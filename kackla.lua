-- The full format is
-- |Tpath:height[:width[:offsetX:offsetY:[textureWidth:textureHeight:leftTexel:rightTexel:topTexel:bottomTexel[:rVertexColor:gVertexColor:bVertexColor]]]]|t
-- as described in  https://wowpedia.fandom.com/wiki/UI_escape_sequences
-- we will however limit ourselves to only "|Tpath:height:width|t"
-- This is the same as executing
local function TextureString(t)
    return "|T"..t.path..":"..t.height..":"..t.width.."|t"
end

-- Create a local frame as a mix between the defined frame in kackla.xml and this local object
kacklaFrameMixin = Mixin({})

--
-- https://wowpedia.fandom.com/wiki/Creating_a_slash_command
function kacklaFrameMixin:registerSlashCommand(command, func)
    local name = "KACKLA_"..command:upper()

    SlashCmdList[name] = func
    _G["SLASH_"..name.."1"] = "/"..command:lower()
end

-- Identity2 = LibStub("AceAddon-3.0").NewAddon("Identity2",
--                                              "AceConsole-3.0",
--                                              "AceHook-3.0",
--                                              "AceEvent-3.0")
-- Identity2:RawHook("SendChatMessage", true) -- method="SendChatMessage", handler=nil, hookSecure=true, object=nil
-- -> AceHook.hook(self, nil, "SendChatMessage", nil, false, false, true, true,  "Usage: RawHook([object], method, [handler], [hookSecure])")
-- ---> _G[method] = uid
function kacklaFrameMixin:registerHookCommand(command, hook, parent)
    if not parent[command] then
        print("Cannot register hook - command "
              .. command ..
              " does not exist in global table")
        return nil
    end

    if type(hook) ~= "function" then
        print("Cannot register hook - hook '"
              .. hook ..
              "'is not a function")
        return nil
    end

    if self.hooks[command] then
        print("Cannot register hook - already registered")
        return nil
    end

    if not parent then
        parent = _G
    end

    self.hooks[command] = parent[command]
    parent[command] = hook
end

--
--
function kacklaFrameMixin:GetAliasAndFormat()
    local alias = KacklaPerCharacterDb.alias
            or KacklaDb.alias
            or ""
    local format = KacklaPerCharacterDb.format
             or KacklaDb.format
             or "%s%s"

    return alias, format
end

function kacklaFrameMixin:SendChatMessage(msg, channel, language, target)
    if not self.hooks["SendChatMessage"] then
        error("We shouldn't be able to reach our own hook without having it registered")
        return
    end

    -- self.hooks["SendChatMessage"]("<Sodrik> " .. msg, channel, language, target)
    local alias, format = self:GetAliasAndFormat()
    local aliasFormattedMessage = string.format(format, alias, msg)

    self.hooks["SendChatMessage"](aliasFormattedMessage, channel, language, target)
end

--
--
function kacklaFrameMixin:MakeAtlasMarkup(name, sx, sy)
    local i = C_Texture.GetAtlasInfo(name)
    if not i then
        print("Atlas not found:", name)
        return
    end

    local w = i.width / (i.rightTexCoord - i.leftTexCoord) + 0.5
    local h = i.height / (i.bottomTexCoord - i.topTexCoord) + 0.5

    local left   = math.floor(i.leftTexCoord   * w + 0.5)
    local right  = math.floor(i.rightTexCoord  * w + 0.5)
    local top    = math.floor(i.topTexCoord    * h + 0.5)
    local bottom = math.floor(i.bottomTexCoord * h + 0.5)

    local markup = string.format(
        "\124T%s:32:32:0:0:%d:%d:%d:%d:%d:%d\124t",
        tostring(i.file), math.floor(sx*w), math.floor(sy*h), left, right, top, bottom
    )

    return markup
end

--
--
function kacklaFrameMixin:slashCommandHandler(msg, editBox)
    local _, _, command, arg = string.find(msg, "(%S+)%s*(.*)")

    local commands = self.slashCommands
    if commands[command] then
        return commands[command].exec(commands,arg)
    elseif command == "test" then
        markup = self:MakeAtlasMarkup("MainPet-LevelBubble", 1.0, 1.0)

        if not arg then
            DEFAULT_CHAT_FRAME:AddMessage(markup)
        else
            self:SendChatMessage(markup, arg)
        end
        return
    elseif command then
        print("unknown command '" .. command .. "' received")
        commands.help.exec(commands)
        return
    else
        commands.help.exec(commands)
        return
    end
end

