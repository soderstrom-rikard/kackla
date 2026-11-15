-- The picker: the ☺ button below the chat menu button (bottom left of the
-- main chat window) and the window it opens, KacklaPickerFrame in
-- kackla.xml. Its tabs show grids of entries:
--   Emoticons   raid icons and the :name: emoticon shortcuts
--   Colors      the named color tokens: basic, class and item quality colors
-- Clicking an entry inserts its text at the cursor of the chat message being
-- typed, the window stays open so several can be inserted. Right-clicking ☺
-- opens the settings.

-- Inserts text at the cursor of the chat message being typed, opening the
-- chat edit box first when no message is being typed
function kacklaInsertIntoChat(text)
    local editBox = ChatFrameUtil.GetActiveWindow()
    if not editBox then
        -- nil text, so OpenChat doesn't replace what we insert
        editBox = ChatFrameUtil.OpenChat(nil)
    end
    editBox:Insert(text)
end

-- Size of an entry and the space between entries, in pixels
local ENTRY_SIZE = 26
local ENTRY_SPACING = 2
-- The emoticons grid fills columns top to bottom, with 8 rows the raid icons
-- get the first column to themselves
local EMOTICON_ROWS = 8
-- Height of a group title in the colors tab
local TITLE_HEIGHT = 16
-- Space between the window's edges and its tab content
local MARGIN_X = 12
local MARGIN_TOP = 32
local MARGIN_BOTTOM = 12

--------------------------------------------------------------------------------
-- The ☺ button

-- Mixin for KacklaEmoticonButton in kackla.xml
KacklaEmoticonButtonMixin = {}

-- Sets the ☺ label and listens to both mouse buttons
function KacklaEmoticonButtonMixin:OnLoad()
    self:SetText(kacklaEmoticons.smile)
    -- gold like the chat menu button's bubble, and larger to fill the button
    self.Label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    if self.Label.SetTextScale then
        self.Label:SetTextScale(1.5)
    end
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
end

-- Left-click toggles the picker, right-click the settings
function KacklaEmoticonButtonMixin:OnClick(mouseButton)
    if mouseButton == "RightButton" then
        kacklaToggleSettings()
    else
        KacklaPickerFrame:SetShown(not KacklaPickerFrame:IsShown())
    end
end

-- Shows what the button does
function KacklaEmoticonButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "kackla")
    GameTooltip_AddNormalLine(GameTooltip, "Click to insert an emoticon, raid icon or color into your chat message")
    GameTooltip_AddNormalLine(GameTooltip, "Right-click to open the settings")
    GameTooltip:Show()
end

-- Hides the tooltip from OnEnter
function KacklaEmoticonButtonMixin:OnLeave()
    GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- Entries

-- Mixin for the entries of the picker, KacklaPickerEntryTemplate in
-- kackla.xml. An entry shows a label or a color swatch.
KacklaPickerEntryMixin = {}

-- Sets what the entry inserts, its label (nil for a swatch) and tooltip lines
function KacklaPickerEntryMixin:Init(insertText, label, tooltipLines)
    self.insertText = insertText
    self.tooltipLines = tooltipLines
    self:SetText(label or "")
    self.Swatch:SetShown(label == nil)
    self.SwatchBorder:SetShown(label == nil)
end

-- Inserts the entry's text, the picker stays open
function KacklaPickerEntryMixin:OnClick()
    kacklaInsertIntoChat(self.insertText)
end

-- Shows the entry's tooltip lines, the first as the title
function KacklaPickerEntryMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, self.tooltipLines[1])
    for i = 2, #self.tooltipLines do
        GameTooltip_AddNormalLine(GameTooltip, self.tooltipLines[i])
    end
    GameTooltip:Show()
end

-- Hides the tooltip from OnEnter
function KacklaPickerEntryMixin:OnLeave()
    GameTooltip:Hide()
end

--------------------------------------------------------------------------------
-- The picker window

-- Mixin for KacklaPickerFrame in kackla.xml, which also has
-- TabSystemOwnerMixin for its tabs
KacklaPickerMixin = {}

-- Adds the tabs, closes with escape
function KacklaPickerMixin:OnLoad()
    TabSystemOwnerMixin.OnLoad(self)
    table.insert(UISpecialFrames, self:GetName())
    self.TitleText:SetText("kackla")
    self:SetTabSystem(self.TabSystem)
    self.emoticonsTab = self:AddNamedTab("Emoticons", self.Emoticons)
    self.colorsTab = self:AddNamedTab("Colors", self.Colors)
    self:SetTabCallback(self.emoticonsTab, function() self:FitTo(self.Emoticons) end)
    self:SetTabCallback(self.colorsTab, function() self:FitTo(self.Colors) end)
end

