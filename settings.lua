-- The settings window (KacklaSettingsFrame in kackla.xml), a GUI for the
-- alias, format and channels set/get slash commands. Opened with a bare
-- /kackla or by right-clicking the emoticon button.
--
-- Each setting is a row with an edit box for the global value and one for
-- this character. The character's edit box is only enabled when its
-- override box is ticked, otherwise it shows the global value. Edits are
-- stored when pressing enter or leaving the edit box, escape reverts them.

-- Row order
local SETTINGS = {"alias", "format", "channels"}

-- The slash command that stores each setting, so the window stores values
-- exactly like the commands do
local SET_COMMANDS = {
    global = {alias = "setAlias", format = "setFormat", channels = "setChannels"},
    player = {alias = "setPlayerAlias", format = "setPlayerFormat", channels = "setPlayerChannels"},
}

-- The message shown in the preview
local PREVIEW_MESSAGE = "Hello :smile:"

-- The color picker's first color, 0xRRGGBB
local START_COLOR = 0xFF8000

-- Shows or hides the settings window
function kacklaToggleSettings()
    KacklaSettingsFrame:SetShown(not KacklaSettingsFrame:IsShown())
end

-- Returns the text shown for a stored value
local function ValueToText(key, value)
    if key == "channels" then
        return kacklaChannelsToCsv(value) or "ALL"
    end
    return value or ""
end

-- Returns a copy of a channel set, so the character's set can be edited
-- without changing the global one
local function CopySet(set)
    local copy = {}
    for k, v in pairs(set) do
        copy[k] = v
    end
    return copy
end

-- Returns an error message when format can't format an alias and a message,
-- e.g. "%d" errors and "%s" or "" would drop the message
local function CheckFormat(format)
    local ok, result = pcall(string.format, format, "\1", "\2")
    if not ok or not string.find(result, "\2", 1, true) then
        return "the format needs a %s for the alias followed by a %s for the message"
    end
end

KacklaSettingsMixin = {}

-- Returns KacklaDb for scope "global" and KacklaPerCharacterDb for "player"
function KacklaSettingsMixin:GetDb(scope)
    if scope == "global" then
        return KacklaDb
    end
    return KacklaPerCharacterDb
end

-- True when this character overrides the global value of the setting key
function KacklaSettingsMixin:IsOverridden(key)
    return KacklaPerCharacterDb[key] ~= nil
end

-- Returns the text of setting key, the player column shows the global value
-- when the setting isn't overridden
function KacklaSettingsMixin:GetSettingText(scope, key)
    local value = self:GetDb(scope)[key]
    if scope == "player" and value == nil then
        value = KacklaDb[key]
    end
    return ValueToText(key, value)
end

-- Stores text with the set command of setting key. Unchanged text isn't
-- stored, so showing and leaving a value doesn't turn nil into "". Returns
-- false and prints why when the text can't be stored.
function KacklaSettingsMixin:SaveSetting(scope, key, text)
    if text == self:GetSettingText(scope, key) then
        return true
    end
    if key == "format" then
        local problem = CheckFormat(text)
        if problem then
            print("kackla: " .. problem .. ", '" .. text .. "' was not stored")
            return false
        end
    end
    local commands = kacklaFrame.slashCommands
    commands[SET_COMMANDS[scope][key]].exec(commands, text)
    return true
end

-- Starts or stops overriding setting key for this character. A new override
-- starts as a copy of the effective global value, all channels when the
-- global channels aren't set.
function KacklaSettingsMixin:SetOverride(key, enabled)
    if not enabled then
        KacklaPerCharacterDb[key] = nil
    elseif KacklaPerCharacterDb[key] == nil then
        if key == "channels" then
            KacklaPerCharacterDb.channels = CopySet(KacklaDb.channels or {})
        elseif key == "format" then
            KacklaPerCharacterDb.format = KacklaDb.format or "%s%s"
        else
            KacklaPerCharacterDb.alias = KacklaDb.alias or ""
        end
    end
end

-- Returns PREVIEW_MESSAGE as it would be sent from this character
function KacklaSettingsMixin:GetPreview()
    local alias, format = kacklaFrame:GetAliasAndFormat()
    local ok, message = pcall(string.format, format, alias, PREVIEW_MESSAGE)
    if not ok then
        return "invalid format"
    end
    return kacklaReplaceEmoticons(message)
end

-- Returns the channels the alias is used in for this character
function KacklaSettingsMixin:GetChannelsText()
    return kacklaChannelsToCsv(kacklaFrame:GetChannels()) or "ALL"
end

-- Closes with escape, can be dragged by its title bar, and starts the color
-- picker with START_COLOR
function KacklaSettingsMixin:OnLoad()
    table.insert(UISpecialFrames, self:GetName())
    self.TitleText:SetText("kackla settings")
    self:RegisterForDrag("LeftButton")
    self.ColorPicker:SetScript("OnColorSelect", function(_, r, g, b)
        self:OnColorSelect(r, g, b)
    end)
    self:SetColor(START_COLOR)
