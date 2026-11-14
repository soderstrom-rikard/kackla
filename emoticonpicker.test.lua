-- Tests the emoticon picker, run with make test
require("testsetup")

-- Tests the emoticon picker button and menu against mocked WoW UI APIs
function checkEmoticonPicker()
    print("Verify emoticon picker start")

    -- chat edit box mocks
    local inserted, opened
    local editBox = {Insert = function(self, text) inserted = text end}
    local activeEditBox
    ChatFrameUtil = {
        GetActiveWindow = function() return activeEditBox end,
        OpenChat = function(text)
            assert(text == nil, "OpenChat should get nil text, got '" .. tostring(text) .. "'")
            opened = true
            return editBox
        end,
    }

    activeEditBox = editBox
    kacklaInsertIntoChat(":heart:")
    assert(inserted == ":heart:" and not opened, "should insert into the active edit box")
    activeEditBox = nil
    inserted = nil
    kacklaInsertIntoChat("{rt8}")
    assert(inserted == "{rt8}" and opened, "should open chat and then insert")

    -- menu mocks, collecting the created entries
    MenuConstants = {VerticalGridDirection = 2}
    MenuResponse = {Open = 1, Refresh = 2, Close = 3, CloseAll = 4}
    ChatFontNormal = {name = "ChatFontNormal"}
    AnchorUtil = {CreateAnchor = function(...) return {...} end}
    local tooltipLines
    GameTooltip_SetTitle = function(tooltip, text) tooltipLines = {text} end
    GameTooltip_AddNormalLine = function(tooltip, text) table.insert(tooltipLines, text) end
    local entries, grid = {}, nil
    local rootDescription = {
        SetTag = function() end,
        CreateButton = function(self, label, callback)
            local entry = {label = label, callback = callback}
            table.insert(entries, entry)
            return {
                SetTooltip = function(_, func) entry.tooltip = func end,
                AddInitializer = function(_, func) entry.initializer = func end,
            }
        end,
        SetGridMode = function(self, direction, columns) grid = {direction, columns} end,
    }

    NORMAL_FONT_COLOR = {GetRGB = function() return 1, 0.82, 0 end}
    local button = {Label = {
        SetTextColor = function(self, r, g, b) self.color = {r, g, b} end,
        SetTextScale = function(self, scale) self.scale = scale end,
    }}
    for k, v in pairs(KacklaEmoticonButtonMixin) do button[k] = v end
    button.SetText = function(self, text) self.text = text end
    button.SetMenuAnchor = function(self, anchor) self.anchor = anchor end
    button.SetupMenu = function(self, generator) generator(self, rootDescription) end
    button.RegisterForMouse = function(self, ...) self.mouse = {...} end
    button.RegisterForClicks = function(self, ...) self.clicks = {...} end
    local menuToggles = 0
    button.SetMenuOpen = function(self, open) menuToggles = menuToggles + 1 end
    -- the intrinsic's mouse down handler, bound before our OnLoad runs
    local mouseDown = function(self) self:SetMenuOpen(true) end
    local rightButtonDown = false
    IsMouseButtonDown = function(mouseButton)
        return mouseButton == "RightButton" and rightButtonDown
    end
    button:OnLoad()

    -- left mouse down toggles the menu, right-click toggles the settings
    assert(table.concat(button.mouse, ",") == "LeftButtonDown,LeftButtonUp,RightButtonDown,RightButtonUp",
           "should listen to both mouse buttons")
    assert(table.concat(button.clicks, ",") == "RightButtonUp", "should only click on right button")
    mouseDown(button)
    rightButtonDown = true
    mouseDown(button)
    rightButtonDown = false
    assert(menuToggles == 1, "only the left button should toggle the menu, got " .. menuToggles)
    local toggles = 0
    local originalToggle = kacklaToggleSettings
    kacklaToggleSettings = function() toggles = toggles + 1 end
    button:OnClick("LeftButton")
    button:OnClick("RightButton")
    assert(toggles == 1, "right-click should toggle the settings, got " .. toggles)
    kacklaToggleSettings = originalToggle

    assert(button.text == "☺", "button text should be ☺, got '" .. tostring(button.text) .. "'")
    assert(button.Label.color[1] == 1 and button.Label.color[2] == 0.82 and button.Label.color[3] == 0,
           "button text should be gold")
    assert(button.Label.scale == 1.5, "button text should be scaled up")
    assert(button.anchor[1] == "BOTTOMLEFT" and button.anchor[3] == "TOPRIGHT", "menu should open upwards")

    local count = #kacklaRaidIcons + #kacklaEmoticonList
    assert(#entries == count, "expected " .. count .. " entries, got " .. #entries)
    assert(grid[1] == 2 and grid[2] == math.ceil(count / 8), "unexpected grid " .. tostring(grid[2]))

    -- every entry uses the chat font and keeps the menu open when picked
    for i, entry in ipairs(entries) do
        local fontObject
        entry.initializer({fontString = {SetFontObject = function(_, font) fontObject = font end}})
        assert(fontObject == ChatFontNormal, "entry " .. i .. " should use ChatFontNormal")
        assert(entry.callback() == MenuResponse.Open, "entry " .. i .. " should keep the menu open")
    end

    -- raid icons first, inserting their {rtN} tag
    for index, tags in ipairs(kacklaRaidIcons) do
        local entry = entries[index]
        assert(entry.label == kacklaRaidIconTexture(index), "raid icon " .. index .. " label")
        entry.callback()
        assert(inserted == tags[1], "raid icon " .. index .. " inserted '" .. tostring(inserted) .. "'")
        entry.tooltip({})
        assert(tooltipLines[1] == table.concat(tags, " "), "raid icon " .. index .. " tooltip")
    end

    -- then the emoticons in list order, inserting their :name: shortcut
    for i, emoticon in ipairs(kacklaEmoticonList) do
        local entry = entries[#kacklaRaidIcons + i]
        assert(entry.label == emoticon[2], emoticon[1] .. " label '" .. entry.label .. "'")
        entry.callback()
        assert(inserted == ":" .. emoticon[1] .. ":", emoticon[1] .. " inserted '" .. tostring(inserted) .. "'")
        entry.tooltip({})
        assert(tooltipLines[1] == ":" .. emoticon[1] .. ":", emoticon[1] .. " tooltip")
    end

    print("Verify emoticon picker done")
end

checkEmoticonPicker()
