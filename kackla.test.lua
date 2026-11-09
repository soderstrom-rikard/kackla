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

inCommandsSection = false
fileObject = io.open( scriptDir .. "README.md.out", "w")
for line in io.lines(scriptDir .. "README.md") do
    if line == "## Bumping version" then
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