end

-- Shows the color picked on the wheel: swatch, hex and token
function KacklaSettingsMixin:OnColorSelect(r, g, b)
    self.color = kacklaColors.join(r, g, b)
    self.ColorSwatch:SetColorTexture(r, g, b)
    self.ColorToken:SetText(kacklaColors.hexToken(self.color))
    if not self.ColorHex:HasFocus() then
        self.ColorHex:SetText(string.format("%06x", self.color))
    end
end

-- Picks rgb, a 0xRRGGBB number, on the wheel and everywhere else
function KacklaSettingsMixin:SetColor(rgb)
    local r, g, b = kacklaColors.split(rgb)
    self.ColorPicker:SetColorRGB(r, g, b)
    self:OnColorSelect(r, g, b)
end

-- Picks the color typed in the hex box: a hex color or any color token name,
-- e.g. "ff8000", "#f80", ":#epic:" or "mage". Anything else shows the
-- current color again.
function KacklaSettingsMixin:ApplyColorText(text)
    local name = string.match(text, "^[%s:#]*(%w+)[%s:]*$")
    local color = name and kacklaColors.tokenColor(name)
    local rgb = color and kacklaColors.rgbOf(color)
    self:SetColor(rgb or self.color)
end

-- Inserts the picked color's token into the chat message being typed
function KacklaSettingsMixin:InsertColor()
    kacklaInsertIntoChat(kacklaColors.hexToken(self.color))
end

-- Shows the stored values each time the window opens
function KacklaSettingsMixin:OnShow()
    self:Refresh()
end

-- Moves the window while dragging it
function KacklaSettingsMixin:OnDragStart()
    self:StartMoving()
end

-- Stops moving the window, the game remembers where it was left
function KacklaSettingsMixin:OnDragStop()
    self:StopMovingOrSizing()
end

-- Shows the stored values, except in the edit box being typed in
function KacklaSettingsMixin:Refresh()
    for _, key in ipairs(SETTINGS) do
        local name = key:gsub("^%l", string.upper)
        local overridden = self:IsOverridden(key)
        local globalBox, playerBox = self["Global" .. name], self["Player" .. name]

        if not globalBox:HasFocus() then
            globalBox:SetText(self:GetSettingText("global", key))
        end
        if not playerBox:HasFocus() then
            playerBox:SetText(self:GetSettingText("player", key))
        end
        playerBox:SetEnabled(overridden)
        playerBox:SetTextColor((overridden and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
        self["Override" .. name]:SetChecked(overridden)
    end
    self.Preview:SetText(self:GetPreview())
    self.Channels:SetText(self:GetChannelsText())
end

-- Edit boxes of the settings window, the KeyValues scope ("global" or
-- "player") and setting (e.g. "alias") say which setting they edit
KacklaSettingsEditBoxMixin = {}

-- Leaving the edit box stores the edit
function KacklaSettingsEditBoxMixin:OnEnterPressed()
    self:ClearFocus()
end

-- Reverts to the stored value, ClearFocus then stores it unchanged
function KacklaSettingsEditBoxMixin:OnEscapePressed()
    self:SetText(self:GetParent():GetSettingText(self.scope, self.setting))
    self:ClearFocus()
end

-- Stores the edit, an edit that can't be stored is reverted by Refresh
function KacklaSettingsEditBoxMixin:OnEditFocusLost()
    EditBox_ClearHighlight(self)
    local settings = self:GetParent()
    settings:SaveSetting(self.scope, self.setting, self:GetText())
    settings:Refresh()
end

-- Override check boxes, the KeyValue setting says which setting they override
KacklaSettingsOverrideMixin = {}

-- Starts or stops the override and shows the result
function KacklaSettingsOverrideMixin:OnClick()
    local settings = self:GetParent()
    settings:SetOverride(self.setting, self:GetChecked())
    settings:Refresh()
end

-- Explains the check box
function KacklaSettingsOverrideMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "Override for this character")
    GameTooltip_AddNormalLine(GameTooltip, "When unticked this character uses the global setting")
    GameTooltip:Show()
end

-- Hides the tooltip from OnEnter
function KacklaSettingsOverrideMixin:OnLeave()
    GameTooltip:Hide()
end

-- The hex box of the color picker
KacklaColorHexMixin = {}

-- Leaving the hex box picks what was typed
function KacklaColorHexMixin:OnEnterPressed()
    self:ClearFocus()
end

-- Shows the picked color again, ClearFocus then picks it unchanged
function KacklaColorHexMixin:OnEscapePressed()
    self:SetText(string.format("%06x", self:GetParent().color))
    self:ClearFocus()
end

-- Picks what was typed
function KacklaColorHexMixin:OnEditFocusLost()
    EditBox_ClearHighlight(self)
    self:GetParent():ApplyColorText(self:GetText())
end
