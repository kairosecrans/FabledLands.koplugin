--[[--
Tests for the text the plugin puts on screen.

These assert on meaning, not on exact layout, so cosmetic tweaks to spacing
do not break the suite. The one thing pinned down hard is the wording of a
check result, because "needed N" is what tells you the roll had to beat the
Difficulty rather than match it.

    luajit spec/format_spec.lua
--]]--

package.path = "?.lua;" .. package.path
local Character = require("fl_character")
local Format = require("fl_format")
local Rules = require("fl_rules")

local failures, checks = 0, 0

local function check(ok, label, detail)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        io.write(("FAIL  %s%s\n"):format(label, detail and ("  -- " .. detail) or ""))
    end
end

local function eq(got, want, label)
    check(got == want, label, ("expected %s, got %s"):format(tostring(want), tostring(got)))
end

local function contains(haystack, needle, label)
    check(haystack:find(needle, 1, true) ~= nil, label,
        ("%q not found in:\n%s"):format(needle, haystack))
end

local function lacks(haystack, needle, label)
    check(haystack:find(needle, 1, true) == nil, label, ("%q unexpectedly present"):format(needle))
end

local function scripted(...)
    local queue, i = { ... }, 0
    return function()
        i = i + 1
        assert(queue[i], "scripted rng ran out of values")
        return queue[i]
    end
end

-- The sheet ----------------------------------------------------------------
do
    local hero = Character.create("Andriel the Hammer", "Warrior")
    local sheet = Format.sheet(hero)

    contains(sheet, "Andriel the Hammer", "name shown")
    contains(sheet, "Warrior", "profession shown")
    contains(sheet, "1st Rank Outcast", "rank and title shown")
    contains(sheet, "COMBAT", "abilities shown")
    contains(sheet, "9/9", "Stamina shown as current over max")
    contains(sheet, "16 Shards", "money shown")
    contains(sheet, "3/12 items", "carry count shown")
    lacks(sheet, "Codewords", "no codeword line when none held")
    lacks(sheet, "DEAD", "living character is not marked dead")

    -- Defence appears as a computed number, not the formula.
    contains(sheet, "Defence", "Defence labelled")
    contains(sheet, tostring(hero:defence()), "Defence value shown")
end

-- Optional lines appear only once there is something to show.
do
    local hero = Character.create("Wanderer", "Rogue")
    hero:addCodeword("Aid")
    hero:addBlessing({ name = "Safety from Storms" })
    table.insert(hero.titles, "Illuminate of Molhern")
    hero.ship = { name = "Sea Dog", type = "brigantine", crew = "good", docked = "Yellowport" }
    hero.notes = "Went north from 274."

    local sheet = Format.sheet(hero)
    contains(sheet, "Codewords", "codeword count shown once held")
    contains(sheet, "Illuminate of Molhern", "titles shown")
    contains(sheet, "Safety from Storms", "blessings shown")
    contains(sheet, "Sea Dog", "ship shown")
    contains(sheet, "brigantine", "ship type shown")
    contains(sheet, "Yellowport", "where docked shown")
    contains(sheet, "Went north from 274.", "notes shown")
end

-- A dead character says so plainly.
do
    local hero = Character.create("Doomed", "Mage")
    hero:takeDamage(99)
    contains(Format.sheet(hero), "DEAD", "death is called out")
end

-- An item bonus is shown against the ability it helps.
do
    local hero = Character.create("Tooled", "Rogue")
    hero:addPossession({ name = "magic lockpicks", ability = "THIEVERY", bonus = 2 })
    local abilities = Format.abilities(hero)
    contains(abilities, "6+2", "THIEVERY 6 with a +2 item")
    contains(abilities, "CHARISMA", "unbonused abilities still listed")
end

-- A character with no name still renders.
do
    local hero = Character.create("", "Mage")
    contains(Format.sheet(hero), "(unnamed)", "blank name has a placeholder")
end

