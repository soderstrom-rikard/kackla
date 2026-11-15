-- A window showing text ready to copy (KacklaCopyBoxFrame in kackla.xml).
-- Addons can't use the clipboard, CopyToClipboard is restricted to Blizzard's
-- own UI, so the text is shown selected and the player presses Ctrl+C.

-- Shows text with title in the copy window, selected
function kacklaShowCopyBox(title, text)
    local frame = KacklaCopyBoxFrame
    frame.TitleText:SetText(title)
    frame.Text = text
    frame:Show()
    frame:SelectText()
end

KacklaCopyBoxMixin = {}

-- Closes with escape, and can be dragged by its title bar
function KacklaCopyBoxMixin:OnLoad()
    table.insert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")
end

-- Moves the window while dragging it
function KacklaCopyBoxMixin:OnDragStart()
    self:StartMoving()
end

-- Stops moving the window
function KacklaCopyBoxMixin:OnDragStop()
    self:StopMovingOrSizing()
end

-- Puts the text back, in case it was edited, selects it and focuses the
-- edit box so Ctrl+C copies it
function KacklaCopyBoxMixin:SelectText()
    local editBox = self.Scroll.EditBox
    editBox:SetText(self.Text or "")
    editBox:SetFocus()
    editBox:HighlightText()
end