-- Fills the tabs on first show, updates the colors (the game can change
-- class and item quality colors) and shows the selected tab
function KacklaPickerMixin:OnShow()
    -- the tabs measured their text while the window was hidden in OnLoad
    for _, tabID in ipairs({self.emoticonsTab, self.colorsTab}) do
        self:GetTabButton(tabID):UpdateTabWidth()
    end
    self.TabSystem:MarkDirty()
    if not self.filled then
        self:FillEmoticons()
        self.filled = true
    end
    self:FillColors()
    self:SetTab(self:GetTab() or self.emoticonsTab)
end

-- Sizes the window to fit page, the content of a tab
function KacklaPickerMixin:FitTo(page)
    self:SetSize(page:GetWidth() + 2 * MARGIN_X, page:GetHeight() + MARGIN_TOP + MARGIN_BOTTOM)
end

-- Returns a new entry on page
function KacklaPickerMixin:NewEntry(page)
    return CreateFrame("Button", nil, page, "KacklaPickerEntryTemplate")
end

-- Places entry at column and row of a grid starting y pixels down on its page
local function Place(entry, column, row, y)
    entry:ClearAllPoints()
    entry:SetPoint("TOPLEFT", column * (ENTRY_SIZE + ENTRY_SPACING), -(y + row * (ENTRY_SIZE + ENTRY_SPACING)))
    entry:Show()
end

-- Returns the size of count entries in a row or column
local function Span(count)
    return count * ENTRY_SIZE + math.max(0, count - 1) * ENTRY_SPACING
end

-- Fills the emoticons tab: raid icons, then the emoticons in list order
function KacklaPickerMixin:FillEmoticons()
    local entries = {}
    for index, tags in ipairs(kacklaRaidIcons) do
        table.insert(entries, {
            text = tags[1],
            label = kacklaRaidIconTexture(index),
            tooltip = {table.concat(tags, " "), "Raid icon, shown by the game itself"},
        })
    end
    for _, emoticon in ipairs(kacklaEmoticonList) do
        local shortcut = ":" .. emoticon[1] .. ":"
        table.insert(entries, {
            text = shortcut,
            label = emoticon[2],
            tooltip = {shortcut, "Replaced with its symbol in channels where the alias is used"},
        })
    end

    local page = self.Emoticons
    for i, entry in ipairs(entries) do
        local button = self:NewEntry(page)
        button:Init(entry.text, entry.label, entry.tooltip)
        Place(button, math.floor((i - 1) / EMOTICON_ROWS), (i - 1) % EMOTICON_ROWS, 0)
    end
    page:SetSize(Span(math.ceil(#entries / EMOTICON_ROWS)), Span(EMOTICON_ROWS))
end

-- The groups of the colors tab: a title and the Color values shown
local function ColorGroups()
    local function Values(kind, enum)
        local values = {}
        for _, value in ipairs(enum.values) do
            table.insert(values, {kind, value})
        end
        return values
    end
    local basic = Values("named", kacklaMessages.NamedColor)
    table.insert(basic, 1, {"reset", true})
    return {
        {"Colors", basic},
        {"Class colors", Values("class", kacklaMessages.ClassColor)},
        {"Item quality colors", Values("quality", kacklaMessages.ItemQuality)},
    }
end

-- Returns the token for a Color value, e.g. ":#red:" or ":#:" for reset
local function Token(color)
    if color[1] == "reset" then
        return ":#:"
    end
    return ":#" .. string.lower(color[2]) .. ":"
end

-- Fills the colors tab, one row per group under its title. Colors this
-- client doesn't have (e.g. a class from a later expansion) are left out.
function KacklaPickerMixin:FillColors()
    local page = self.Colors
    self.colorEntries = self.colorEntries or {}
    self.colorTitles = self.colorTitles or {}
    for _, entry in pairs(self.colorEntries) do
        entry:Hide()
    end

    local y, width = 0, 0
    for g, group in ipairs(ColorGroups()) do
        local title = self.colorTitles[g]
        if not title then
            title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            self.colorTitles[g] = title
        end
        title:SetText(group[1])
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 0, -y)
        y = y + TITLE_HEIGHT

        local column = 0
        for _, color in ipairs(group[2]) do
            local token = Token(color)
            local rgb = kacklaColors.rgbOf(color)
            if rgb or color[1] == "reset" then
                local button = self.colorEntries[token]
                if not button then
                    button = self:NewEntry(page)
                    self.colorEntries[token] = button
                end
                if color[1] == "reset" then
                    button:Init(token, "x", {token, "Back to the channel's color"})
                else
                    button:Init(token, nil, {token, "Colors the text after it for players with kackla"})
                    button.Swatch:SetColorTexture(kacklaColors.split(rgb))
                end
                Place(button, column, 0, y)
                column = column + 1
            end
        end
        width = math.max(width, Span(column))
        y = y + ENTRY_SIZE + ENTRY_SPACING
    end
    page:SetSize(math.max(width, 1), y - ENTRY_SPACING)
end