-- Check results ------------------------------------------------------------
-- The Difficulty must be beaten outright, so "needed" is always Difficulty+1.
do
    local hero = Character.create("Scout", "Wayfarer") -- SCOUTING 6

    -- 2d6 = 4, +6 = 10, against Difficulty 9 -> success by the skin of it.
    local pass = hero:check("SCOUTING", 9, scripted(2, 2))
    local text = Format.check("SCOUTING", pass)
    contains(text, "SCOUTING roll, Difficulty 9", "heading names ability and Difficulty")
    contains(text, "2 + 2 = 4", "individual dice shown")
    contains(text, "SUCCESS", "success announced")
    contains(text, "needed 10, got 10", "needed is one above the Difficulty")

    -- 2d6 = 3, +6 = 9, against Difficulty 9 -> equalling it is a failure.
    local fail = hero:check("SCOUTING", 9, scripted(1, 2))
    local fail_text = Format.check("SCOUTING", fail)
    contains(fail_text, "FAILED", "failure announced")
    contains(fail_text, "needed 10, got 9", "equalling the Difficulty reads as a failure")
end

-- The item bonus gets its own line, but only when there is one.
do
    local hero = Character.create("Tooled", "Rogue")
    local bare = Format.check("THIEVERY", hero:check("THIEVERY", 9, scripted(3, 3)))
    lacks(bare, "Item bonus", "no bonus line without gear")

    hero:addPossession({ name = "magic lockpicks", ability = "THIEVERY", bonus = 2 })
    local geared = Format.check("THIEVERY", hero:check("THIEVERY", 9, scripted(3, 3)))
    contains(geared, "Item bonus", "bonus line appears with gear")
    contains(geared, "+2", "bonus amount shown")
end

