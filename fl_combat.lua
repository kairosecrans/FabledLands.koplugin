--[[--
The combat tracker.

A fight is resolved one round at a time: you strike, then if the enemy is
still standing it strikes back; you strike first unless the book says
otherwise (p. 6). The book sometimes gives the enemy the first blow, so there
is a separate button for a lone enemy strike.

The fight is stored on the character, so closing the panel to re-read the page
does not lose the enemy's Stamina.

@module koplugin.FabledLands.combat
--]]--

local Format = require("fl_format")
local Prompts = require("fl_prompts")
local Rules = require("fl_rules")
local _ = require("gettext")

local Combat = {}

-- How many log lines to keep on screen.
local LOG_LIMIT = 12

local function logLine(fight, line)
    table.insert(fight.log, line)
    while #fight.log > LOG_LIMIT do
        table.remove(fight.log, 1)
    end
end

--- Asks for the enemy's COMBAT, Defence and Stamina, as printed in the book.
function Combat.start(plugin)
    -- The labels live in the hints rather than in per-field descriptions:
    -- with the keyboard up, four extra label rows push the buttons off the
    -- bottom of a phone screen.
    Prompts.fields{
        title = _("Who are you fighting?"),
        fields = {
            { text = "", hint = _("Enemy, e.g. Goblin") },
            { input_type = "number", text = "", hint = _("COMBAT, e.g. 5") },
            { input_type = "number", text = "", hint = _("Defence, e.g. 7") },
            { input_type = "number", text = "", hint = _("Stamina, e.g. 6") },
        },
        ok_text = _("Fight"),
        callback = function(values)
            local stamina = tonumber(values[4])
            local fight = {
                name = (values[1] or ""):match("^%s*(.-)%s*$"),
                combat = tonumber(values[2]) or 0,
                defence = tonumber(values[3]) or 0,
                stamina = stamina or 0,
                stamina_max = stamina or 0,
                round = 0,
                log = {},
            }
            if not stamina or stamina <= 0 or not tonumber(values[3]) then
                Prompts.info(_("A fight needs at least the enemy's Defence and Stamina."))
                return
            end
            plugin.character.fight = fight
            plugin:save()
            Combat.show(plugin)
        end,
    }
end

--- Your blow, then the enemy's reply if it survives.
local function fightRound(plugin)
    local character = plugin.character
    local fight = character.fight

    fight.round = fight.round + 1
    logLine(fight, ("Round %d"):format(fight.round))

    local blow = character:attack(fight.defence)
    fight.stamina = math.max(0, fight.stamina - blow.damage)
    logLine(fight, Format.blow(_("You"), blow))

    if fight.stamina > 0 then
        local reply = Rules.strike(fight.combat, 0, character:defence())
        character:takeDamage(reply.damage)
        logLine(fight, Format.blow(fight.name ~= "" and fight.name or _("Enemy"), reply))
    end

    plugin:save()
end

--- Only the enemy strikes: for the openings where the book says so.
local function enemyRound(plugin)
    local character = plugin.character
    local fight = character.fight

    local reply = Rules.strike(fight.combat, 0, character:defence())
    character:takeDamage(reply.damage)
    logLine(fight, Format.blow(fight.name ~= "" and fight.name or _("Enemy"), reply))
    plugin:save()
end

local function endFight(plugin)
    plugin.character.fight = nil
    plugin:save()
end

--- The combat panel. Rebuilt after every action so the numbers stay live.
function Combat.show(plugin)
    local character = plugin.character
    local fight = character.fight
    if not fight then
        Combat.start(plugin)
        return
    end

    local over = fight.stamina <= 0 or character:isDead()
    local buttons = {}

    if over then
        -- Stop tracking a decided fight straight away. `fight` is still held
        -- locally for this last render, but dismissing the panel can no
        -- longer leave a defeated enemy waiting on the sheet.
        endFight(plugin)
        table.insert(buttons, { {
            text = _("Done"),
            callback = function() plugin:showSheet() end,
        } })
    else
        table.insert(buttons, { {
            text = _("Attack"),
            callback = function()
                fightRound(plugin)
                Combat.show(plugin)
            end,
        } })
        table.insert(buttons, {
            {
                text = _("Enemy strikes"),
                callback = function()
                    enemyRound(plugin)
                    Combat.show(plugin)
                end,
            },
            {
                text = _("Drink potion"),
                callback = function()
                    Prompts.number{
                        title = _("Restore how much Stamina?"),
                        info = _("A potion of healing restores 5."),
                        value = 5,
                        min = 1,
                        max = 50,
                        ok_text = _("Drink"),
                        callback = function(amount)
                            local gained = character:heal(amount)
                            logLine(fight, ("  You drink -- +%d Stamina"):format(gained))
                            plugin:save()
                            Combat.show(plugin)
                        end,
                    }
                end,
            },
        })
        table.insert(buttons, {
            {
                text = _("Flee"),
                callback = function()
                    endFight(plugin)
                    Prompts.info(_("You flee the fight. Follow the book for what that costs you."))
                    plugin:showSheet()
                end,
            },
            {
                text = _("Give up fight"),
                callback = function()
                    Prompts.confirm{
                        text = _("Abandon this fight and forget the enemy's Stamina?"),
                        ok_text = _("Abandon"),
                        ok_callback = function()
                            endFight(plugin)
                            plugin:showSheet()
                        end,
                        cancel_callback = function() Combat.show(plugin) end,
                    }
                end,
            },
        })
    end

    local panel = {
        title = Format.fight(character, fight),
        buttons = buttons,
    }
    -- Written out rather than as `over and false or _("Close")`: that idiom
    -- silently yields "Close" for both cases, because `false` is falsy and
    -- the `or` takes over.
    if over then
        panel.close_text = false
    else
        panel.close_text = _("Close")
    end
    Prompts.panel(panel)
end

return Combat
