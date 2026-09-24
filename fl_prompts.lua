--[[--
Thin wrappers over the KOReader widgets this plugin uses, so the view code
reads as intent ("ask for a number") rather than widget plumbing.

@module koplugin.FabledLands.prompts
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local logger = require("logger")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Prompts = {}

--- A monospaced face, so the Adventure Sheet and combat log line up in columns.
--
-- Resolved on first use rather than at require time, and through a fallback
-- chain. Font names are not a stable API between KOReader versions, and this
-- module is pulled in by main.lua's very first require: a throw here happens
-- before the plugin can register anything, so the whole plugin would vanish
-- with no menu entry and no error anyone could act on. Losing the monospaced
-- columns is a far smaller price.
local FACE_NAMES = { "smallinfont", "infont", "smallinfofont", "infofont", "cfont" }
local mono_face, mono_resolved

function Prompts.monoFace()
    if not mono_resolved then
        mono_resolved = true
        for _i, name in ipairs(FACE_NAMES) do
            local ok, face = pcall(Font.getFace, Font, name)
            if ok and face then
                mono_face = face
                break
            end
        end
        if not mono_face then
            logger.warn("Fabled Lands: no usable font face; falling back to the widget default")
        end
    end
    return mono_face
end

function Prompts.info(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

--- Asks for a number with the spinner, which beats a keyboard on e-ink.
-- @tparam table opts title, info, value, min, max, hold_step, ok_text, callback
function Prompts.number(opts)
    local spinner = SpinWidget:new{
        title_text = opts.title,
        info_text = opts.info,
        value = opts.value or 0,
        value_min = opts.min or 0,
        value_max = opts.max or 99,
        value_step = 1,
        value_hold_step = opts.hold_step or 5,
        ok_text = opts.ok_text or _("OK"),
        ok_always_enabled = true,
        callback = function(spin)
            opts.callback(spin.value)
        end,
    }
    UIManager:show(spinner)
    return spinner
end

--- Asks for a line of text.
-- Set `input_type = "number"` for a numeric keypad, which beats the spinner
-- whenever the value could be three digits.
-- @tparam table opts title, description, value, hint, input_type, ok_text, callback
function Prompts.text(opts)
    local dialog
    dialog = InputDialog:new{
        title = opts.title,
        description = opts.description,
        input = opts.value or "",
        input_hint = opts.hint,
        input_type = opts.input_type,
        buttons = { {
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = opts.ok_text or _("Save"),
                is_enter_default = true,
                callback = function()
                    local value = dialog:getInputText()
                    UIManager:close(dialog)
                    opts.callback(value)
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

--- Asks for several values at once.
-- `extra` adds a third button that receives whatever has been typed so far,
-- which is how a half-filled form can be minimized and come back intact.
-- @tparam table opts title, fields (as MultiInputDialog), ok_text, callback(values), extra
function Prompts.fields(opts)
    local dialog
    local row = {
        {
            text = _("Cancel"),
            id = "close",
            callback = function() UIManager:close(dialog) end,
        },
        {
            text = opts.ok_text or _("OK"),
            is_enter_default = true,
            callback = function()
                local values = dialog:getFields()
                UIManager:close(dialog)
                opts.callback(values)
            end,
        },
    }
    if opts.extra then
        table.insert(row, 2, {
            text = opts.extra.text,
            callback = function()
                local values = dialog:getFields()
                UIManager:close(dialog)
                opts.extra.callback(values)
            end,
        })
    end

    dialog = MultiInputDialog:new{
        title = opts.title,
        fields = opts.fields,
        buttons = { row },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

--- Shows a panel: a monospaced block of text above a grid of buttons.
-- Each row of `buttons` is a list of { text, callback, hold_callback }.
-- Callbacks fire after the panel closes, unless the button sets keep_open.
-- @tparam table opts title, buttons, close_text, close_callback, dismissable
-- @treturn widget the dialog, so callers can close it themselves
function Prompts.panel(opts)
    local dialog
    local rows = {}
    for _i, row in ipairs(opts.buttons or {}) do
        local built = {}
        for _i, button in ipairs(row) do
            table.insert(built, {
                text = button.text,
                enabled = button.enabled ~= false,
                callback = function()
                    if not button.keep_open then UIManager:close(dialog) end
                    if button.callback then button.callback() end
                end,
                hold_callback = button.hold_callback and function()
                    if not button.keep_open then UIManager:close(dialog) end
                    button.hold_callback()
                end,
            })
        end
        table.insert(rows, built)
    end
    if opts.close_text ~= false then
        table.insert(rows, { {
            text = opts.close_text or _("Close"),
            callback = function()
                UIManager:close(dialog)
                if opts.close_callback then opts.close_callback() end
            end,
        } })
    end

    dialog = ButtonDialog:new{
        title = opts.title,
        title_align = opts.title_align or "left",
        info_face = opts.face or Prompts.monoFace(),
        dismissable = opts.dismissable ~= false,
        buttons = rows,
    }
    UIManager:show(dialog)
    return dialog
end

--- A one-column panel built from a flat list of { text, callback } items.
-- @tparam table opts title, items, close_text, close_callback
function Prompts.menu(opts)
    local rows = {}
    for _i, item in ipairs(opts.items or {}) do
        table.insert(rows, { item })
    end
    return Prompts.panel{
        title = opts.title,
        title_align = opts.title_align,
        face = opts.face,
        buttons = rows,
        close_text = opts.close_text,
        close_callback = opts.close_callback,
    }
end

--- Asks for confirmation before something irreversible.
-- @tparam table opts text, ok_text, ok_callback, cancel_callback
function Prompts.confirm(opts)
    UIManager:show(ConfirmBox:new{
        text = opts.text,
        ok_text = opts.ok_text or _("OK"),
        ok_callback = opts.ok_callback,
        cancel_callback = opts.cancel_callback,
    })
end

return Prompts
