--[[--
The combat tracker.

A fight is resolved one round at a time: you strike, then if the enemy is
still standing it strikes back; you strike first unless the book says
otherwise (p. 6). The book sometimes gives the enemy the first blow, so there
is a separate button for a lone enemy strike.

Two situational modifiers cover the local rules the books spring on you: a
signed adjustment to your attack rolls, and one to your Defence for the
duration of the fight. Both are signed, because the books hand out penalties
as well as bonuses. Neither touches the Adventure Sheet -- they live and die
with the fight.

Some encounters say to fight several foes one at a time. "Next enemy" keeps
the same fight going, so your Stamina, the round count and the log all carry
over instead of restarting.

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

local function enemyName(fight)
    return fight.name ~= "" and fight.name or _("Enemy")
end

--- Asks for a stat block and hands back a fight table, or nil plus a reason.
-- @tparam table values the four raw strings from the setup dialog
-- @tparam table carry optional existing fight whose state should continue
local function buildFight(values, carry)
    local stamina = tonumber(values[4])
    if not stamina or stamina <= 0 or not tonumber(values[3]) then
        return nil, _("A fight needs at least the enemy's Defence and Stamina.")
    end
    return {
        name = (values[1] or ""):match("^%s*(.-)%s*$"),
        combat = tonumber(values[2]) or 0,
        defence = tonumber(values[3]) or 0,
        stamina = stamina,
        stamina_max = stamina,
        -- Carried across a "one at a time" sequence; fresh otherwise.
        round = carry and carry.round or 0,
        log = carry and carry.log or {},
        attack_mod = carry and carry.attack_mod or 0,
        defence_mod = carry and carry.defence_mod or 0,
    }
end

--- The stat-block form. `typed` repopulates it after a minimise, so you can
-- duck back to the page for the enemy's numbers without losing your place.
local function askStatBlock(plugin, title, ok_text, callback, typed)
    typed = typed or {}
    -- The labels live in the hints rather than in per-field descriptions:
    -- with the keyboard up, four extra label rows push the buttons off the
    -- bottom of a phone screen.
    Prompts.fields{
        title = title,
        fields = {
            { text = typed[1] or "", hint = _("Enemy, e.g. Goblin") },
            { input_type = "number", text = typed[2] or "", hint = _("COMBAT, e.g. 5") },
            { input_type = "number", text = typed[3] or "", hint = _("Defence, e.g. 7") },
            { input_type = "number", text = typed[4] or "", hint = _("Stamina, e.g. 6") },
        },
        ok_text = ok_text,
        callback = callback,
        extra = {
            text = _("Minimise"),
            callback = function(values)
                plugin:minimise(function()
                    askStatBlock(plugin, title, ok_text, callback, values)
                end, "combat")
            end,
        },
    }
end

--- Asks for the enemy's COMBAT, Defence and Stamina, as printed in the book.
function Combat.start(plugin)
    askStatBlock(plugin, _("Who are you fighting?"), _("Fight"), function(values)
        local fight, err = buildFight(values)
        if not fight then
            Prompts.info(err)
            return
        end
        plugin.character.fight = fight
        plugin:save()
        Combat.show(plugin)
    end)
end

--- Continues the same fight against the next foe in a sequence.
local function nextEnemy(plugin)
    local carry = plugin.character.fight
    askStatBlock(plugin, _("Who steps up next?"), _("Fight"), function(values)
        local fight, err = buildFight(values, carry)
        if not fight then
            Prompts.info(err)
            return
        end
        logLine(fight, ("-- %s steps up --"):format(
            fight.name ~= "" and fight.name or _("the next foe")))
        plugin.character.fight = fight
        plugin:save()
        Combat.show(plugin)
    end)
end

--- Your blow, then the enemy's reply if it survives.
local function fightRound(plugin)
    local character = plugin.character
    local fight = character.fight

    fight.round = fight.round + 1
    logLine(fight, ("Round %d"):format(fight.round))

    -- The situational modifier rides alongside the weapon bonus.
    local blow = Rules.strike(character.abilities.COMBAT,
        character:itemBonus("COMBAT") + fight.attack_mod, fight.defence)
    fight.stamina = math.max(0, fight.stamina - blow.damage)
    logLine(fight, Format.blow(_("You"), blow))

    if fight.stamina > 0 then
        local reply = Rules.strike(fight.combat, 0, character:defence() + fight.defence_mod)
        character:takeDamage(reply.damage)
        logLine(fight, Format.blow(enemyName(fight), reply))
    end

    plugin:save()
end

--- Only the enemy strikes: for the openings where the book says so.
local function enemyRound(plugin)
    local character = plugin.character
    local fight = character.fight

    local reply = Rules.strike(fight.combat, 0, character:defence() + fight.defence_mod)
    character:takeDamage(reply.damage)
    logLine(fight, Format.blow(enemyName(fight), reply))
    plugin:save()
end

local function endFight(plugin)
    plugin.character.fight = nil
    plugin:save()
end

--- The two situational modifiers, on their own screen so the setup dialog
-- stays short enough to show its buttons above the keyboard.
local function showModifiers(plugin)
    local fight = plugin.character.fight
    local back = function() showModifiers(plugin) end

    local function adjust(title, info, current, apply)
        Prompts.number{
            title = title,
            info = info,
            -- Signed: the books hand out penalties as well as bonuses.
            value = current,
            min = -10,
            max = 10,
            ok_text = _("Set"),
            callback = function(value)
                apply(value)
                plugin:save()
                back()
            end,
        }
    end

    Prompts.menu{
        title = Format.modifiers(fight),
        items = {
            {
                text = _("Adjust your attack rolls"),
                callback = function()
                    adjust(_("Attack roll modifier"),
                        _("Added to your dice when you strike."),
                        fight.attack_mod,
                        function(v) fight.attack_mod = v end)
                end,
            },
            {
                text = _("Adjust your Defence"),
                callback = function()
                    adjust(_("Defence modifier"),
                        _("Applies for this fight only; your sheet is untouched."),
                        fight.defence_mod,
                        function(v) fight.defence_mod = v end)
                end,
            },
            {
                text = _("Minimise"),
                callback = function()
                    plugin:minimise(function() showModifiers(plugin) end, "combat")
                end,
            },
            {
                text = _("Clear both"),
                callback = function()
                    fight.attack_mod, fight.defence_mod = 0, 0
                    plugin:save()
                    back()
                end,
            },
        },
        close_callback = function() Combat.show(plugin) end,
    }
end

--- The combat panel. Rebuilt after every action so the numbers stay live.
function Combat.show(plugin)
    local character = plugin.character
    local fight = character.fight
    if not fight then
        Combat.start(plugin)
        return
    end
    -- Fights saved before modifiers existed have no such fields.
    fight.attack_mod = fight.attack_mod or 0
    fight.defence_mod = fight.defence_mod or 0

    local over = fight.stamina <= 0 or character:isDead()
    local buttons = {}

    if over then
        if character:isDead() then
            -- Your own death ends the sequence regardless.
            endFight(plugin)
            table.insert(buttons, { {
                text = _("Done"),
                callback = function() plugin:showSheet() end,
            } })
        else
            table.insert(buttons, {
                {
                    text = _("Next enemy"),
                    callback = function() nextEnemy(plugin) end,
                },
                {
                    text = _("Done"),
                    callback = function()
                        endFight(plugin)
                        plugin:showSheet()
                    end,
                },
            })
        end
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
                text = _("Modifiers"),
                callback = function() showModifiers(plugin) end,
            },
            {
                text = _("Minimise"),
                callback = function()
                    plugin:minimise(function() Combat.show(plugin) end, "combat")
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
