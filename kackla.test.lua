_G = {}
C_ChatInfo = {
    SendChatMessage = function(msg, channel, language, target)
        error("we are running the non-hooked SendChatInfo")
    end
}
-- Channels the test player has joined, by channel number
joinedChannels = {
    [1] = "General - Stormwind City",
    [5] = "MyChannel",
}
-- Mirrors the WoW API: by number returns id and name, by name returns the
-- id or 0 when not joined
function GetChannelName(channel)
    if type(channel) == "number" then
        if joinedChannels[channel] then
            return channel, joinedChannels[channel]
        end
        return 0, nil
    end
    for id, name in pairs(joinedChannels) do
        local baseName = name:match("^(.-) %- ") or name
        if string.upper(name) == string.upper(channel)
                or string.upper(baseName) == string.upper(channel) then
            return id, name
        end
    end
    return 0, nil
end
SlashCmdList = {}
registeredEvents = {}

function Mixin(table)
    table.name = "kacklaTest"
    table.RegisterEvent = function(eventname)
        registeredEvents[eventname] = true
    end
    return table
end

function UnitName(unit)
    local units = {
        player = {name = "tester", realm = "bob"}
    }
    return units[unit].name, units[unit].realm
end

scriptDir = (function()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)") or "./"
end)()

print("script dir: ", scriptDir)
require("emoticons")
require("kackla")
require("emoticonpicker")

sut = kacklaFrameMixin
sut:OnLoad()
sut:ADDON_LOADED("kackla")
sut.slashCommands.help.exec(sut.slashCommands)

print("Generating updated README.md.out with an updated commands list")
inCommandsSection = false
fileObject = io.open( scriptDir .. "README.md.out", "w")
for line in io.lines(scriptDir .. "README.md") do
    if line == "## Formatting" then
        inCommandsSection = false

        fileObject:write("\n```txt\n"
            .. sut.slashCommands.help.make(sut.slashCommands)
            .. "\n```\n\n")

    end

    if not inCommandsSection then
        fileObject:write(line .. "\n")
    end

    if line == "## Commands" then
        inCommandsSection = true
    end
end
fileObject:close()

-- Compares two sets ({KEY = true}), nil only equals nil
function compareSets(left, right)
    if left == nil or right == nil then
        return left == right
    end
    for k in pairs(left) do
        if right[k] ~= true then return false end
    end
    for k in pairs(right) do
        if left[k] ~= true then return false end
    end
    return true
end

function setToString(set)
    if set == nil then return "nil" end
    local names = {}
    for k in pairs(set) do table.insert(names, k) end
    table.sort(names)
    return "{" .. table.concat(names, ",") .. "}"
end

-- Runs func and returns everything it printed, one string per print call
function capturePrint(func)
    local printed = {}
    local originalPrint = print
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring(select(i, ...))
        end
        table.insert(printed, table.concat(parts, " "))
    end
    local ok, err = pcall(func)
    print = originalPrint
    assert(ok, err)
    return printed
end

function checkChannels(command, getDb, input, expected)
    getDb().channels = "garbage"
    sut:slashCommandHandler(command .. " " .. input)
    assert(compareSets(getDb().channels, expected), command .. " '" .. input
           .. "': expected " .. setToString(expected)
           .. " got " .. setToString(getDb().channels))
end

