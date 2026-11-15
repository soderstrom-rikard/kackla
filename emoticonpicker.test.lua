-- Tests the picker, run with make test
require("testsetup")

-- Mock tooltip, collecting the lines shown
local tooltipLines
GameTooltip = {
    SetOwner = function() end,
    Show = function() end,
    Hide = function() end,
}
GameTooltip_SetTitle = function(tooltip, text) tooltipLines = {text} end
GameTooltip_AddNormalLine = function(tooltip, text) table.insert(tooltipLines, text) end
NORMAL_FONT_COLOR = {GetRGB = function() return 1, 0.82, 0 end}

-- Returns a mock widget with the methods the picker uses
local function Widget(fields)
    local widget = {
        points = {},
        shown = true,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) table.insert(self.points, {...}) end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        SetShown = function(self, shown) self.shown = shown end,
        IsShown = function(self) return self.shown end,
        SetText = function(self, text) self.label = text end,
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        GetWidth = function(self) return self.width end,
        GetHeight = function(self) return self.height end,
        SetColorTexture = function(self, r, g, b) self.color = {r, g, b} end,
    }
    for k, v in pairs(fields or {}) do
        widget[k] = v
    end
    return widget
end

-- Mock CreateFrame for picker entries: a widget with the entry mixin
CreateFrame = function(frameType, name, parent, template)
    assert(template == "KacklaPickerEntryTemplate", "unexpected template " .. tostring(template))
    local entry = Widget({parent = parent, Swatch = Widget({shown = false}), SwatchBorder = Widget({shown = false})})
    for k, v in pairs(KacklaPickerEntryMixin) do
        entry[k] = v
    end
    table.insert(parent.entries, entry)
    return entry
end

-- Returns a mock page, collecting its entries and titles
local function Page()
    return Widget({
        shown = false,
        entries = {},
        titles = {},
        CreateFontString = function(self)
            local title = Widget()
            table.insert(self.titles, title)
            return title
        end,
    })
end

-- Returns a mock KacklaPickerFrame with a simple TabSystemOwnerMixin
local function PickerFrame()
    local frame = Widget({
        shown = false,
        TitleText = Widget(),
        TabSystem = {MarkDirty = function(self) self.dirty = true end},
        tabButtons = {},
        GetTabButton = function(self, tabID)
            self.tabButtons[tabID] = self.tabButtons[tabID] or {
                UpdateTabWidth = function(button) button.measured = (button.measured or 0) + 1 end,
            }
            return self.tabButtons[tabID]
        end,
        Emoticons = Page(),
        Colors = Page(),
        tabs = {},
        callbacks = {},
        GetName = function() return "KacklaPickerFrame" end,
        SetTabSystem = function(self, tabSystem) self.tabSystem = tabSystem end,
        AddNamedTab = function(self, name, page)
            table.insert(self.tabs, {name = name, page = page})
            return #self.tabs
        end,
        SetTabCallback = function(self, tabID, callback) self.callbacks[tabID] = callback end,
        SetTab = function(self, tabID)
            self.tab = tabID
            for id, tab in ipairs(self.tabs) do
                tab.page:SetShown(id == tabID)
            end
            self.callbacks[tabID]()
        end,
        GetTab = function(self) return self.tab end,
    })
    for k, v in pairs(KacklaPickerMixin) do
        frame[k] = v
    end
    return frame
end
TabSystemOwnerMixin = {OnLoad = function(self) self.ownerLoaded = true end}

-- Tests inserting into the chat message being typed
function checkInsertIntoChat()
    local inserted, opened
    local editBox = {Insert = function(self, text) inserted = text end}
    local activeEditBox
    ChatFrameUtil.GetActiveWindow = function() return activeEditBox end
    ChatFrameUtil.OpenChat = function(text)
        assert(text == nil, "OpenChat should get nil text, got '" .. tostring(text) .. "'")
        opened = true
        return editBox
    end

    activeEditBox = editBox
    kacklaInsertIntoChat(":heart:")
    assert(inserted == ":heart:" and not opened, "should insert into the active edit box")
    activeEditBox = nil
    inserted = nil
    kacklaInsertIntoChat("{rt8}")
    assert(inserted == "{rt8}" and opened, "should open chat and then insert")
