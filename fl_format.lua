--[[--
Renders the Adventure Sheet and roll results as text.

Kept free of KOReader dependencies so the wording can be unit-tested. Lines
are written for a monospaced face (see Prompts.MONO_FACE) and kept under
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
function Format.professionTable()
    local function row(label, cell)
        local line = pad(label, 11)
        for _, ability in ipairs(Rules.ABILITIES) do
            line = line .. ("%4s"):format(cell(ability))
        end
        return line
    end

    local lines = { row("", function(ability) return SHORT_ABILITY[ability] end) }
    for _, profession in ipairs(Rules.PROFESSION_NAMES) do
        local stats = Rules.PROFESSIONS[profession]
        table.insert(lines, row(profession, function(ability) return stats[ability] end))
    end
    return table.concat(lines, "\n")
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
    if character.ship then
        table.insert(lines, pad("Ship", 10) .. Format.ship(character.ship))
    end
    if character:isDead() then
        table.insert(lines, "")
        table.insert(lines, "*** DEAD -- Stamina has reached zero ***")
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

--- The combat panel: both combatants' state, then the round log.
function Format.fight(character, fight)
    local lines = {
        fight.name ~= "" and fight.name or "The enemy",
        ("  COMBAT %d   Defence %d   Stamina %d/%d")
            :format(fight.combat, fight.defence, fight.stamina, fight.stamina_max),
        "",
        "You",
        ("  COMBAT %d   Defence %d   Stamina %d/%d")
            :format(character.abilities.COMBAT, character:defence(), character.stamina, character.stamina_max),
    }
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