-- ADDON is fully loaded, so we now have access to things like
-- SavedVariables: KacklaDb
-- SavedVariablesPerCharacter: KacklaPerCharacterDb
-- https://wowwiki-archive.fandom.com/wiki/Saving_variables_between_game_sessions
function kacklaFrameMixin:ADDON_LOADED(addonName)
    if addonName ~= "kackla" then
        return
    end

    print("kackla loading..")
    local playerFirstName, playerLastName = UnitName("player")
    local playerFullName = playerFirstName .. " " .. playerLastName
    KacklaDb = KacklaDb or {alias = playerFullName, format = "[%s] %s"}
    KacklaPerCharacterDb = KacklaPerCharacterDb or {
        alias = nil,
        format = nil
    }

    if KacklaDb.alias and KacklaDb.format then
        print( "kackla alias: " .. KacklaDb.alias)
        print( "kackla format: " .. KacklaDb.format)
    end

    if KacklaPerCharacterDb.alias and KacklaPerCharacterDb.format then
        print( "kackla Character specific alias: " .. KacklaPerCharacterDb.alias)
        print( "kackla Character specific format: " .. KacklaPerCharacterDb.format)
    end

    print("kackla loaded")
end

--
-- Initializes player specific variables
function kacklaFrameMixin:PLAYER_LOGIN()
    return
end

-- The purpose of this event is to ensure that all SavedVariables are updated
-- before the player leaves the game, but we currently don't shadow any SavedVariables
function kacklaFrameMixin:PLAYER_LOGOUT()
    return
end

function kacklaFrameMixin:OnEvent(event, ...)
    self[event](self, ...)
end

-- Initializes kackla addon module when frame loads
--
function kacklaFrameMixin:OnLoad()
    local playerFirstName, playerLastName = UnitName("player")
    local playerFullName = playerFirstName .. " " .. playerLastName
    print("kackla OnLoad: welcomes '" .. playerFullName .. "'")


    self.hooks = {}
    self.chatTypes = {
      "SAY",
      "EMOTE",
      "YELL",
      "PARTY",
      "RAID",
      "RAID_WARNING",
      "INSTANCE_CHAT",
      "GUILD",
      "OFFICER",
      "WHISPER",
      "CHANNEL",
      "AFK",
      "DND",
      "VOICE_TEXT"
    }
    self.slashCommands = {
        ["setAlias"] = {
            exec = function(lookup, alias)
                KacklaDb.alias = alias
            end,
            help = "%s %s ALIAS\10    Sets the global alias"
        },
        ["setFormat"] = {
            exec = function(lookup, format)
                KacklaDb.format = format
            end,
            help = "%s %s FORMAT\10    Sets the global format"
        },
        ["getAlias"] = {
            exec = function(lookup)
                print(KacklaDb.alias)
            end,
            help = "%s %s\10    Gets the global alias"
        },
        ["getFormat"] = {
            exec = function(lookup)
                print(KacklaDb.format)
            end,
            help = "%s %s\10    Gets the global alias"
        },
        ["setPlayerAlias"] = {
            exec = function(lookup, alias)
                KacklaPerCharacterDb.alias = alias
            end,
            help = "%s %s ALIAS\10    Sets the player alias"
        },
        ["setPlayerFormat"] = {
            exec = function(lookup, format)
                KacklaPerCharacterDb.format = format
            end,
            help = "%s %s FORMAT\10    Sets the player format"
        },
        ["getPlayerAlias"] = {
            exec = function(lookup)
                print(KacklaPerCharacterDb.alias)
            end,
            help = "%s %s\10    Gets the player alias"
        },
        ["getPlayerFormat"] = {
            exec = function(lookup)
                print(KacklaPerCharacterDb.format)
            end,
            help = "%s %s\10    Gets the player alias"
        },
        ["help"] = {
            make = function(lookup, key)
                if lookup[key] then
                    return string.format(lookup[key].help, "/kackla", key)
                end

                local s = "/kackla [COMMAND] ([ARGS])"

                local table_keys = {}
                local index = 0
                for k,_ in pairs(lookup) do
                    index = index + 1
                    table_keys[index] = k
                end
                table.sort(table_keys, function(left, right)
                    return left < right
                end)

                s = s .. "\nCOMMANDS"
                for k,v in ipairs(table_keys) do
                    s = s .. "\n" .. string.format(lookup[v].help, " ", v)
                end

                return s
            end,
            exec = function(lookup, key)
                print(lookup.help.make(lookup,key))
            end,
            help = "%s %s [COMMAND]\n    Print help, if command is supplied shows help for that command"
        }
    }

    self:registerSlashCommand("kackla", function(msg, editBox)
        self:slashCommandHandler(msg, editBox)
    end)
    self:registerHookCommand("SendChatMessage", function(msg, channel, language, target)
            self:SendChatMessage(msg, channel, language, target)
        end,
        C_ChatInfo)
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_LOGOUT")
end

-- Example printing textures directly in WoW console
-- /kackla test
