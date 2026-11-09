_G = {}
C_ChatInfo = {
    SendChatMessage = function(msg, channel, language, target)
        error("we are running the non-hooked SendChatInfo")
    end
}
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
require("kackla")

sut = kacklaFrameMixin
sut:OnLoad()
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


function checkSlashCommands()
    print("Verify commands start")

    -- Global tests
    KacklaDb = {alias = nil, format = nil}
    local alias = "tester"
    sut:slashCommandHandler("setAlias tester")
    assert(KacklaDb.alias == alias, "Failed to set alias to '" .. alias
           .. "' got '" .. KacklaDb.alias .. "'")

    KacklaDb = {alias = nil, format = nil}
    local format = "[ %s ]%s "
    sut:slashCommandHandler("setFormat " .. format)
    assert(KacklaDb.format == format, "Failed to set format to '" .. format
           .. "' got '" .. KacklaDb.format .. "'")

    -- Player tests
    KacklaPerCharacterDb = {alias = nil, format = nil}
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

checkSlashCommands()
