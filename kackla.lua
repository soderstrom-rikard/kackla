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

-- How channels are stored in KacklaDb.channels and KacklaPerCharacterDb.channels:
--   nil                       not set. Globally the alias is used in all
--                             channels, per character the global channels
--                             are used
--   {}                        the alias is used in all channels. Lets a
--                             character use all channels even when the
--                             global channels are restricted
--   {GUILD = true, ...}       the alias is only used in these channels
-- The empty set meaning "all" is only how it is stored, users type ALL.

-- Parses a comma separated list of channels into a set, e.g.
-- "guild, Say,MyChannel" -> {GUILD = true, SAY = true, MYCHANNEL = true}
-- Names are upper cased since both chat types and channel names are
-- case-insensitive. An empty list returns nil (not set) and the keyword ALL
-- returns {} (all channels). ALL wins over any other listed channel, so a
-- custom channel actually named "All" can't be selected.
local function ParseChannels(csv)
    local channels = nil
    for item in string.gmatch(csv or "", "[^,]+") do
        local name = string.upper(item:match("^%s*(.-)%s*$"))
        if name == "ALL" then
            return {}
        end
        if name ~= "" then
            channels = channels or {}
            channels[name] = true
        end
    end
    return channels
end

-- Inverse of ParseChannels, sorted so the output is stable. Returns nil when
-- not set, so the caller can say what that means in its context.
local function ChannelsToCsv(channels)
    if channels == nil then
        return nil
    end
    if next(channels) == nil then
        return "ALL"
    end
    local names = {}
    for name in pairs(channels) do
        table.insert(names, name)
    end
    table.sort(names)
    return table.concat(names, ",")
end

-- Stores the parsed channels via the setter and warns about names that are
-- neither a chat type nor a channel the player is currently in. They are
-- still stored, since the player may join the channel later.
function kacklaFrameMixin:SetChannels(csv, store)
    local channels = ParseChannels(csv)
    for name in pairs(channels or {}) do
        if not self.chatTypeLookup[name] and GetChannelName(name) == 0 then
            print("kackla: '" .. name .. "' is not a chat type or a joined channel")
        end
    end
    store(channels)
end

-- The per character channels override the global ones
function kacklaFrameMixin:GetChannels()
    if KacklaPerCharacterDb.channels ~= nil then
        return KacklaPerCharacterDb.channels
    end
    return KacklaDb.channels
end

-- nil or {} channels means the alias is used in all channels, see above.
-- Custom channels are sent as chatType "CHANNEL" with target being the
-- channel number, so they are matched on the channel name. Zone channels such
-- as "General - Stormwind City" also match on the part before " - ".
-- Listing "CHANNEL" itself makes the alias used in all custom channels.
function kacklaFrameMixin:IsChannelActive(chatType, target)
    local channels = self:GetChannels()
    if channels == nil or next(channels) == nil then
        return true
    end

    chatType = string.upper(chatType or "SAY")
    if channels[chatType] then
        return true
    end

    if chatType == "CHANNEL" and target then
        local _, name = GetChannelName(target)
        if name then
            name = string.upper(name)
            local baseName = name:match("^(.-) %- ") or name
            return channels[name] == true or channels[baseName] == true
        end
    end

    return false
end

function kacklaFrameMixin:SendChatMessage(msg, channel, language, target)
    if not self.hooks["SendChatMessage"] then
        error("We shouldn't be able to reach our own hook without having it registered")
        return
    end

    -- the alias and emoticons are only used in the active channels
    if not self:IsChannelActive(channel, target) then
        return self.hooks["SendChatMessage"](msg, channel, language, target)
    end

    -- self.hooks["SendChatMessage"]("<Sodrik> " .. msg, channel, language, target)
    local alias, format = self:GetAliasAndFormat()
    -- replaced after formatting, so shortcuts in the alias and format work too
    local aliasFormattedMessage = kacklaReplaceEmoticons(string.format(format, alias, msg))

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

-- Prints each line as its own chat message. A single message taller than the
-- chat window only shows its bottom part and can't be scrolled.
local function PrintLines(text)
    for line in string.gmatch(text, "[^\n]+") do
        print(line)
    end
end

