--[[--
The minimized badge: a small floating marker that stays on screen while you
read, and taps back to whatever plugin screen you left.

The whole thing hinges on one KOReader detail. UIManager:sendEvent dispatches
to the topmost *non-toast* widget and stops there; widgets flagged `toast`
receive every event but never halt propagation. So a toast badge can notice
its own taps while page turns still reach the reader underneath. A normal
widget in this position would swallow them and make the book unreadable.

UIManager also keeps toasts above every other window, so left alone the badge
would sit on top of KOReader's own menus and dialogs, and a tap on it would
press whatever button is underneath as well. It therefore only draws and
answers taps while the page itself is the top window.

The trade-off of that same mechanism: a tap on the badge also reaches the
reader, so it may turn a page as well as restoring. The badge therefore sits
in the corner that does the least damage, and restoring is also bound to a
dispatcher action for anyone who would rather use a gesture.

@module koplugin.FabledLands.badge
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Badge = InputContainer:extend{
    -- Never stop events reaching the page underneath.
    toast = true,
    text = "",
    on_tap = nil,
    -- The ReaderUI the badge floats over.
    reader = nil,
}

function Badge:init()
    local label = TextWidget:new{
        text = self.text,
        face = Font:getFace("x_smallinfofont"),
    }
    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.thin,
        radius = Size.radius.window,
        padding = Size.padding.small,
        margin = 0,
        label,
    }

    local size = frame:getSize()
    -- Placement is constrained by KOReader's default tap zones, and since a
    -- toast never stops propagation, a tap here also reaches the reader.
    -- The top eighth opens the menu and the bottom eighth opens the config
    -- bar, so both strips are out. The left quarter is the page-back zone,
    -- which is the least disruptive thing a stray tap can do, and the middle
    -- band keeps clear of the two menu strips.
    local margin = Size.margin.default
    self.dimen = Geom:new{
        x = margin,
        y = math.floor(Screen:getHeight() * 0.55),
        w = size.w,
        h = size.h,
    }
    frame.dimen = self.dimen
    self[1] = frame

    if Device:isTouchDevice() then
        self.ges_events.TapBadge = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        }
    end
end

--- True when the page is the top window, ignoring other toasts.
function Badge:isUncovered()
    if not self.reader then return true end
    for widget in UIManager:topdown_widgets_iter() do
        if widget ~= self and not widget.toast and not widget.invisible then
            return widget == self.reader
        end
    end
    return false
end

--- Paints at the fixed corner position rather than wherever the caller asks,
-- since this widget owns its placement. Stays hidden under a menu or dialog.
function Badge:paintTo(bb, x, y)
    if not self:isUncovered() then
        self.hidden = true
        return
    end
    InputContainer.paintTo(self, bb, self.dimen.x, self.dimen.y)
    if self.hidden then
        -- Closing a dialog repaints the badge but refreshes only the
        -- dialog's own area, which need not include the badge.
        self.hidden = false
        UIManager:setDirty(nil, "ui", self.dimen)
    end
end

function Badge:onTapBadge()
    if not self:isUncovered() then return false end
    if self.on_tap then self.on_tap() end
    return true
end

--- Repaints the strip the badge occupies, so the page underneath comes back
-- cleanly once it is gone.
function Badge:onCloseWidget()
    UIManager:setDirty(nil, "ui", self.dimen)
end

return Badge