function checkChannelCommands()
    print("Verify channel commands start")
    KacklaDb = {}
    KacklaPerCharacterDb = {}

    for _, test in ipairs({
        {command = "setChannels",       getDb = function() return KacklaDb end},
        {command = "setPlayerChannels", getDb = function() return KacklaPerCharacterDb end},
    }) do
        local c, db = test.command, test.getDb
        checkChannels(c, db, "GUILD,SAY", {GUILD = true, SAY = true})
        checkChannels(c, db, " guild , Say ", {GUILD = true, SAY = true})
        checkChannels(c, db, "GUILD,,GUILD,", {GUILD = true})
        checkChannels(c, db, "", nil)
        checkChannels(c, db, " , ", nil)
        -- custom channel, case-insensitive
        checkChannels(c, db, "MyChannel", {MYCHANNEL = true})
        -- zone channel by its base name
        checkChannels(c, db, "General,PARTY", {GENERAL = true, PARTY = true})

        -- non existing channels are stored, but warned about
        local printed = capturePrint(function()
            checkChannels(c, db, "NoSuchChannel,SAY", {NOSUCHCHANNEL = true, SAY = true})
        end)
        assert(#printed == 1 and printed[1]:find("NOSUCHCHANNEL"),
               "expected one warning about NOSUCHCHANNEL, got: " .. table.concat(printed, " | "))

        -- known chat types, joined channels and ALL are not warned about
        local printed = capturePrint(function()
            checkChannels(c, db, "SAY,MyChannel,General", {SAY = true, MYCHANNEL = true, GENERAL = true})
            checkChannels(c, db, "all", {})
        end)
        assert(#printed == 0, "expected no warnings, got: " .. table.concat(printed, " | "))

        -- ALL is stored as the empty set and wins over any other listed channel
        checkChannels(c, db, "ALL", {})
        checkChannels(c, db, "SAY, All ,MyChannel", {})
    end

    -- getters
    KacklaDb = {channels = {SAY = true, GUILD = true}}
    KacklaPerCharacterDb = {channels = nil}
    local printed = capturePrint(function() sut:slashCommandHandler("getChannels") end)
    assert(printed[1] == "GUILD,SAY", "getChannels got '" .. tostring(printed[1]) .. "'")
    printed = capturePrint(function() sut:slashCommandHandler("getPlayerChannels") end)
    assert(printed[1] == "global", "getPlayerChannels got '" .. tostring(printed[1]) .. "'")
    KacklaPerCharacterDb = {channels = {}}
    printed = capturePrint(function() sut:slashCommandHandler("getPlayerChannels") end)
    assert(printed[1] == "ALL", "getPlayerChannels got '" .. tostring(printed[1]) .. "'")
    KacklaDb = {channels = nil}
    printed = capturePrint(function() sut:slashCommandHandler("getChannels") end)
    assert(printed[1] == "ALL", "getChannels got '" .. tostring(printed[1]) .. "'")
    KacklaDb = {channels = {}}
    printed = capturePrint(function() sut:slashCommandHandler("getChannels") end)
    assert(printed[1] == "ALL", "getChannels got '" .. tostring(printed[1]) .. "'")

    print("Verify channel commands done")
end

function checkIsChannelActive()
    print("Verify channel matching start")

    local function check(global, player, chatType, target, expected)
        KacklaDb = {channels = global}
        KacklaPerCharacterDb = {channels = player}
        local active = sut:IsChannelActive(chatType, target)
        assert(active == expected, "global " .. setToString(global)
               .. " player " .. setToString(player) .. " " .. tostring(chatType)
               .. " " .. tostring(target) .. ": expected " .. tostring(expected)
               .. " got " .. tostring(active))
    end

    -- nil everywhere means all channels
    check(nil, nil, "SAY", nil, true)
    check(nil, nil, "CHANNEL", 5, true)
    check(nil, nil, "CHANNEL", 42, true)

    -- global only
    check({SAY = true}, nil, "SAY", nil, true)
    check({SAY = true}, nil, "say", nil, true)
    check({SAY = true}, nil, nil, nil, true) -- nil chatType defaults to SAY
    check({SAY = true}, nil, "GUILD", nil, false)

    -- player overrides global
    check({SAY = true}, {GUILD = true}, "GUILD", nil, true)
    check({SAY = true}, {GUILD = true}, "SAY", nil, false)
    check(nil, {GUILD = true}, "SAY", nil, false)

    -- {} means all channels, so a player can override a restricted global
    check({}, nil, "GUILD", nil, true)
    check({SAY = true}, {}, "GUILD", nil, true)
    check({SAY = true}, {}, "CHANNEL", 42, true)
    check({}, {SAY = true}, "GUILD", nil, false)

    -- custom channels, matched on name by channel number
    check({MYCHANNEL = true}, nil, "CHANNEL", 5, true)
    check({MYCHANNEL = true}, nil, "CHANNEL", 1, false)
    check({MYCHANNEL = true}, nil, "SAY", nil, false)
    check({GENERAL = true}, nil, "CHANNEL", 1, true)
    check({["GENERAL - STORMWIND CITY"] = true}, nil, "CHANNEL", 1, true)
    check({CHANNEL = true}, nil, "CHANNEL", 1, true)
    check({CHANNEL = true}, nil, "CHANNEL", 5, true)

    -- non existing channels never match
    check({NOSUCHCHANNEL = true}, nil, "CHANNEL", 5, false)
    check({NOSUCHCHANNEL = true}, nil, "CHANNEL", 42, false)
    check({MYCHANNEL = true}, nil, "CHANNEL", 42, false)

    print("Verify channel matching done")
end

function checkSendChatMessageHook()
    print("Verify SendChatMessage hook start")
    local originalHook = sut.hooks["SendChatMessage"]
    local sent
    sut.hooks["SendChatMessage"] = function(msg, channel, language, target)
        sent = {msg = msg, channel = channel, target = target}
    end

    KacklaDb = {alias = "Bob", format = "[%s] %s", channels = {GUILD = true, MYCHANNEL = true}}
    KacklaPerCharacterDb = {}

    C_ChatInfo.SendChatMessage("hi", "GUILD")
    assert(sent.msg == "[Bob] hi", "GUILD should be aliased, got '" .. sent.msg .. "'")
    C_ChatInfo.SendChatMessage("hi", "CHANNEL", nil, 5)
    assert(sent.msg == "[Bob] hi" and sent.target == 5, "MyChannel should be aliased, got '" .. sent.msg .. "'")
    C_ChatInfo.SendChatMessage("hi", "SAY")
    assert(sent.msg == "hi", "SAY should not be aliased, got '" .. sent.msg .. "'")
    C_ChatInfo.SendChatMessage("hi", "CHANNEL", nil, 1)
    assert(sent.msg == "hi", "General should not be aliased, got '" .. sent.msg .. "'")

    -- player ALL overrides the restricted global channels
    sut:slashCommandHandler("setPlayerChannels ALL")
    C_ChatInfo.SendChatMessage("hi", "SAY")
    assert(sent.msg == "[Bob] hi", "SAY should be aliased with player ALL, got '" .. sent.msg .. "'")

    -- no player channels, so the global channels apply again
    sut:slashCommandHandler("setPlayerChannels")
    C_ChatInfo.SendChatMessage("hi", "SAY")
    assert(sent.msg == "hi", "SAY should not be aliased without player channels, got '" .. sent.msg .. "'")

    -- global ALL and no global channels both alias all channels
    sut:slashCommandHandler("setChannels ALL")
    C_ChatInfo.SendChatMessage("hi", "SAY")
    assert(sent.msg == "[Bob] hi", "SAY should be aliased after global ALL, got '" .. sent.msg .. "'")
    sut:slashCommandHandler("setChannels")
    C_ChatInfo.SendChatMessage("hi", "SAY")
    assert(sent.msg == "[Bob] hi", "SAY should be aliased without global channels, got '" .. sent.msg .. "'")

    sut.hooks["SendChatMessage"] = originalHook
    print("Verify SendChatMessage hook done")
end

function checkEmoticons()
    print("Verify emoticons start")

    for name, symbol in pairs(kacklaEmoticons) do
        assert(name:match("^[%l%d]+$"), "emoticon name '" .. name
               .. "' should be lowercase letters and digits")
        assert(type(symbol) == "string" and #symbol > 0, name .. ": missing symbol")
    end

    local function check(input, expected)
        local got = kacklaReplaceEmoticons(input)
        assert(got == expected, "'" .. input .. "': expected '" .. expected
               .. "' got '" .. got .. "'")
    end

    check("hello :sun:", "hello ☼")
    check(":SUN: :Heart:", "☼ ♥")
    check(":sun::heart:", "☼♥")
    check("x:sun:y", "x☼y")
    check(":nosuch: :sun", ":nosuch: :sun")
    check("meet at 12:30:45", "meet at 12:30:45")
    check("", "")
    -- links are left untouched, both their data and their text
    local link = "|cff1eff00|Hitem:19019:up:0|h[:sun: sword]|h|r"
    check(link .. " :heart:", link .. " ♥")
    check(":heart: " .. link .. " :heart: " .. link, "♥ " .. link .. " ♥ " .. link)

    -- the list shows every emoticon and keeps lines short
    local list = sut:EmoticonList()
    for name, symbol in pairs(kacklaEmoticons) do
        assert(list:find(":" .. name .. ": " .. symbol, 1, true), "list is missing " .. name)
    end
    for index, tags in ipairs(kacklaRaidIcons) do
        assert(list:find(tags[1] .. " " .. tags[2] .. " |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_"
                         .. index .. ":0|t", 1, true), "list is missing raid icon " .. tags[1])
        assert(kacklaRaidIconTexture(index) == "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_"
                         .. index .. ":0|t", "unexpected raid icon texture for " .. index)
    end
    for line in string.gmatch(list, "[^\n]+") do
        -- textures take one character's space, not their escape's length
        local shown = line:gsub("|T.-|t", "#")
        assert(#shown <= 54, "emoticon list line too long: '" .. line .. "'")
    end

    -- the hook replaces emoticons only in channels where the alias is used
    local originalHook = sut.hooks["SendChatMessage"]
    local sent
    sut.hooks["SendChatMessage"] = function(msg) sent = msg end
    KacklaDb = {alias = "Bob :sun:", format = "[%s] %s", channels = {GUILD = true}}
    KacklaPerCharacterDb = {}
    C_ChatInfo.SendChatMessage("hi :heart:", "GUILD")
    assert(sent == "[Bob ☼] hi ♥", "aliased message got '" .. sent .. "'")
    C_ChatInfo.SendChatMessage("hi :heart:", "SAY")
    assert(sent == "hi :heart:", "message in inactive channel got '" .. sent .. "'")
    KacklaPerCharacterDb = {channels = {}}
    C_ChatInfo.SendChatMessage("hi :heart:", "SAY")
    assert(sent == "[Bob ☼] hi ♥", "message with player ALL got '" .. sent .. "'")
    sut.hooks["SendChatMessage"] = originalHook

    print("Verify emoticons done")
end

function checkEmoticonPicker()
    print("Verify emoticon picker start")

    -- chat edit box mocks
    local inserted, opened
    local editBox = {Insert = function(self, text) inserted = text end}
    local activeEditBox
    ChatFrameUtil = {
        GetActiveWindow = function() return activeEditBox end,
        OpenChat = function(text)
            assert(text == nil, "OpenChat should get nil text, got '" .. tostring(text) .. "'")
            opened = true
            return editBox
        end,
    }

    activeEditBox = editBox
    kacklaInsertIntoChat(":heart:")
    assert(inserted == ":heart:" and not opened, "should insert into the active edit box")
    activeEditBox = nil
    inserted = nil
    kacklaInsertIntoChat("{rt8}")
    assert(inserted == "{rt8}" and opened, "should open chat and then insert")

    -- menu mocks, collecting the created entries
    MenuConstants = {VerticalGridDirection = 2}
    MenuResponse = {Open = 1, Refresh = 2, Close = 3, CloseAll = 4}
    ChatFontNormal = {name = "ChatFontNormal"}
    AnchorUtil = {CreateAnchor = function(...) return {...} end}
    local tooltipLines
    GameTooltip_SetTitle = function(tooltip, text) tooltipLines = {text} end
    GameTooltip_AddNormalLine = function(tooltip, text) table.insert(tooltipLines, text) end
    local entries, grid = {}, nil
    local rootDescription = {
        SetTag = function() end,
        CreateButton = function(self, label, callback)
            local entry = {label = label, callback = callback}
            table.insert(entries, entry)
            return {
                SetTooltip = function(_, func) entry.tooltip = func end,
                AddInitializer = function(_, func) entry.initializer = func end,
            }
        end,
        SetGridMode = function(self, direction, columns) grid = {direction, columns} end,
    }

    NORMAL_FONT_COLOR = {GetRGB = function() return 1, 0.82, 0 end}
    local button = {Label = {
        SetTextColor = function(self, r, g, b) self.color = {r, g, b} end,
        SetTextScale = function(self, scale) self.scale = scale end,
    }}
    for k, v in pairs(KacklaEmoticonButtonMixin) do button[k] = v end
    button.SetText = function(self, text) self.text = text end
    button.SetMenuAnchor = function(self, anchor) self.anchor = anchor end
    button.SetupMenu = function(self, generator) generator(self, rootDescription) end
    button:OnLoad()

    assert(button.text == "☺", "button text should be ☺, got '" .. tostring(button.text) .. "'")
    assert(button.Label.color[1] == 1 and button.Label.color[2] == 0.82 and button.Label.color[3] == 0,
           "button text should be gold")
    assert(button.Label.scale == 1.5, "button text should be scaled up")
    assert(button.anchor[1] == "BOTTOMLEFT" and button.anchor[3] == "TOPRIGHT", "menu should open upwards")

    local count = #kacklaRaidIcons + #kacklaEmoticonList
    assert(#entries == count, "expected " .. count .. " entries, got " .. #entries)
    assert(grid[1] == 2 and grid[2] == math.ceil(count / 8), "unexpected grid " .. tostring(grid[2]))

    -- every entry uses the chat font and keeps the menu open when picked
    for i, entry in ipairs(entries) do
        local fontObject
        entry.initializer({fontString = {SetFontObject = function(_, font) fontObject = font end}})
        assert(fontObject == ChatFontNormal, "entry " .. i .. " should use ChatFontNormal")
        assert(entry.callback() == MenuResponse.Open, "entry " .. i .. " should keep the menu open")
    end

    -- raid icons first, inserting their {rtN} tag
    for index, tags in ipairs(kacklaRaidIcons) do
        local entry = entries[index]
        assert(entry.label == kacklaRaidIconTexture(index), "raid icon " .. index .. " label")
        entry.callback()
        assert(inserted == tags[1], "raid icon " .. index .. " inserted '" .. tostring(inserted) .. "'")
        entry.tooltip({})
        assert(tooltipLines[1] == table.concat(tags, " "), "raid icon " .. index .. " tooltip")
    end

    -- then the emoticons in list order, inserting their :name: shortcut
    for i, emoticon in ipairs(kacklaEmoticonList) do
        local entry = entries[#kacklaRaidIcons + i]
        assert(entry.label == emoticon[2], emoticon[1] .. " label '" .. entry.label .. "'")
        entry.callback()
        assert(inserted == ":" .. emoticon[1] .. ":", emoticon[1] .. " inserted '" .. tostring(inserted) .. "'")
        entry.tooltip({})
        assert(tooltipLines[1] == ":" .. emoticon[1] .. ":", emoticon[1] .. " tooltip")
    end

    print("Verify emoticon picker done")
end

function checkHelp()
    print("Verify help start")
    local maxLength = 50
    local commands = sut.slashCommands
    for name, command in pairs(commands) do
        assert(type(command.help) == "table", name .. ": help should be a table of lines")
        assert(#command.help >= 2, name .. ": help needs a usage and a description line")
        for i = 2, #command.help do
            local line = command.help[i]
            assert(#line <= maxLength, name .. ": help line " .. i .. " is " .. #line
                   .. " characters, max is " .. maxLength .. ": '" .. line .. "'")
        end

        -- single command help is the usage followed by indented descriptions
        local text = commands.help.make(commands, name)
        local lines = {}
        for line in string.gmatch(text, "[^\n]+") do table.insert(lines, line) end
        assert(lines[1] == string.format(command.help[1], "/kackla", name),
               name .. ": unexpected usage line '" .. lines[1] .. "'")
        for i = 2, #lines do
            assert(lines[i] == "    " .. command.help[i],
                   name .. ": unexpected description line '" .. lines[i] .. "'")
        end
    end

    -- the full help keeps every description line within 4 + maxLength
    for line in string.gmatch(commands.help.make(commands), "[^\n]+") do
        if line:sub(1, 4) == "    " then
            assert(#line <= 4 + maxLength, "help line too long: '" .. line .. "'")
        end
    end
    print("Verify help done")
end

function checkSlashCommands()
    print("Verify commands start")

    -- Global tests
    KacklaDb = {alias = nil, format = nil, channels = nil}
    local alias = "tester"
    sut:slashCommandHandler("setAlias tester")
    assert(KacklaDb.alias == alias, "Failed to set alias to '" .. alias
           .. "' got '" .. KacklaDb.alias .. "'")

    KacklaDb = {alias = nil, format = nil, channels = nil}
    local format = "[ %s ]%s "
    sut:slashCommandHandler("setFormat " .. format)
    assert(KacklaDb.format == format, "Failed to set format to '" .. format
           .. "' got '" .. KacklaDb.format .. "'")

    -- Player tests
    KacklaPerCharacterDb = {alias = nil, format = nil, channels = nil}
    local alias = ""
    sut:slashCommandHandler("setPlayerAlias")
    assert(KacklaPerCharacterDb.alias == alias, "Failed to set player alias to '" .. alias
           .. "' got '" .. KacklaPerCharacterDb.alias .. "'")
    assert(type(KacklaPerCharacterDb.alias) == "string", "expected string not " ..
           type(KacklaPerCharacterDb.alias))

    KacklaPerCharacterDb = {alias = nil, format = nil}
    local format = "%s%s"
    sut:slashCommandHandler("setPlayerFormat " .. format)
    assert(KacklaPerCharacterDb.format == format, "Failed to set player format to '" .. format
           .. "' got '" .. KacklaPerCharacterDb.format .. "'")

    print("Verify commands done")
end

checkHelp()
checkSlashCommands()
checkChannelCommands()
checkIsChannelActive()
checkSendChatMessageHook()
checkEmoticons()
checkEmoticonPicker()
