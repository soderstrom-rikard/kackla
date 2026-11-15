-- Tests chat colors, run with make test
require("testsetup")

local UNKNOWN = kacklaUper.UNKNOWN
local RED, BLUE = {"named", "red"}, {"named", "blue"}

-- Returns true when a and b are equal, comparing tables by content
local function deepEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- Returns the chat event arguments after text and author (languageName,
-- channelName, playerName2, specialFlags, zoneChannelID, channelIndex,
-- channelBaseName, languageID), then lineID as the 11th argument
local function EventArgs(lineID)
    return "", "", "", "", 0, 0, "", 0, lineID
end

-- Tests the token names
function checkTokens()
    print("Verify color tokens start")
    assert(deepEqual(kacklaColors.tokenColor("red"), RED), "red")
    assert(deepEqual(kacklaColors.tokenColor("RED"), RED), "names are case-insensitive")
    assert(deepEqual(kacklaColors.tokenColor("Mage"), {"class", "mage"}), "class")
    assert(deepEqual(kacklaColors.tokenColor("deathknight"), {"class", "deathKnight"}), "class in lower case")
    assert(deepEqual(kacklaColors.tokenColor("epic"), {"quality", "epic"}), "quality")
    assert(deepEqual(kacklaColors.tokenColor("ff8000"), {"rgb", 0xFF8000}), "hex")
    assert(deepEqual(kacklaColors.tokenColor("F80"), {"rgb", 0xFF8800}), "short hex")
    assert(deepEqual(kacklaColors.tokenColor(""), {"reset", true}), "reset")
    for _, invalid in ipairs({"nope", "12345", "ff80000", "ggg"}) do
        assert(kacklaColors.tokenColor(invalid) == nil, invalid .. " isn't a color")
    end
    print("Verify color tokens done")
end

