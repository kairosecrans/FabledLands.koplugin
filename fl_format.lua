--[[--
Renders the Adventure Sheet and roll results as text.

Kept free of KOReader dependencies so the wording can be unit-tested. Lines
are written for a monospaced face (see Prompts.monoFace) and kept under
about 40 columns so they survive a phone in portrait.

@module koplugin.FabledLands.format
--]]--

local Rules = require("fl_rules")

local Format = {}

--- Pads to a byte width. Safe here because every label we pad is ASCII.
local function pad(text, width)
    text = tostring(text)
    if #text >= width then return text end
    return text .. string.rep(" ", width - #text)
end

local function signed(n)
    return n >= 0 and ("+" .. n) or tostring(n)
end

--- "2nd Rank Commoner"
function Format.rank(character)
    return ("%s Rank %s"):format(Rules.ordinal(character.rank), character:rankTitle())
end

--- The ability block, two columns of three, marking item bonuses.
function Format.abilities(character)
    local left = { "CHARISMA", "COMBAT", "MAGIC" }
    local right = { "SANCTITY", "SCOUTING", "THIEVERY" }
    local lines = {}
    for i = 1, 3 do
        local parts = {}
        for _, ability in ipairs({ left[i], right[i] }) do
            local score = character.abilities[ability]
            local bonus = character:itemBonus(ability)
            local value = bonus > 0 and ("%d%s"):format(score, signed(bonus)) or tostring(score)
            table.insert(parts, pad(ability, 9) .. pad(value, 6))
        end
        table.insert(lines, (table.concat(parts):gsub("%s+$", "")))
    end
    return table.concat(lines, "\n")
end

-- Three-letter forms, for the cramped profession menu.
local SHORT_ABILITY = {
    CHARISMA = "CHA", COMBAT = "COM", MAGIC = "MAG",
    SANCTITY = "SAN", SCOUTING = "SCO", THIEVERY = "THI",
}

--- The whole profession table, aligned, for choosing at creation.
-- Buttons render on a single line in a proportional font, so the comparison
-- goes in the panel's monospaced title and the buttons carry only the names.
-- Shows the table belonging to the book you are starting in, since the
-- scores scale as the series goes on.
function Format.professionTable(book)
    local professions = Rules.professionsFor(book)
    local function row(label, cell)
        local line = pad(label, 11)
        for _, ability in ipairs(Rules.ABILITIES) do
            line = line .. ("%4s"):format(cell(ability))
        end
        return line
    end

    local lines = { row("", function(ability) return SHORT_ABILITY[ability] end) }
    for _, profession in ipairs(Rules.PROFESSION_NAMES) do
        local stats = professions[profession]
        table.insert(lines, row(profession, function(ability) return stats[ability] end))
    end
    return table.concat(lines, "\n")
end

--- What starting in a given book gives you, for the creation screen.
function Format.startingBook(book)
    local start = Rules.STARTING_BOOKS[book]
    if not start then return "" end
    local kit = {}
    for _i, item in ipairs(start.kit) do
        table.insert(kit, item.defence and ("%s (Defence +%d)"):format(item.name, item.defence)
            or item.name)
    end
    return ("Book %d: %s\n\n  %s Rank, Stamina %d, %d Shards\n  %s"):format(
        book, Rules.BOOK_TITLES[book] or "?", Rules.ordinal(start.rank),
        start.stamina, start.shards, table.concat(kit, ", "))
end

--- The whole sheet, as shown on the plugin's main panel.
function Format.sheet(character)
    local lines = {
        character.name ~= "" and character.name or "(unnamed)",
        ("%s, %s"):format(character.profession or "adventurer", Format.rank(character)),
        "",
        Format.abilities(character),
        "",
        pad("Stamina", 10) .. ("%d/%d"):format(character.stamina, character.stamina_max),
        pad("Defence", 10) .. character:defence(),
        pad("Money", 10) .. ("%d Shards"):format(character.shards),
        pad("Carrying", 10) .. ("%d/%d items"):format(#character.possessions, Rules.MAX_POSSESSIONS),
    }
    if #character.codewords > 0 then
        table.insert(lines, pad("Codewords", 10) .. #character.codewords)
    end
    if #character.titles > 0 then
        table.insert(lines, pad("Titles", 10) .. table.concat(character.titles, ", "))
    end
    if #character.blessings > 0 then
        local names = {}
        for _, blessing in ipairs(character.blessings) do
            table.insert(names, blessing.name)
        end
        table.insert(lines, pad("Blessings", 10) .. table.concat(names, ", "))
    end
    if character.god then
        table.insert(lines, pad("God", 10) .. character.god)
    end
    if character.ship then
        table.insert(lines, pad("Ship", 10) .. Format.ship(character.ship))
    end
    if character:isDead() then
        table.insert(lines, "")
        table.insert(lines, "*** DEAD -- Stamina has reached zero ***")
        -- The one moment the arrangement is needed, so it goes here rather
        -- than two screens away.
        table.insert(lines, Format.resurrection(character))
    end
    if character.notes and character.notes ~= "" then
        table.insert(lines, "")
        table.insert(lines, character.notes)
    end
    return table.concat(lines, "\n")
end

function Format.ship(ship)
    local parts = { ship.name and ship.name ~= "" and ship.name or ship.type or "ship" }
    if ship.type then table.insert(parts, ship.type) end
    if ship.crew then table.insert(parts, ship.crew .. " crew") end
    local capacity = tonumber(ship.capacity)
    if capacity then
        table.insert(parts, ("cargo %d/%d"):format(#(ship.cargo or {}), capacity))
    end
    if ship.docked and ship.docked ~= "" then table.insert(parts, "at " .. ship.docked) end
    return table.concat(parts, ", ")
end

--- The result of an ability check.
-- Spells out the number that was needed, because the rule that you must beat
-- the Difficulty outright is the one people get wrong.
function Format.check(ability, result)
    local needed = result.difficulty + 1
    local lines = {
        ("%s roll, Difficulty %d"):format(ability, result.difficulty),
        "",
        ("  %s%d + %d = %d"):format(pad("Dice", 12), result.dice[1], result.dice[2], result.dice_total),
        ("  %s%s"):format(pad(ability, 12), signed(result.score)),
    }
    if result.bonus > 0 then
        table.insert(lines, ("  %s%s"):format(pad("Item bonus", 12), signed(result.bonus)))
    end
    table.insert(lines, ("  %s%d"):format(pad("Total", 12), result.total))
    table.insert(lines, "")
    table.insert(lines, result.success
        and ("SUCCESS -- needed %d, got %d"):format(needed, result.total)
        or ("FAILED -- needed %d, got %d"):format(needed, result.total))
    return table.concat(lines, "\n")
end

--- One blow, as a single compact log line.
-- e.g. "  You    (4+4)+6=14 vs 7 -> 7"
-- The name is clipped to keep the columns aligned; enemies in these books can
-- be called things like "Ravening Beast of Xane".
function Format.blow(who, result)
    local bonus = result.combat + result.bonus
    local outcome = result.hit and ("-> %d"):format(result.damage) or "-> miss"
    return ("  %s(%d+%d)+%d=%d vs %d %s"):format(
        pad(tostring(who):sub(1, 7), 8), result.dice[1], result.dice[2], bonus,
        result.total, result.defence, outcome)
end

--- What happens now you are dead, if anything was arranged.
function Format.resurrection(character)
    local deals = character.resurrection or {}
    if #deals == 0 then
        return "No resurrection arranged."
    end
    local lines = { "Resurrection arranged:" }
    for _i, deal in ipairs(deals) do
        table.insert(lines, deal.section
            and ("  %s -- turn to %d"):format(deal.where, deal.section)
            or ("  %s"):format(deal.where))
    end
    return table.concat(lines, "\n")
end

--- The result of a roll made for the ship.
function Format.shipRoll(result)
    local lines = {
        ("Ship roll: %s, %s crew"):format(result.ship_type, result.crew or "average"),
        "",
        ("  %s%s = %d"):format(pad("Dice", 12), table.concat(result.dice, " + "), result.dice_total),
    }
    if result.bonus > 0 then
        table.insert(lines, ("  %s%s"):format(pad("Crew", 12), signed(result.bonus)))
    end
    table.insert(lines, ("  %s%d"):format(pad("Total", 12), result.total))
    return table.concat(lines, "\n")
end

--- The dice roller: your numbers for the mental math, then the last roll.
-- The books ask for dice in many shapes (add your Rank, beat your Rank, a
-- Warrior rolls three), so the roller shows the parts rather than guessing
-- the sum.
-- @tparam table roll { dice = {..}, total = n }, or nil before the first roll
local DICE_WORDS = { "One die", "Two dice", "Three dice", "Four dice" }

function Format.diceRoller(character, roll)
    local lines = {
        ("Rank %d     Defence %d     Stamina %d/%d"):format(character.rank,
            character:defence(), character.stamina, character.stamina_max),
        "",
        Format.abilities(character),
        "",
    }
    if not roll then
        table.insert(lines, "How many dice?")
    else
        local label = pad(DICE_WORDS[#roll.dice] or ("%d dice"):format(#roll.dice), 13)
        if #roll.dice == 1 then
            table.insert(lines, label .. roll.total)
        else
            table.insert(lines, ("%s%s = %d"):format(label, table.concat(roll.dice, " + "), roll.total))
        end
    end
    return table.concat(lines, "\n")
end

--- Describes the situational modifiers in force, for the modifiers screen.
function Format.modifiers(fight)
    local attack = fight.attack_mod or 0
    local defence = fight.defence_mod or 0
    if attack == 0 and defence == 0 then
        return "No modifiers in force.\n\nUse these when the book adjusts a\nfight, such as a bonus for carrying a\nparticular item."
    end
    local lines = { "For this fight only:" }
    if attack ~= 0 then
        table.insert(lines, ("  attack rolls  %s"):format(signed(attack)))
    end
    if defence ~= 0 then
        table.insert(lines, ("  your Defence  %s"):format(signed(defence)))
    end
    return table.concat(lines, "\n")
end

--- A short label for the minimized badge: enough to see the fight's state at
-- a glance without opening it.
function Format.badge(character, fight)
    if fight then
        local who = fight.name ~= "" and fight.name:sub(1, 10) or "Enemy"
        return ("%s %d/%d  You %d/%d"):format(
            who, fight.stamina, fight.stamina_max, character.stamina, character.stamina_max)
    end
    return ("%s  %d/%d"):format(
        character.name ~= "" and character.name:sub(1, 12) or "Sheet",
        character.stamina, character.stamina_max)
end

--- The combat panel: both combatants' state, then the round log.
function Format.fight(character, fight)
    local attack_mod = fight.attack_mod or 0
    local defence_mod = fight.defence_mod or 0
    local lines = {
        fight.name ~= "" and fight.name or "The enemy",
        ("  COMBAT %d   Defence %d   Stamina %d/%d")
            :format(fight.combat, fight.defence, fight.stamina, fight.stamina_max),
        "",
        "You",
        ("  COMBAT %d   Defence %d   Stamina %d/%d")
            :format(character.abilities.COMBAT, character:defence() + defence_mod,
                character.stamina, character.stamina_max),
    }
    -- Spell the modifiers out, so a surprising number on the sheet is
    -- traceable to the rule that caused it.
    if attack_mod ~= 0 or defence_mod ~= 0 then
        local parts = {}
        if attack_mod ~= 0 then table.insert(parts, ("attack %s"):format(signed(attack_mod))) end
        if defence_mod ~= 0 then table.insert(parts, ("Defence %s"):format(signed(defence_mod))) end
        table.insert(lines, ("  this fight: %s"):format(table.concat(parts, ", ")))
    end
    if #fight.log > 0 then
        table.insert(lines, "")
        for _, entry in ipairs(fight.log) do
            table.insert(lines, entry)
        end
    end
    if fight.stamina <= 0 then
        table.insert(lines, "")
        table.insert(lines, "*** " .. (fight.name ~= "" and fight.name or "The enemy") .. " is defeated ***")
    elseif character:isDead() then
        table.insert(lines, "")
        table.insert(lines, "*** You are dead ***")
    end
    return table.concat(lines, "\n")
end

return Format
