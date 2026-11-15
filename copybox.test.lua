-- Tests the copy window, run with make test
require("testsetup")

-- Tests that the copy window shows the text selected and focused, and that
-- selecting again puts back edited text
function checkCopyBox()
    print("Verify copy box start")
    local editBox = {
        SetText = function(self, text) self.text = text end,
        SetFocus = function(self) self.focused = true end,
        HighlightText = function(self) self.highlighted = true end,
    }
    KacklaCopyBoxFrame = {
        Scroll = {EditBox = editBox},
        TitleText = {SetText = function(self, text) self.text = text end},
        Show = function(self) self.shown = true end,
    }
    for k, v in pairs(KacklaCopyBoxMixin) do KacklaCopyBoxFrame[k] = v end

    kacklaShowCopyBox("Title", "line 1\nline 2")
    assert(KacklaCopyBoxFrame.shown, "copy box should be shown")
    assert(KacklaCopyBoxFrame.TitleText.text == "Title", "copy box title")
    assert(editBox.text == "line 1\nline 2", "copy box text '" .. tostring(editBox.text) .. "'")
    assert(editBox.focused and editBox.highlighted, "copy box text should be focused and selected")

    editBox.text = "edited"
    KacklaCopyBoxFrame:SelectText()
    assert(editBox.text == "line 1\nline 2", "selecting should put back the original text")
    KacklaCopyBoxFrame = nil
    print("Verify copy box done")
end

checkCopyBox()