-- Tests removing tokens and their positions
function checkParse()
    print("Verify color parsing start")
    local function Check(name, input, text, spans)
        local gotText, gotSpans = kacklaColors.parse(input)
        assert(gotText == text, name .. ": text '" .. gotText .. "'")
        assert(deepEqual(gotSpans, spans), name .. ": spans")
    end
    Check("one", "hello :#red:world", "hello world", {{start = 6, color = RED}})
    Check("reset", ":#red:a:#:b", "ab", {{start = 0, color = RED}, {start = 1, color = {"reset", true}}})
    Check("last of adjacent tokens wins", ":#red::#blue:x", "x", {{start = 0, color = BLUE}})
    Check("unknown token stays", ":#nope:x", ":#nope:x", {})
    Check("unclosed token stays", "a :#red b", "a :#red b", {})
    Check("token at the end is dropped", "hi:#red:", "hi", {})
    Check("no tokens", "plain", "plain", {})
    Check("tokens in links stay", "|Hitem:12:#red:|h[x]|h :#red:b", "|Hitem:12:#red:|h[x]|h b",
          {{start = 23, color = RED}})

    local many = string.rep(":#red:a", 40)
    local text, spans = kacklaColors.parse(many)
    assert(text == string.rep("a", 40) and #spans == 32, "at most 32 spans, got " .. #spans)
    text, spans = kacklaColors.parse(string.rep("x", 260) .. ":#red:y")
    assert(#spans == 0, "a start over 255 is dropped")
    print("Verify color parsing done")
end

-- Tests the hash, values computed independently with Python
function checkHash()
    assert(kacklaColors.hash("") == 0, "empty")
    assert(kacklaColors.hash("a") == 97, "a")
    assert(kacklaColors.hash("ab") == 3105, "ab")
    assert(kacklaColors.hash("Hello world") == 32270, "Hello world")
    assert(kacklaColors.hash(string.rep("x", 300)) == 34391, "300 x")
end

-- Tests the helpers for 0xRRGGBB numbers
function checkRgbHelpers()
    local r, g, b = kacklaColors.split(0xFF8000)
    assert(r == 1 and g == 128 / 255 and b == 0, "split")
    for _, rgb in ipairs({0x000000, 0xFFFFFF, 0xFF8000, 0x123456, 0x0080FF}) do
        assert(kacklaColors.join(kacklaColors.split(rgb)) == rgb, "join(split) of " .. rgb)
    end
    assert(kacklaColors.join(2, -1, 0.5) == 0xFF0080, "join clamps")
    assert(kacklaColors.hexToken(0x0080FF) == ":#0080ff:", "hex token")
    assert(kacklaColors.rgbOf(RED) == 0xFF4040, "rgbOf named")
    assert(kacklaColors.rgbOf({"reset", true}) == nil, "reset has no rgb")
    assert(deepEqual(kacklaColors.tokenColor(string.sub(kacklaColors.hexToken(0x0080FF), 3, -2)), {"rgb", 0x0080FF}),
           "hex tokens parse back")
end

-- Tests color codes and inserting them
function checkApply()
    print("Verify color codes start")
    RAID_CLASS_COLORS = {MAGE = {r = 0.25, g = 0.78, b = 0.92}}
    ITEM_QUALITY_COLORS = {[4] = {r = 0.64, g = 0.21, b = 0.93}}
    assert(kacklaColors.code({"rgb", 0xFF8000}) == "|cffff8000", "rgb")
    assert(kacklaColors.code(RED) == "|cffff4040", "named")
    assert(kacklaColors.code({"class", "mage"}) == "|cff40c7eb", "class " .. tostring(kacklaColors.code({"class", "mage"})))
    assert(kacklaColors.code({"quality", "epic"}) == "|cffa336ed", "quality")
    assert(kacklaColors.code({"reset", true}) == "|r", "reset")
    assert(kacklaColors.code({"class", "evoker"}) == nil, "a class this client lacks")
    assert(kacklaColors.code({"named", UNKNOWN}) == nil, "a newer named color")
    assert(kacklaColors.code({UNKNOWN, 0}) == nil, "a newer kind of color")
    assert(kacklaColors.code({"class", UNKNOWN}) == nil, "a newer class")

    local function Check(name, text, spans, expected)
        local got = kacklaColors.apply(text, spans)
        assert(got == expected, name .. ": got '" .. got .. "'")
    end
    Check("one", "hello world", {{start = 6, color = RED}}, "hello |cffff4040world|r")
    Check("reset", "abc", {{start = 0, color = RED}, {start = 1, color = {"reset", true}}, {start = 2, color = BLUE}},
          "|cffff4040a|rb|cff4080ffc|r")
    Check("reset without color", "ab", {{start = 0, color = {"reset", true}}}, "ab")
    Check("change", "abc", {{start = 0, color = RED}, {start = 1, color = BLUE}}, "|cffff4040a|r|cff4080ffbc|r")
    Check("unsorted", "abc", {{start = 1, color = BLUE}, {start = 0, color = RED}}, "|cffff4040a|r|cff4080ffbc|r")

    -- untrusted spans that would break the line are skipped
    local link = "a |cffa335ee|Hitem:1|h[x]|h|r b"
    for _, start in ipairs({3, 5, 13, 20, 24, 28}) do
        Check("inside a link at " .. start, link, {{start = start, color = RED}}, link)
    end
    Check("before a link", link, {{start = 2, color = RED}}, "a |cffff4040|cffa335ee|Hitem:1|h[x]|h|r b|r")
    Check("inside {rt1}", "a {rt1} b", {{start = 4, color = RED}}, "a {rt1} b")
    Check("inside ☺", "a☺", {{start = 2, color = RED}}, "a☺")
    Check("before ☺", "a☺", {{start = 1, color = RED}}, "a|cffff4040☺|r")
    Check("inside ||", "a||b", {{start = 2, color = RED}}, "a||b")
    Check("at the end", "ab", {{start = 2, color = RED}}, "ab")
    Check("negative", "ab", {{start = -1, color = RED}}, "ab")
    Check("not a number", "ab", {{start = "1", color = RED}}, "ab")
    Check("no color", "ab", {{start = 1}}, "ab")
    Check("unknown color", "ab", {{start = 1, color = {UNKNOWN, 3}}}, "ab")
    print("Verify color codes done")
end

-- Sends msg through the SendChatMessage hook to channel, returns the chat
-- text sent and the addon messages queued
local function SendThroughHook(msg, channel, target)
    local sentText
    local queued = {}
    local originalSend = kacklaComm.send
    sut.hooks["SendChatMessage"] = function(text) sentText = text end
    kacklaComm.send = function(message, chatType, addonTarget, options)
        table.insert(queued, {message = message, chatType = chatType, target = addonTarget, options = options})
        return true
    end
    sut:SendChatMessage(msg, channel, nil, target)
    kacklaComm.send = originalSend
    return sentText, queued
end

-- Tests sending: tokens removed in every channel, colors sent where possible
function checkSending()
    print("Verify color sending start")
    local originalHook = sut.hooks["SendChatMessage"]
    kacklaColors.reset()
    KacklaDb = {alias = "A", format = "[%s] %s", channels = nil}
    KacklaPerCharacterDb = {}

    -- in an active channel the positions are those after the alias
    local text, queued = SendThroughHook("hi :#red:there", "GUILD")
    assert(text == "[A] hi there", "guild text '" .. tostring(text) .. "'")
    assert(#queued == 1 and queued[1].chatType == "GUILD" and queued[1].target == nil, "guild colors queued")
    assert(deepEqual(queued[1].message, {"chatColors", {textHash = 56406, spans = {{start = 7, color = RED}}}}),
           "guild colors message")
    assert(queued[1].options.priority == 1 and queued[1].options.expiresIn == 5, "colors are urgent")

    -- in an inactive channel there is no alias, but colors still work
    KacklaDb.channels = {SAY = true}
    text, queued = SendThroughHook("hi :#red:there", "GUILD")
    assert(text == "hi there" and #queued == 1 and queued[1].message[2].spans[1].start == 3, "inactive channel")

    -- SAY and EMOTE can't carry addon messages: no colors, no tokens
    text, queued = SendThroughHook("hi :#red:there", "SAY")
    assert(text == "[A] hi there" and #queued == 0, "SAY sends no colors")
    text, queued = SendThroughHook("waves :#red:wildly", "EMOTE")
    assert(text == "waves wildly" and #queued == 0, "EMOTE sends no colors")

    KacklaDb.channels = nil
    text, queued = SendThroughHook(":#epic:loot", "RAID_WARNING")
    assert(#queued == 1 and queued[1].chatType == "RAID", "raid warnings go to RAID")
    text, queued = SendThroughHook(":#red:x", "CHANNEL", 5)
    assert(#queued == 1 and queued[1].chatType == "CHANNEL" and queued[1].target == "5", "channel by number")
    text, queued = SendThroughHook("no tokens", "GUILD")
    assert(text == "[A] no tokens" and #queued == 0, "no tokens, no colors")

    -- the line of a sent whisper is colored locally
    text, queued = SendThroughHook(":#red:psst", "WHISPER", "Bob")
    assert(#queued == 1 and queued[1].target == "Bob", "whisper colors go to the recipient")
    local _, shown = kacklaColors.filter(nil, "CHAT_MSG_WHISPER_INFORM", text, "Bob", EventArgs(1))
    assert(shown == "[A] |cffff4040psst|r", "own whisper line '" .. tostring(shown) .. "'")

    sut.hooks["SendChatMessage"] = originalHook
    print("Verify color sending done")
end

-- Simulated chat frames for recoloring: lines {message, eventArgs} shown
-- with a formatter adding the sender
local function ChatFrames(lines)
    local function Formatter(text) return "[Bob]: " .. text end
    local frame = {}
    function frame:TransformMessages(predicate, transform)
        for _, line in ipairs(lines) do
            if predicate(line.message, 1, 1, 1, 0, 0, 0, "CHAT_MSG_GUILD", line.eventArgs, Formatter) then
                line.message = transform(line.message, 1, 1, 1, 0, 0, 0, "CHAT_MSG_GUILD", line.eventArgs, Formatter)
            end
        end
    end
    ChatFrameUtil.ForEachChatFrame = function(func)
        func(frame)
        func(frame)
    end
end

-- Tests receiving: colors before and after their line
function checkReceiving()
    print("Verify color receiving start")
    local text = "hello world"
    local spans = {{start = 6, color = RED}}
    local colored = "hello |cffff4040world|r"

    -- colors first, realms are ignored, every chat frame colors the line
    kacklaColors.reset()
    now = 100
    kacklaColors.receive({textHash = kacklaColors.hash(text), spans = spans}, {sender = "Bob-Realm"})
    local _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "bob", EventArgs(7))
    assert(shown == colored, "colors first: '" .. tostring(shown) .. "'")
    _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "bob", EventArgs(7))
    assert(shown == colored, "the same line in a second chat frame")
    _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "Bob", EventArgs(8))
    assert(shown == text, "a later line with the same text isn't colored")
    _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "Carol", EventArgs(9))
    assert(shown == text, "another sender's line isn't colored")

    -- expired colors aren't used
    kacklaColors.reset()
    kacklaColors.receive({textHash = kacklaColors.hash(text), spans = spans}, {sender = "Bob"})
    now = 111
    _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "Bob", EventArgs(10))
    assert(shown == text, "expired colors")

    -- the line first: recolored when the colors arrive, in every chat frame
    kacklaColors.reset()
    local lines = {
        {message = "[Bob]: " .. text, eventArgs = {text, "Bob", [11] = 20}},
        {message = "[Bob]: other", eventArgs = {"other", "Bob", [11] = 21}},
    }
    ChatFrames(lines)
    _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "Bob", EventArgs(20))
    assert(shown == text, "line without colors yet")
    kacklaColors.receive({textHash = kacklaColors.hash(text), spans = spans}, {sender = "Bob"})
    assert(lines[1].message == "[Bob]: " .. colored, "recolored '" .. lines[1].message .. "'")
    assert(lines[2].message == "[Bob]: other", "other lines unchanged")
    assert(kacklaColors.waitingCount() == 0, "nothing left waiting")

    -- a line waiting longer than the timeout isn't recolored
    kacklaColors.reset()
    lines[1].message = "[Bob]: " .. text
    kacklaColors.filter(nil, "CHAT_MSG_GUILD", text, "Bob", EventArgs(20))
    now = now + 11
    kacklaColors.receive({textHash = kacklaColors.hash(text), spans = spans}, {sender = "Bob"})
    assert(lines[1].message == "[Bob]: " .. text, "too late to recolor")

    -- untrusted messages don't raise errors, and waiting is limited
    kacklaColors.reset()
    kacklaColors.receive({textHash = 1, spans = "x"}, {sender = "Mallory"})
    kacklaColors.receive({textHash = 1}, {sender = "Mallory"})
    kacklaColors.receive({textHash = 2, spans = {{start = 0, color = {UNKNOWN, 1}}}}, {sender = "Mallory"})
    _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", "ab", "Mallory", EventArgs(30))
    for i = 1, 500 do
        kacklaColors.receive({textHash = i, spans = spans}, {sender = "Mallory"})
    end
    assert(kacklaColors.waitingCount() <= kacklaColors.MAX_WAITING + 1, "waiting is limited")
    print("Verify color receiving done")
end

-- Tests sending and receiving together, through the communication layer
-- with addon messages looping back like guild messages do
function checkEndToEnd()
    print("Verify colors end to end start")
    kacklaColors.reset()
    kacklaComm.reset()
    kacklaComm.on("chatColors", kacklaColors.receive)
    KacklaDb = {alias = "A", format = "[%s] %s", channels = nil}
    local originalSendAddon = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function(prefix, message, chatType, target)
        kacklaComm.onAddonMessage(prefix, message, chatType, kacklaColors.me)
        return true
    end
    local sentText
    local originalHook = sut.hooks["SendChatMessage"]
    sut.hooks["SendChatMessage"] = function(text) sentText = text end

    sut:SendChatMessage("loot: :#epic:Thunderfury:#: !", "GUILD")
    local _, shown = kacklaColors.filter(nil, "CHAT_MSG_GUILD", sentText, kacklaColors.me, EventArgs(40))
    assert(shown == "[A] loot: |cffa336edThunderfury|r !", "end to end '" .. tostring(shown) .. "'")

    sut.hooks["SendChatMessage"] = originalHook
    C_ChatInfo.SendAddonMessage = originalSendAddon
    print("Verify colors end to end done")
end

checkTokens()
checkParse()
checkHash()
checkRgbHelpers()
checkApply()
checkSending()
checkReceiving()
checkEndToEnd()
