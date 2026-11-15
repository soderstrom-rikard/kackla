-- Chat colors: color tokens in sent messages become colors for players with
-- kackla, everyone else sees the message without the tokens. See "Chat
-- colors" in docs/communication-layer.md.
--
-- Tokens, case-insensitive, color the text from here on:
--   :#red:      a basic color (NamedColor in docs/kackla.asn)
--   :#mage:     a class color, as the receiver's game shows it
--   :#epic:     an item quality color, as the receiver's game shows it
--   :#ff8000:   a hex color, also short as :#f80:
--   :#:         back to the channel's color
-- Unknown tokens stay in the message as typed.
--
-- Sending: the tokens are removed and their positions sent as a chatColors
-- message (comm.lua) just before the chat message, in every chat type that
-- can carry addon messages (not SAY and YELL).
--
-- Receiving: a chat filter inserts the color codes into the matching line,
-- matched by sender and a hash of the text. When the colors arrive after the
-- line is shown, the line is recolored.

kacklaColors = {}
local colors = kacklaColors

-- The basic colors, 0xRRGGBB
colors.NAMED = {
    red = 0xFF4040,
    green = 0x40FF40,
    blue = 0x4080FF,
    yellow = 0xFFFF00,
    orange = 0xFF8000,
    purple = 0xA335EE,
    pink = 0xFF80C0,
    cyan = 0x00FFFF,
    white = 0xFFFFFF,
    gray = 0x9D9D9D,
    black = 0x000000,
}

-- Chat types that can carry addon messages, and the addon chat type to use
local ADDON_CHAT_TYPES = {
    GUILD = "GUILD",
    OFFICER = "OFFICER",
    PARTY = "PARTY",
    RAID = "RAID",
    RAID_WARNING = "RAID",
    INSTANCE_CHAT = "INSTANCE_CHAT",
    WHISPER = "WHISPER",
    CHANNEL = "CHANNEL",
}

-- The chat events whose lines can be colored
colors.EVENTS = {
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
}

-- seconds colors wait for their line, and lines for their colors
colors.MATCH_TIMEOUT = 10
-- colors and lines kept waiting at most, the oldest are dropped
colors.MAX_WAITING = 200

local MAX_SPANS = 32
local MAX_START = 255

--------------------------------------------------------------------------------
-- Tokens

-- token name (lower case) -> Color value (docs/kackla.asn), built on first use
local tokenColors

-- Returns the Color value of a token name, or nil when it isn't a color
function colors.tokenColor(name)
    if not tokenColors then
        tokenColors = {}
        local enums = {
            named = kacklaMessages.NamedColor,
            class = kacklaMessages.ClassColor,
            quality = kacklaMessages.ItemQuality,
        }
        for kind, enum in pairs(enums) do
            for _, value in ipairs(enum.values) do
                tokenColors[string.lower(value)] = {kind, value}
            end
        end
    end
    name = string.lower(name)
    if name == "" then
        return {"reset", true}
    end
    if tokenColors[name] then
        return tokenColors[name]
    end
    if string.match(name, "^%x%x%x%x%x%x$") then
        return {"rgb", tonumber(name, 16)}
    end
    if string.match(name, "^%x%x%x$") then
        local r, g, b = string.match(name, "(%x)(%x)(%x)")
        return {"rgb", tonumber(r .. r .. g .. g .. b .. b, 16)}
    end
    return nil
end

