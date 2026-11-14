-- Tests the emoticon shortcuts, run with make test
require("testsetup")

-- Tests the :name: replacement (also through the hook), the emoticon table
-- and the list printed by the emoticons command
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

checkEmoticons()