end

-- Tests the ☺ button: label, clicks and tooltip
function checkPickerButton()
    local button = Widget({Label = Widget({
        SetTextColor = function(self, r, g, b) self.textColor = {r, g, b} end,
        SetTextScale = function(self, scale) self.scale = scale end,
    })})
    button.RegisterForClicks = function(self, ...) self.clicks = {...} end
    for k, v in pairs(KacklaEmoticonButtonMixin) do
        button[k] = v
    end
    button:OnLoad()
    assert(button.label == "☺", "button text should be ☺, got '" .. tostring(button.label) .. "'")
    assert(button.Label.textColor[1] == 1 and button.Label.textColor[2] == 0.82, "button text should be gold")
    assert(button.Label.scale == 1.5, "button text should be scaled up")
    assert(table.concat(button.clicks, ",") == "LeftButtonUp,RightButtonUp", "clicks with both buttons")

    -- left-click toggles the picker, right-click the settings
    KacklaPickerFrame = Widget({shown = false})
    local settingsToggles = 0
    local originalToggle = kacklaToggleSettings
    kacklaToggleSettings = function() settingsToggles = settingsToggles + 1 end
    button:OnClick("LeftButton")
    assert(KacklaPickerFrame.shown and settingsToggles == 0, "left-click opens the picker")
    button:OnClick("LeftButton")
    assert(not KacklaPickerFrame.shown, "left-click again closes it")
    button:OnClick("RightButton")
    assert(settingsToggles == 1 and not KacklaPickerFrame.shown, "right-click toggles the settings")
    kacklaToggleSettings = originalToggle
    KacklaPickerFrame = nil

    button:OnEnter()
    assert(tooltipLines[1] == "kackla", "tooltip title '" .. tostring(tooltipLines[1]) .. "'")
    assert(#tooltipLines == 3, "tooltip explains both clicks")
end

-- Returns the column and row of an entry from its TOPLEFT point
local function Cell(entry)
    local point = entry.points[1]
    return point[2] / 28, -point[3] / 28
end

-- Tests the picker window: tabs, the emoticons and the colors
function checkPickerFrame()
    RAID_CLASS_COLORS = {MAGE = {r = 0.25, g = 0.78, b = 0.92}}
    ITEM_QUALITY_COLORS = {[4] = {r = 0.64, g = 0.21, b = 0.93}}
    UISpecialFrames = {}
    local inserted
    local originalInsert = kacklaInsertIntoChat
    kacklaInsertIntoChat = function(text) inserted = text end

    local frame = PickerFrame()
    frame:OnLoad()
    assert(frame.ownerLoaded and frame.tabSystem == frame.TabSystem, "tab system set up")
    assert(UISpecialFrames[1] == "KacklaPickerFrame", "closes with escape")
    assert(frame.TitleText.label == "kackla", "title")
    assert(#frame.tabs == 2 and frame.tabs[1].name == "Emoticons" and frame.tabs[2].name == "Colors", "two tabs")

    -- opening shows the emoticons tab, sized to fit
    frame:OnShow()
    assert(frame.Emoticons.shown and not frame.Colors.shown, "emoticons tab first")
    assert(frame.tabButtons[1].measured == 1 and frame.tabButtons[2].measured == 1 and frame.TabSystem.dirty,
           "tabs measure their text when the window opens")
    local entries = frame.Emoticons.entries
    local count = #kacklaRaidIcons + #kacklaEmoticonList
    assert(#entries == count, "expected " .. count .. " entries, got " .. #entries)
    local columns = math.ceil(count / 8)
    assert(frame.Emoticons.width == columns * 26 + (columns - 1) * 2 and frame.Emoticons.height == 8 * 26 + 7 * 2,
           "emoticons page size")
    assert(frame.width == frame.Emoticons.width + 24 and frame.height == frame.Emoticons.height + 44, "window size")

    -- raid icons in the first column, then the emoticons column by column
    for index, tags in ipairs(kacklaRaidIcons) do
        local entry = entries[index]
        local column, row = Cell(entry)
        assert(column == 0 and row == index - 1, "raid icon " .. index .. " in the first column")
        assert(entry.label == kacklaRaidIconTexture(index), "raid icon " .. index .. " label")
        entry:OnClick()
        assert(inserted == tags[1], "raid icon " .. index .. " inserted '" .. tostring(inserted) .. "'")
        entry:OnEnter()
        assert(tooltipLines[1] == table.concat(tags, " "), "raid icon " .. index .. " tooltip")
    end
    for i, emoticon in ipairs(kacklaEmoticonList) do
        local index = #kacklaRaidIcons + i
        local entry = entries[index]
        local column, row = Cell(entry)
        assert(column == math.floor((index - 1) / 8) and row == (index - 1) % 8, emoticon[1] .. " position")
        assert(entry.label == emoticon[2] and not entry.Swatch.shown, emoticon[1] .. " label")
        entry:OnClick()
        assert(inserted == ":" .. emoticon[1] .. ":", emoticon[1] .. " inserted '" .. tostring(inserted) .. "'")
    end

    -- the colors tab: reset and the named colors, the class and item quality
    -- colors this client has
    frame:SetTab(frame.colorsTab)
    assert(frame.Colors.shown and not frame.Emoticons.shown, "colors tab")
    assert(frame.width == frame.Colors.width + 24, "window fits the colors tab")
    local shown = {}
    for _, entry in ipairs(frame.Colors.entries) do
        if entry.shown then
            entry:OnClick()
            table.insert(shown, inserted)
        end
    end
    local expected = {":#:"}
    for _, name in ipairs(kacklaMessages.NamedColor.values) do
        table.insert(expected, ":#" .. name .. ":")
    end
    table.insert(expected, ":#mage:")
    table.insert(expected, ":#epic:")
    assert(table.concat(shown, " ") == table.concat(expected, " "), "color entries: " .. table.concat(shown, " "))
    assert(#frame.Colors.titles == 3 and frame.Colors.titles[2].label == "Class colors", "group titles")

    -- swatches show the colors, reset has a label
    local reset, red, mage = frame.Colors.entries[1], frame.Colors.entries[2], nil
    for _, entry in ipairs(frame.Colors.entries) do
        entry:OnClick()
        if inserted == ":#mage:" then mage = entry end
    end
    assert(reset.label == "x" and not reset.Swatch.shown and not reset.SwatchBorder.shown, "reset has a label")
    assert(red.Swatch.shown and red.SwatchBorder.shown and red.Swatch.color[1] == 1, "red swatch with border")
    local column, row = Cell(mage)
    assert(column == 0, "mage starts the class row")
    red:OnEnter()
    assert(tooltipLines[1] == ":#red:", "color tooltip")

    -- reopening updates the colors: a class color the game adds later shows
    RAID_CLASS_COLORS.EVOKER = {r = 0.2, g = 0.58, b = 0.5}
    frame:OnShow()
    local evoker = false
    for _, entry in ipairs(frame.Colors.entries) do
        entry:OnClick()
        if entry.shown and inserted == ":#evoker:" then evoker = true end
    end
    assert(evoker, "evoker shown once the game has its color")
    assert(#frame.Emoticons.entries == count, "emoticons aren't created twice")

    kacklaInsertIntoChat = originalInsert
end

print("Verify emoticon picker start")
checkInsertIntoChat()
checkPickerButton()
checkPickerFrame()
print("Verify emoticon picker done")