-- Returns text without its color tokens, and the spans: {start, color}, where
-- start is the byte offset in the returned text where color starts. Tokens
-- inside links are left alone, at most 32 spans are kept, a token without
-- text after it is dropped.
function colors.parse(text)
    local out, spans = {}, {}
    local length = 0

    local function AddText(s)
        table.insert(out, s)
        length = length + #s
    end

    local function AddSpan(color)
        local last = spans[#spans]
        if last and last.start == length then
            last.color = color
        elseif #spans < MAX_SPANS then
            table.insert(spans, {start = length, color = color})
        end
    end

    local pos = 1
    while pos <= #text do
        local linkStart, linkEnd = string.find(text, "|H.-|h.-|h", pos)
        local tokenStart, tokenEnd, name = string.find(text, ":#(%w*):", pos)
        if tokenStart and (not linkStart or tokenStart < linkStart) then
            local color = colors.tokenColor(name)
            if color then
                AddText(string.sub(text, pos, tokenStart - 1))
                AddSpan(color)
                pos = tokenEnd + 1
            else
                -- not a color, keep the ":" and look again after it
                AddText(string.sub(text, pos, tokenStart))
                pos = tokenStart + 1
            end
        elseif linkStart then
            AddText(string.sub(text, pos, linkEnd))
            pos = linkEnd + 1
        else
            AddText(string.sub(text, pos))
            break
        end
    end

    while spans[#spans] and (spans[#spans].start >= length or spans[#spans].start > MAX_START) do
        table.remove(spans)
    end
    return table.concat(out), spans
end

-- Returns a 16-bit hash of text, the same on every Lua version (no bit
-- operations, values stay small)
function colors.hash(text)
    local h = 0
    for i = 1, #text do
        h = (h * 31 + string.byte(text, i)) % 65521
    end
    return h
end

--------------------------------------------------------------------------------
-- Color codes

-- Returns the RRGGBB number of red, green and blue from 0 to 1
local function ToRgb(r, g, b)
    local function Byte(v)
        return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
    end
    return Byte(r) * 65536 + Byte(g) * 256 + Byte(b)
end

-- Returns the 0xRRGGBB number of a Color value, or nil for reset and colors
-- this client doesn't have (e.g. a newer kackla's)
function colors.rgbOf(color)
    local kind, value = color[1], color[2]
    local rgb
    if kind == "rgb" then
        rgb = value
    elseif kind == "named" then
        rgb = colors.NAMED[value]
    elseif kind == "class" and type(value) == "string" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[string.upper(value)]
        rgb = c and ToRgb(c.r, c.g, c.b)
    elseif kind == "quality" then
        for index, quality in ipairs(kacklaMessages.ItemQuality.values) do
            if quality == value then
                -- Enum.ItemQuality, 0 for poor
                local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[index - 1]
                rgb = c and ToRgb(c.r, c.g, c.b)
            end
        end
    end
    if type(rgb) ~= "number" then
        return nil
    end
    return rgb
end

-- Returns the color code for a Color value: "|cffRRGGBB", "|r" for reset,
-- or nil for colors this client doesn't have (e.g. a newer kackla's)
function colors.code(color)
    if color[1] == "reset" then
        return "|r"
    end
    local rgb = colors.rgbOf(color)
    return rgb and string.format("|cff%06x", rgb)
end

-- Returns red, green and blue from 0 to 1 of a 0xRRGGBB number
function colors.split(rgb)
    local r = math.floor(rgb / 65536)
    local g = math.floor(rgb / 256) % 256
    return r / 255, g / 255, (rgb % 256) / 255
end

-- Returns the 0xRRGGBB number of red, green and blue from 0 to 1
function colors.join(r, g, b)
    return ToRgb(r, g, b)
end

-- Returns the token for a 0xRRGGBB number, e.g. ":#ff8000:"
function colors.hexToken(rgb)
    return string.format(":#%06x:", rgb)
end

-- Patterns of the text that color codes can't be inserted into: links,
-- escape sequences and raid icon tags such as {rt1}
local PROTECTED = {
    "|H.-|h.-|h",
    "|c%x%x%x%x%x%x%x%x",
    "|cn[%w_]+:",
    "|T.-|t",
    "|A.-|a",
    "|K.-|k",
    "|.",
    "{[^{}%s]+}",
}

-- Returns true when a color code can be inserted before byte start + 1 of
-- text: not inside a protected part or a UTF-8 character
local function CanInsertAt(text, start)
    if start < 0 or start >= #text then
        return false
    end
    local byte = string.byte(text, start + 1)
    if byte >= 128 and byte < 192 then
        return false
    end
    for _, pattern in ipairs(PROTECTED) do
        local pos = 1
        while true do
            local s, e = string.find(text, pattern, pos)
            if not s or s > start then
                break
            end
            if start < e then
                return false
            end
            pos = s + 1
        end
    end
    return true
end

