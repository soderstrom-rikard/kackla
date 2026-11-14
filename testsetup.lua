-- Shared setup for the *.test.lua files, loaded with require("testsetup").
-- Mocks the WoW API kackla uses, loads the addon's Lua files and runs its
-- OnLoad and ADDON_LOADED, then provides helpers for the tests. sut is the
-- addon (kacklaFrameMixin), also available as kacklaFrame like in game.

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

-- Mock of the WoW Mixin, RegisterEvent records the event in registeredEvents
function Mixin(table)
    table.name = "kacklaTest"
    table.RegisterEvent = function(eventname)
        registeredEvents[eventname] = true
    end
    return table
end

-- Mock of the WoW UnitName, returns the name and realm of the unit
function UnitName(unit)
    local units = {
        player = {name = "tester", realm = "bob"}
    }
    return units[unit].name, units[unit].realm
end

require("emoticons")
require("kackla")
require("emoticonpicker")
require("settings")

sut = kacklaFrameMixin
-- the settings window calls the addon through its frame
kacklaFrame = sut
sut:OnLoad()
sut:ADDON_LOADED("kackla")

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

-- Returns the set ({KEY = true}) as a sorted "{A,B}" string, or "nil"
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