-- All emoticon shortcuts sorted by name, a few per line
function kacklaFrameMixin:EmoticonList()
    local names = {}
    for name in pairs(kacklaEmoticons) do
        table.insert(names, name)
    end
    table.sort(names)

    local lines, line = {}, ""
    for _, name in ipairs(names) do
        local entry = ":" .. name .. ": " .. kacklaEmoticons[name]
        if line ~= "" and #line + #entry > 50 then
            table.insert(lines, line)
            line = ""
        end
        line = line == "" and ("  " .. entry) or (line .. "  " .. entry)
    end
    table.insert(lines, line)

    -- raid icons with a local preview, |T textures only show locally
    table.insert(lines, "kackla raid icons, built into the game:")
    for index, tags in ipairs(kacklaRaidIcons) do
        table.insert(lines, "  " .. table.concat(tags, " ") .. " " .. kacklaRaidIconTexture(index))
    end

    return "kackla emoticons:\n" .. table.concat(lines, "\n")
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
    -- channels = nil means all channels, so existing saved variables
    -- without channels keep working as before
    KacklaDb = KacklaDb or {alias = playerFullName, format = "[%s] %s", channels = nil}
    KacklaPerCharacterDb = KacklaPerCharacterDb or {
        alias = nil,
        format = nil,
        channels = nil
    }

    print( "kackla alias: " .. tostring(KacklaDb.alias))
    print( "kackla format: " .. tostring(KacklaDb.format))
    print( "kackla channels: " .. (ChannelsToCsv(KacklaDb.channels) or "ALL"))

    print( "kackla player alias: " .. tostring(KacklaPerCharacterDb.alias))
    print( "kackla player format: " .. tostring(KacklaPerCharacterDb.format))
    print( "kackla player channels: " .. (ChannelsToCsv(KacklaPerCharacterDb.channels) or "global"))

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
    self.chatTypeLookup = {}
    for _, chatType in ipairs(self.chatTypes) do
        self.chatTypeLookup[chatType] = true
    end
    self.slashCommands = {
        ["setAlias"] = {
            exec = function(lookup, alias)
                KacklaDb.alias = alias
            end,
            help = {
                "%s %s ALIAS",
                "Sets the global alias",
            }
        },
        ["setFormat"] = {
            exec = function(lookup, format)
                KacklaDb.format = format
            end,
            help = {
                "%s %s FORMAT",
                "Sets the global format",
            }
        },
        ["setChannels"] = {
            exec = function(lookup, csv)
                self:SetChannels(csv, function(channels) KacklaDb.channels = channels end)
            end,
            help = {
                "%s %s [CHANNELS]",
                "Sets the comma-separated global channels",
                "where the alias is used, e.g. GUILD,SAY,MyChannel",
                "Without CHANNELS, or with ALL, the alias is used",
                "in all channels",
            }
        },
        ["getAlias"] = {
            exec = function(lookup)
                print(KacklaDb.alias)
            end,
            help = {
                "%s %s",
                "Gets the global alias",
            }
        },
        ["getFormat"] = {
            exec = function(lookup)
                print(KacklaDb.format)
            end,
            help = {
                "%s %s",
                "Gets the global format",
            }
        },
        ["getChannels"] = {
            exec = function(lookup)
                print(ChannelsToCsv(KacklaDb.channels) or "ALL")
            end,
            help = {
                "%s %s",
                "Gets the global channels",
            }
        },
        ["setPlayerAlias"] = {
            exec = function(lookup, alias)
                KacklaPerCharacterDb.alias = alias
            end,
            help = {
                "%s %s ALIAS",
                "Sets the player alias",
            }
        },
        ["setPlayerFormat"] = {
            exec = function(lookup, format)
                KacklaPerCharacterDb.format = format
            end,
            help = {
                "%s %s FORMAT",
                "Sets the player format",
            }
        },
        ["setPlayerChannels"] = {
            exec = function(lookup, csv)
                self:SetChannels(csv, function(channels) KacklaPerCharacterDb.channels = channels end)
            end,
            help = {
                "%s %s [CHANNELS]",
                "Sets the comma-separated player channels where",
                "the alias is used, overriding the global channels",
                "ALL uses the alias in all channels, even when the",
                "global channels are restricted",
                "Without CHANNELS the global channels are used",
            }
        },
        ["getPlayerAlias"] = {
            exec = function(lookup)
                print(KacklaPerCharacterDb.alias)
            end,
            help = {
                "%s %s",
                "Gets the player alias",
            }
        },
        ["getPlayerFormat"] = {
            exec = function(lookup)
                print(KacklaPerCharacterDb.format)
            end,
            help = {
                "%s %s",
                "Gets the player format",
            }
        },
        ["getPlayerChannels"] = {
            exec = function(lookup)
                print(ChannelsToCsv(KacklaPerCharacterDb.channels) or "global")
            end,
            help = {
                "%s %s",
                "Gets the player channels",
            }
        },
        ["emoticons"] = {
            exec = function(lookup)
                PrintLines(self:EmoticonList())
            end,
            help = {
                "%s %s",
                "Lists the :name: shortcuts that are replaced",
                "with their symbol in channels where the alias",
                "is used",
            }
        },
        ["help"] = {
            -- Each help is a table of lines: the first is the usage, formatted
            -- with the prefix and command name, the rest describe the command
            -- and are indented here. Keep description lines at most 50
            -- characters, kackla.test.lua checks this.
            format = function(help, prefix, key)
                return string.format(help[1], prefix, key)
                       .. "\n    " .. table.concat(help, "\n    ", 2)
            end,
            make = function(lookup, key)
                local format = lookup.help.format
                if lookup[key] then
                    return format(lookup[key].help, "/kackla", key)
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
                    s = s .. "\n" .. format(lookup[v].help, " ", v)
                end

                return s
            end,
            exec = function(lookup, key)
                PrintLines(lookup.help.make(lookup,key))
            end,
            help = {
                "%s %s [COMMAND]",
                "Print help, if command is supplied shows help for",
                "that command",
            }
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
