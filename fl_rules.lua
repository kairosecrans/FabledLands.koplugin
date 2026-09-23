--[[--
The Fabled Lands rules engine.

Deliberately free of any KOReader dependency so it can be unit-tested with a
bare Lua interpreter (see spec/rules_spec.lua).

Rule references are to Book 1, "The War-Torn Kingdom", pp. 5-7:

* An ability check is 2d6 + ability score, and must come out *strictly
  greater* than the Difficulty to succeed.
* Defence = COMBAT + Rank + the bonus of the best armour carried.
* A blow is 2d6 + COMBAT against the target's Defence; the amount by which
  the roll exceeds the Defence is the Stamina lost. There is no separate
  damage roll.
* Item bonuses are not cumulative -- only the best item counts per ability.

@module koplugin.FabledLands.rules
--]]--

local Rules = {}

Rules.ABILITIES = { "CHARISMA", "COMBAT", "MAGIC", "SANCTITY", "SCOUTING", "THIEVERY" }

Rules.ABILITY_MIN = 1
Rules.ABILITY_MAX = 12
Rules.MAX_POSSESSIONS = 12
Rules.MAX_RANK = 10

Rules.STARTING_STAMINA = 9
Rules.STARTING_SHARDS = 16

-- Starting ability scores by profession (p. 5).
Rules.PROFESSIONS = {
    Mage       = { CHARISMA = 2, COMBAT = 2, MAGIC = 6, SANCTITY = 1, SCOUTING = 5, THIEVERY = 3 },
    Priest     = { CHARISMA = 4, COMBAT = 2, MAGIC = 3, SANCTITY = 6, SCOUTING = 4, THIEVERY = 2 },
    Rogue      = { CHARISMA = 5, COMBAT = 4, MAGIC = 4, SANCTITY = 1, SCOUTING = 2, THIEVERY = 6 },
    Troubadour = { CHARISMA = 6, COMBAT = 3, MAGIC = 4, SANCTITY = 3, SCOUTING = 2, THIEVERY = 4 },
    Warrior    = { CHARISMA = 3, COMBAT = 6, MAGIC = 2, SANCTITY = 4, SCOUTING = 3, THIEVERY = 2 },
    Wayfarer   = { CHARISMA = 2, COMBAT = 5, MAGIC = 2, SANCTITY = 3, SCOUTING = 6, THIEVERY = 4 },
}

-- Ordered for menus; the table above is keyed, so it has no stable order.
Rules.PROFESSION_NAMES = { "Mage", "Priest", "Rogue", "Troubadour", "Warrior", "Wayfarer" }

Rules.RANK_TITLES = {
    "Outcast", "Commoner", "Guildmember", "Master/Mistress", "Gentleman/Lady",
    "Baron/Baroness", "Count/Countess", "Earl/Viscountess", "Marquis/Marchioness", "Duke/Duchess",
}

-- Codewords are lettered by the book they come from, which is how you know
-- where to look one up (p. 7).
Rules.BOOK_TITLES = {
    "The War-Torn Kingdom",
    "Cities of Gold and Glory",
    "Over the Blood-Dark Sea",
    "The Plains of Howling Darkness",
    "The Court of Hidden Faces",
    "Lords of the Rising Sun",
    "The Serpent King's Domain",
}

Rules.SHIP_TYPES = { "barque", "brigantine", "galleon" }
Rules.CREW_QUALITY = { "poor", "average", "good", "excellent" }

--- Rolls n six-sided dice.
-- @int n how many dice
-- @func rng optional; must behave like math.random(a, b). Injected by tests.
-- @treturn table the individual die results
-- @treturn int their sum
function Rules.rollDice(n, rng)
    rng = rng or math.random
    local dice, sum = {}, 0
    for i = 1, n do
        dice[i] = rng(1, 6)
        sum = sum + dice[i]
    end
    return dice, sum
end

--- Makes an ability check: 2d6 + score + bonus, beating the Difficulty outright.
-- @treturn table a result record suitable for formatting
function Rules.abilityCheck(score, bonus, difficulty, rng)
    bonus = bonus or 0
    local dice, dice_total = Rules.rollDice(2, rng)
    local total = dice_total + score + bonus
    return {
        dice = dice,
        dice_total = dice_total,
        score = score,
        bonus = bonus,
        total = total,
        difficulty = difficulty,
        success = total > difficulty,
    }
end

--- Defence = COMBAT + Rank + best armour bonus (p. 6).
function Rules.defence(combat, rank, armour_bonus)
    return combat + rank + (armour_bonus or 0)
end

--- Resolves one blow. Damage is the margin by which the roll beats Defence.
-- Used for both sides of a fight: the attacker's COMBAT against the
-- defender's Defence.
function Rules.strike(combat, bonus, target_defence, rng)
    bonus = bonus or 0
    local dice, dice_total = Rules.rollDice(2, rng)
    local total = dice_total + combat + bonus
    local damage = total > target_defence and total - target_defence or 0
    return {
        dice = dice,
        dice_total = dice_total,
        combat = combat,
        bonus = bonus,
        total = total,
        defence = target_defence,
        damage = damage,
        hit = damage > 0,
    }
end

--- Rolls the permanent Stamina gain that comes with a new Rank (1d6).
function Rules.rankUpStamina(rng)
    local _, gain = Rules.rollDice(1, rng)
    return gain
end

--- Returns the best bonus any carried item gives to an ability.
-- Bonuses do not stack: only the single best item counts (p. 7).
function Rules.bestBonus(possessions, ability)
    local best = 0
    for _, item in ipairs(possessions or {}) do
        if item.ability == ability and (item.bonus or 0) > best then
            best = item.bonus
        end
    end
    return best
end

--- Returns the bonus of the best armour carried. You may own several suits but
-- wear only one, so only the best counts (p. 6).
function Rules.bestArmour(possessions)
    local best = 0
    for _, item in ipairs(possessions or {}) do
        if (item.defence or 0) > best then
            best = item.defence
        end
    end
    return best
end

function Rules.clampAbility(value)
    return math.max(Rules.ABILITY_MIN, math.min(Rules.ABILITY_MAX, value))
end

function Rules.rankTitle(rank)
    return Rules.RANK_TITLES[rank] or Rules.RANK_TITLES[#Rules.RANK_TITLES]
end

--- "1st", "2nd", "3rd", "4th"...
function Rules.ordinal(n)
    local suffix = "th"
    local tens, units = n % 100, n % 10
    if tens < 11 or tens > 13 then
        if units == 1 then
            suffix = "st"
        elseif units == 2 then
            suffix = "nd"
        elseif units == 3 then
            suffix = "rd"
        end
    end
    return n .. suffix
end

--- Maps a codeword to the book it came from via its initial letter.
-- @treturn int|nil book number, or nil if the word does not start with a letter
-- @treturn string|nil that book's title
function Rules.codewordBook(word)
    local letter = tostring(word):sub(1, 1):upper()
    if not letter:match("%a") then return nil, nil end
    local index = letter:byte() - ("A"):byte() + 1
    return index, Rules.BOOK_TITLES[index]
end

return Rules