-- Blows --------------------------------------------------------------------
do
    local hit = Rules.strike(6, 0, 7, scripted(5, 3))
    local line = Format.blow("You", hit)
    contains(line, "You", "who struck")
    contains(line, "(5+3)+6=14", "the arithmetic is shown")
    contains(line, "vs 7", "target Defence shown")
    contains(line, "-> 7", "damage shown")

    local miss = Rules.strike(2, 0, 20, scripted(1, 1))
    contains(Format.blow("Goblin", miss), "miss", "a miss says so")

    -- Long names are clipped so the columns stay aligned.
    local long = Format.blow("Ravening Beast of Xane", hit)
    check(#long == #line, "long names do not widen the line",
        ("%d vs %d"):format(#long, #line))
end

-- The combat panel ---------------------------------------------------------
do
    local hero = Character.create("Fighter", "Warrior")
    local fight = {
        name = "Goblin", combat = 5, defence = 7, stamina = 6, stamina_max = 6,
        round = 0, log = {},
    }
    local panel = Format.fight(hero, fight)
    contains(panel, "Goblin", "enemy named")
    contains(panel, "COMBAT 5", "enemy COMBAT shown")
    contains(panel, "Defence 7", "enemy Defence shown")
    contains(panel, "6/6", "enemy Stamina shown")
    contains(panel, "You", "your own block shown")
    contains(panel, "9/9", "your Stamina shown")

    fight.stamina = 0
    contains(Format.fight(hero, fight), "defeated", "a dead enemy is called out")

    fight.stamina = 3
    hero:takeDamage(99)
    contains(Format.fight(hero, fight), "You are dead", "your own death is called out")
end

-- An unnamed enemy still reads sensibly.
do
    local hero = Character.create("Fighter", "Warrior")
    local fight = { name = "", combat = 3, defence = 5, stamina = 4, stamina_max = 4, round = 0, log = {} }
    contains(Format.fight(hero, fight), "The enemy", "unnamed enemy gets a placeholder")
end

-- The profession table -----------------------------------------------------
do
    local table_text = Format.professionTable()
    local lines = {}
    for line in table_text:gmatch("[^\n]+") do table.insert(lines, line) end

    eq(#lines, 7, "a header plus six professions")
    contains(lines[1], "CHA", "header names the abilities")
    contains(lines[1], "THI", "header runs to THIEVERY")

    for index, profession in ipairs(Rules.PROFESSION_NAMES) do
        contains(lines[index + 1], profession, profession .. " has a row")
    end

    -- Every row must be the same width, or the columns will not line up under
    -- the header in the monospaced panel title.
    for index, line in ipairs(lines) do
        eq(#line, #lines[1], ("row %d matches the header width"):format(index))
    end

    -- The table must stay narrow enough for a phone in portrait.
    check(#lines[1] <= 40, "table fits in 40 columns", ("%d columns"):format(#lines[1]))

    -- Spot-check that the numbers land in the right columns.
    local warrior = lines[6]
    contains(warrior, "Warrior", "warrior row")
    eq(warrior:match("Warrior%s+(%d+)"), "3", "warrior CHARISMA is first")
end

-- Rank ---------------------------------------------------------------------
do
    local hero = Character.create("Rising", "Warrior")
    eq(Format.rank(hero), "1st Rank Outcast", "rank line at the start")
    hero:rankUp(scripted(3))
    eq(Format.rank(hero), "2nd Rank Commoner", "rank line after advancing")
end

-- Situational modifiers ----------------------------------------------------
-- The books hand out penalties as well as bonuses, so these must be signed.
do
    local hero = Character.create("Fighter", "Warrior")
    local fight = {
        name = "Goblin", combat = 5, defence = 7, stamina = 6, stamina_max = 6,
        round = 0, log = {}, attack_mod = 0, defence_mod = 0,
    }

    contains(Format.modifiers(fight), "No modifiers", "says so when none are set")

    fight.attack_mod = 3
    local text = Format.modifiers(fight)
    contains(text, "attack rolls", "attack modifier labelled")
    contains(text, "+3", "bonus is signed")
    lacks(text, "your Defence", "unset Defence modifier is not listed")

    fight.defence_mod = -1
    local both = Format.modifiers(fight)
    contains(both, "+3", "bonus still shown")
    contains(both, "-1", "penalty shown as negative")

    -- The panel shows them, and the Defence modifier moves the displayed
    -- Defence without touching the sheet.
    local panel = Format.fight(hero, fight)
    contains(panel, "this fight", "panel calls out the modifiers")
    contains(panel, "attack +3", "panel shows the attack modifier")
    contains(panel, "Defence -1", "panel shows the Defence modifier")
    eq(hero:defence(), 8, "the sheet Defence is untouched")
    contains(panel, "Defence 7 ", "displayed Defence is 8 - 1 = 7")

    -- A fight saved before modifiers existed must still render.
    local legacy = {
        name = "Old", combat = 3, defence = 5, stamina = 4, stamina_max = 4,
        round = 0, log = {},
    }
    contains(Format.fight(hero, legacy), "Old", "legacy fight renders")
    lacks(Format.fight(hero, legacy), "this fight", "legacy fight shows no modifier line")
    contains(Format.modifiers(legacy), "No modifiers", "legacy fight has no modifiers")
end

-- The minimised badge ------------------------------------------------------
do
    local hero = Character.create("Marana", "Rogue")
    hero:takeDamage(3)

    local sheet_badge = Format.badge(hero, nil)
    contains(sheet_badge, "Marana", "badge names the character")
    contains(sheet_badge, "6/9", "badge shows Stamina")

    local fight = { name = "Goblin", combat = 5, defence = 7, stamina = 2, stamina_max = 6 }
    local fight_badge = Format.badge(hero, fight)
    contains(fight_badge, "Goblin", "badge names the enemy")
    contains(fight_badge, "2/6", "badge shows enemy Stamina")
    contains(fight_badge, "6/9", "badge shows your Stamina")

    -- Long names must not make the badge sprawl across the page. The cap is
    -- on the badge as a whole, not on the difference between two names.
    local long = Format.badge(hero, { name = "Ravening Beast of Xane",
        combat = 5, defence = 7, stamina = 2, stamina_max = 6 })
    lacks(long, "Ravening Beast", "the full long name is not shown")
    check(#long <= 32, "badge stays narrow", ("%d chars"):format(#long))
end

-- Dice roller -------------------------------------------------------------
do
    local Character = require("fl_character")
    local hero = Character.create("Marana", "Rogue")
    hero:addPossession({ name = "lockpicks", ability = "THIEVERY", bonus = 2 })

    local fresh = Format.diceRoller(hero)
    contains(fresh, "Rank 1     Defence 6     Stamina 9/9", "stats line for the mental math")
    contains(fresh, "THIEVERY 6+2", "abilities shown with gear bonuses")
    contains(fresh, "How many dice?", "prompt before the first roll")

    local dice, total = Rules.rollDice(3, scripted(4, 6, 2))
    local three = Format.diceRoller(hero, { dice = dice, total = total })
    contains(three, "Three dice   4 + 6 + 2 = 12", "three dice show each die and the total")
    lacks(three, "How many dice?", "the prompt gives way to the result")
    contains(Format.diceRoller(hero, { dice = { 5 }, total = 5 }), "One die      5", "one die shows just the number")
    contains(Format.diceRoller(hero, { dice = { 1, 2, 3, 4 }, total = 10 }), "Four dice    1 + 2 + 3 + 4 = 10", "four dice")
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
