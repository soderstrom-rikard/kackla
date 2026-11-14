-- The emoticon picker, a button below the chat menu button (bottom left of
-- the main chat window) that opens a grid menu of emoticons and raid icons.
-- Clicking one inserts its :name: shortcut, or raid icon tag, at the cursor
-- of the chat message being typed. The button is defined in kackla.xml.

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

-- Raid icons first, the grid fills columns top to bottom so with 8 rows they
-- get the first column to themselves
local PICKER_ROWS = 8

-- Mixin for KacklaEmoticonButton in kackla.xml, a DropdownButton
KacklaEmoticonButtonMixin = {}

-- The DropdownButton intrinsic only listens to the left mouse button. This
-- adds the right button, which opens the settings instead of the menu.
function KacklaEmoticonButtonMixin:ListenToRightButton()
    self:RegisterForMouse("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
    self:RegisterForClicks("RightButtonUp")
end

-- Sets the ☺ label, the menu, which is created each time it opens, and
-- right-click opening the settings
function KacklaEmoticonButtonMixin:OnLoad()
    self:SetText(kacklaEmoticons.smile)
    -- gold like the chat menu button's bubble, and larger to fill the button
    self.Label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    if self.Label.SetTextScale then
        self.Label:SetTextScale(1.5)
    end
    -- the button is at the bottom of the screen, so open the menu upwards
    self:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMLEFT", self, "TOPRIGHT"))
    self:SetupMenu(function(dropdown, rootDescription)
        self:CreateEntries(rootDescription)
    end)

    -- the intrinsic toggles the menu on any mouse down, keep that to the left
    -- button. Its script is bound when the button loads, so replacing
    -- OnMouseDown_Intrinsic has no effect, but the SetMenuOpen it calls is
    -- looked up on the button each time.
    local setMenuOpen = self.SetMenuOpen
    self.SetMenuOpen = function(button, open)
        if not IsMouseButtonDown("RightButton") then
            setMenuOpen(button, open)
        end
    end
    self:ListenToRightButton()
end

-- Right-click toggles the settings window, left clicks are handled by the
-- intrinsic on mouse down
function KacklaEmoticonButtonMixin:OnClick(mouseButton)
    if mouseButton == "RightButton" then
        kacklaToggleSettings()
    end
end

-- Shows what the button does
function KacklaEmoticonButtonMixin:OnEnter()
    -- again, in case the intrinsic OnLoad ran after ours and reset it
    self:ListenToRightButton()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, "kackla emoticons")
    GameTooltip_AddNormalLine(GameTooltip, "Click to insert an emoticon or raid icon into your chat message")
    GameTooltip_AddNormalLine(GameTooltip, "Right-click to open the settings")
    GameTooltip:Show()
end

-- Hides the tooltip from OnEnter
function KacklaEmoticonButtonMixin:OnLeave()
    GameTooltip:Hide()
end

-- Menus use a font without most symbols (they show as boxes), the chat font
-- falls back to fonts that have them
local function UseChatFont(button)
    button.fontString:SetFontObject(ChatFontNormal)
end

-- Adds a button showing label, inserting text and with tooltip lines. The
-- menu stays open after a pick, so several can be inserted.
local function AddEntry(rootDescription, label, text, tooltipLines)
    local button = rootDescription:CreateButton(label, function()
        kacklaInsertIntoChat(text)
        return MenuResponse.Open
    end)
    button:AddInitializer(UseChatFont)
    button:SetTooltip(function(tooltip)
        GameTooltip_SetTitle(tooltip, tooltipLines[1])
        for i = 2, #tooltipLines do
            GameTooltip_AddNormalLine(tooltip, tooltipLines[i])
        end
    end)
end

-- Fills the menu with the raid icons followed by the emoticons, in a grid of
-- PICKER_ROWS rows
function KacklaEmoticonButtonMixin:CreateEntries(rootDescription)
    rootDescription:SetTag("MENU_KACKLA_EMOTICONS")

    for index, tags in ipairs(kacklaRaidIcons) do
        AddEntry(rootDescription, kacklaRaidIconTexture(index), tags[1],
                 {table.concat(tags, " "), "Raid icon, shown by the game itself"})
    end

    for _, entry in ipairs(kacklaEmoticonList) do
        local shortcut = ":" .. entry[1] .. ":"
        AddEntry(rootDescription, entry[2], shortcut,
                 {shortcut, "Replaced with its symbol in channels where the alias is used"})
    end

    local count = #kacklaRaidIcons + #kacklaEmoticonList
    rootDescription:SetGridMode(MenuConstants.VerticalGridDirection,
                                math.ceil(count / PICKER_ROWS))
end
