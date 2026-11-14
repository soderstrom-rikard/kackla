-- Tests the settings window, run with make test
require("testsetup")

-- Tests the settings window logic: shown texts, storing edits through the
-- set commands, overrides, the preview and opening it with a bare /kackla
function checkSettings()
    print("Verify settings start")
    local settings = KacklaSettingsMixin

    KacklaDb = {alias = "Global", format = "[%s] %s", channels = nil}
    KacklaPerCharacterDb = {}
    assert(settings:GetSettingText("global", "alias") == "Global", "global alias text")
    assert(settings:GetSettingText("global", "channels") == "ALL", "unset global channels are ALL")
    -- not overridden, the player column shows the global values
    for _, key in ipairs({"alias", "format", "channels"}) do
        assert(not settings:IsOverridden(key), key .. " should not be overridden")
        assert(settings:GetSettingText("player", key) == settings:GetSettingText("global", key),
               "player " .. key .. " should show the global value")
    end

    -- unchanged text is not stored, so nil stays nil
    KacklaDb.alias = nil
    assert(settings:SaveSetting("global", "alias", ""), "unchanged alias should be ok")
    assert(KacklaDb.alias == nil, "unchanged alias should stay nil")

    -- edits are stored like the set commands do
    settings:SaveSetting("global", "alias", "New")
    assert(KacklaDb.alias == "New", "global alias not stored")
    capturePrint(function() settings:SaveSetting("global", "channels", "guild, say") end)
    assert(compareSets(KacklaDb.channels, {GUILD = true, SAY = true}), "global channels not stored")
    assert(settings:GetSettingText("global", "channels") == "GUILD,SAY", "global channels text")
    settings:SaveSetting("global", "channels", "")
    assert(KacklaDb.channels == nil, "empty global channels should be nil")

    -- formats that would drop the message are refused
    for _, format in ipairs({"", "%s", "%d %s", "%s %s %s"}) do
        local printed = capturePrint(function()
            assert(settings:SaveSetting("global", "format", format) == false,
                   "format '" .. format .. "' should be refused")
        end)
        assert(printed[1] and printed[1]:find("not stored", 1, true), "refused format should print why")
        assert(KacklaDb.format == "[%s] %s", "refused format '" .. format .. "' was stored")
    end
    settings:SaveSetting("global", "format", "<%s> %s")
    assert(KacklaDb.format == "<%s> %s", "valid format not stored")

    -- overriding starts from the global value, unticking removes it
    KacklaDb = {alias = "Global", format = nil, channels = {GUILD = true}}
    settings:SetOverride("alias", true)
    settings:SetOverride("format", true)
    settings:SetOverride("channels", true)
    assert(KacklaPerCharacterDb.alias == "Global", "override should copy the global alias")
    assert(KacklaPerCharacterDb.format == "%s%s", "override should start with the default format")
    assert(compareSets(KacklaPerCharacterDb.channels, {GUILD = true}), "override should copy the channels")
    assert(KacklaPerCharacterDb.channels ~= KacklaDb.channels, "override channels should be a copy")
    settings:SaveSetting("player", "channels", "ALL")
    assert(compareSets(KacklaPerCharacterDb.channels, {}), "player ALL should be stored as {}")
    assert(compareSets(KacklaDb.channels, {GUILD = true}), "global channels changed by player edit")
    settings:SaveSetting("player", "alias", "")
    assert(KacklaPerCharacterDb.alias == "", "player alias can be set to no alias")
    assert(settings:IsOverridden("alias"), "no alias is still an override")
    -- an empty player channel list means use the global channels again
    settings:SaveSetting("player", "channels", "")
    assert(not settings:IsOverridden("channels"), "empty player channels should stop the override")
    settings:SetOverride("alias", false)
    assert(KacklaPerCharacterDb.alias == nil, "unticking should remove the player alias")
    KacklaDb.channels = nil
    settings:SetOverride("channels", true)
    assert(compareSets(KacklaPerCharacterDb.channels, {}), "override of unset global channels is ALL")

    -- the preview is the message as sent from this character
    KacklaDb = {alias = "Bob", format = "[%s] %s", channels = {SAY = true}}
    KacklaPerCharacterDb = {}
    assert(settings:GetPreview() == "[Bob] Hello ☺", "preview got '" .. settings:GetPreview() .. "'")
    assert(settings:GetChannelsText() == "SAY", "channels text got '" .. settings:GetChannelsText() .. "'")
    KacklaPerCharacterDb = {format = "%d", channels = {}}
    assert(settings:GetPreview() == "invalid format", "preview of a broken format")
    assert(settings:GetChannelsText() == "ALL", "player ALL channels text")

    -- a bare /kackla toggles the window, commands refresh it when it is shown
    local refreshes = 0
    KacklaSettingsFrame = {
        shown = false,
        IsShown = function(self) return self.shown end,
        SetShown = function(self, shown) self.shown = shown end,
        Refresh = function(self) refreshes = refreshes + 1 end,
    }
    sut:slashCommandHandler("")
    assert(KacklaSettingsFrame.shown, "bare /kackla should show the settings")
    sut:slashCommandHandler("setAlias Someone")
    assert(refreshes == 1, "commands should refresh the shown settings")
    sut:slashCommandHandler("")
    assert(not KacklaSettingsFrame.shown, "bare /kackla should hide the shown settings")
    sut:slashCommandHandler("setAlias Someone")
    assert(refreshes == 1, "commands should not refresh hidden settings")
    KacklaSettingsFrame = nil

    print("Verify settings done")
end

checkSettings()