-- Returns text with the color codes of spans inserted. Spans that can't be
-- inserted (see CanInsertAt) or whose colors are unknown are skipped. The
-- colors end with the text.
function colors.apply(text, spans)
    local valid = {}
    for _, span in ipairs(spans) do
        local code = type(span.start) == "number" and type(span.color) == "table" and colors.code(span.color)
        if code and CanInsertAt(text, span.start) then
            table.insert(valid, {start = span.start, code = code, index = #valid})
        end
    end
    table.sort(valid, function(a, b)
        return a.start < b.start or (a.start == b.start and a.index < b.index)
    end)

    local out, pos, active = {}, 0, false
    for _, span in ipairs(valid) do
        table.insert(out, string.sub(text, pos + 1, span.start))
        pos = span.start
        if span.code == "|r" then
            if active then
                table.insert(out, "|r")
            end
            active = false
        else
            table.insert(out, (active and "|r" or "") .. span.code)
            active = true
        end
    end
    table.insert(out, string.sub(text, pos + 1))
    if active then
        table.insert(out, "|r")
    end
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- Matching colors and lines

local waitingColors = {} -- key -> {spans, time}
local waitingLines = {}  -- key -> {lineID, time}

-- Returns the name of a sender for matching: lower case, without realm
local function NormalizeName(name)
    return (string.gsub(string.lower(tostring(name)), "%-.*$", ""))
end

-- Returns the key matching colors and lines from sender with text hash
local function Key(sender, hash)
    return NormalizeName(sender) .. ":" .. hash
end

-- Returns entry when it is younger than MATCH_TIMEOUT, else nil
local function Fresh(entry)
    if entry and GetTime() - entry.time <= colors.MATCH_TIMEOUT then
        return entry
    end
end

-- Removes entries older than MATCH_TIMEOUT from waiting, and the oldest when
-- there are too many
local function Prune(waiting)
    local now = GetTime()
    local count, oldestKey, oldest = 0, nil, nil
    for key, entry in pairs(waiting) do
        if now - entry.time > colors.MATCH_TIMEOUT then
            waiting[key] = nil
        else
            count = count + 1
            if not oldest or entry.time < oldest then
                oldestKey, oldest = key, entry.time
            end
        end
    end
    if count >= colors.MAX_WAITING then
        waiting[oldestKey] = nil
    end
end

-- Recolors the shown line lineID in every chat frame
local function Recolor(lineID, spans)
    local function Matches(message, r, g, b, infoID, accessID, typeID, event, eventArgs)
        return type(eventArgs) == "table" and eventArgs[11] == lineID
    end
    local function Colored(message, r, g, b, infoID, accessID, typeID, event, eventArgs, MessageFormatter, ...)
        if type(MessageFormatter) ~= "function" or type(eventArgs[1]) ~= "string" then
            return message, r, g, b, infoID, accessID, typeID, event, eventArgs, MessageFormatter, ...
        end
        local colored = colors.apply(eventArgs[1], spans)
        return MessageFormatter(colored) or message, r, g, b, infoID, accessID, typeID, event, eventArgs,
               MessageFormatter, ...
    end
    ChatFrameUtil.ForEachChatFrame(function(chatFrame)
        chatFrame:TransformMessages(Matches, Colored)
    end)
end

-- Handles a received chatColors message (comm.lua handler)
function colors.receive(value, info)
    if type(value) ~= "table" or type(value.spans) ~= "table" then
        return
    end
    local key = Key(info.sender, value.textHash)
    local line = Fresh(waitingLines[key])
    if line then
        waitingLines[key] = nil
        Recolor(line.lineID, value.spans)
        return
    end
    Prune(waitingColors)
    waitingColors[key] = {spans = value.spans, time = GetTime()}
end

-- The chat message filter: colors the line when its colors arrived, else
-- remembers the line for colors arriving later. Returns the arguments to
-- show, as ChatFrameUtil.AddMessageEventFilter filters do.
function colors.filter(chatFrame, event, text, author, ...)
    if type(text) ~= "string" then
        return false, text, author, ...
    end
    -- the author of a sent whisper's line is its recipient
    local sender = event == "CHAT_MSG_WHISPER_INFORM" and colors.me or author
    local key = Key(sender, colors.hash(text))
    local lineID = select(9, ...)
    local waiting = Fresh(waitingColors[key])
    -- the filter runs once per chat frame showing the line, the colors stay
    -- for the line they first colored, not a later line with the same text
    if waiting and (waiting.lineID == nil or waiting.lineID == lineID) then
        waiting.lineID = lineID
        return false, colors.apply(text, waiting.spans), author, ...
    end
    if lineID then
        Prune(waitingLines)
        waitingLines[key] = {lineID = lineID, time = GetTime()}
    end
    return false, text, author, ...
end

-- Returns the number of colors and lines waiting to be matched, for tests
function colors.waitingCount()
    local count = 0
    for _ in pairs(waitingColors) do count = count + 1 end
    for _ in pairs(waitingLines) do count = count + 1 end
    return count
end

--------------------------------------------------------------------------------
-- Sending

-- Sends the colors of a chat message about to be sent: text is the message
-- without tokens, chatType and target as for SendChatMessage. Chat types
-- that can't carry addon messages are skipped, the message is then sent
-- without colors. Never raises, so chat always works.
function colors.send(text, spans, chatType, target)
    local addonChatType = ADDON_CHAT_TYPES[chatType]
    if #spans == 0 or not addonChatType then
        return
    end
    local hash = colors.hash(text)
    local message = {"chatColors", {textHash = hash, spans = spans}}
    pcall(kacklaComm.send, message, addonChatType, target and tostring(target), {priority = 1, expiresIn = 5})
    -- a whisper's colors don't come back, the line of the sent whisper is
    -- colored from here
    if chatType == "WHISPER" then
        Prune(waitingColors)
        waitingColors[Key(colors.me, hash)] = {spans = spans, time = GetTime()}
    end
end

-- Sets up receiving, call once when kackla loads
function colors.init()
    local first, last = UnitName("player")
    colors.me = (last and last ~= "") and (first .. " " .. last) or first
    kacklaComm.on("chatColors", colors.receive)
    for _, event in ipairs(colors.EVENTS) do
        ChatFrameUtil.AddMessageEventFilter(event, colors.filter)
    end
end

-- Forgets the waiting colors and lines, for tests
function colors.reset()
    waitingColors, waitingLines = {}, {}
end

return kacklaColors
