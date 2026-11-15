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

-- Tests the color picker in the settings window against mocked widgets
function checkColorPicker()
    print("Verify color picker start")
    local frame = {
        GetName = function() return "KacklaSettingsFrame" end,
        TitleText = {SetText = function() end},
        RegisterForDrag = function() end,
        ColorPicker = {
            SetScript = function(self, name, handler) self.handler = handler end,
            SetColorRGB = function(self, r, g, b) self.rgb = {r, g, b} end,
        },
        ColorSwatch = {SetColorTexture = function(self, r, g, b) self.rgb = {r, g, b} end},
        ColorToken = {SetText = function(self, text) self.text = text end},
        ColorHex = {
            focus = false,
            HasFocus = function(self) return self.focus end,
            SetText = function(self, text) self.text = text end,
        },
    }
    for k, v in pairs(KacklaSettingsMixin) do
        frame[k] = v
    end
    UISpecialFrames = {}
    frame:OnLoad()

    -- starts with orange everywhere
    assert(frame.color == 0xFF8000, "start color")
    assert(frame.ColorToken.text == ":#ff8000:", "token '" .. tostring(frame.ColorToken.text) .. "'")
    assert(frame.ColorHex.text == "ff8000", "hex box")
    assert(frame.ColorPicker.rgb[1] == 1 and frame.ColorPicker.rgb[3] == 0, "wheel set")
    assert(frame.ColorSwatch.rgb[1] == 1, "swatch set")

    -- picking on the wheel updates the rest, but not the hex box being typed in
    frame.ColorPicker.handler(frame.ColorPicker, 0, 0.5, 1)
    assert(frame.color == 0x0080FF and frame.ColorToken.text == ":#0080ff:", "wheel pick")
    assert(frame.ColorHex.text == "0080ff", "hex box follows the wheel")
    frame.ColorHex.focus = true
    frame.ColorPicker.handler(frame.ColorPicker, 1, 1, 1)
    assert(frame.ColorHex.text == "0080ff", "hex box being typed in isn't overwritten")
    frame.ColorHex.focus = false

    -- typed colors: hex, short hex, tokens and names
    for input, expected in pairs({
        ["ff8000"] = 0xFF8000,
        ["#f80"] = 0xFF8800,
        [":#00ff00:"] = 0x00FF00,
        ["  red "] = kacklaColors.NAMED.red,
    }) do
        frame:ApplyColorText(input)
        if expected then
            assert(frame.color == expected, "typed '" .. input .. "' gave " .. string.format("%06x", frame.color))
        end
    end
    -- anything else keeps the current color, and shows it again
    frame:SetColor(0x123456)
    for _, input in ipairs({"", "nope", "12345", "ff 80 00", ":#:"}) do
        frame.ColorHex.text = input
        frame:ApplyColorText(input)
        assert(frame.color == 0x123456 and frame.ColorHex.text == "123456", "'" .. input .. "' is ignored")
    end

    -- inserting the token into chat
    local inserted
    local originalInsert = kacklaInsertIntoChat
    kacklaInsertIntoChat = function(text) inserted = text end
    frame:InsertColor()
    assert(inserted == ":#123456:", "inserted '" .. tostring(inserted) .. "'")
    kacklaInsertIntoChat = originalInsert
    print("Verify color picker done")
end

checkSettings()
checkColorPicker()
