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
Rules.MIN_RANK = 1
Rules.MAX_RANK = 10

Rules.STARTING_STAMINA = 9
Rules.STARTING_SHARDS = 16

--- Starting ability scores by profession.
--
-- You need only one book to start, and a later one starts you further along:
-- higher Rank, more Stamina, better gear, and a profession table whose scores
-- have been scaled up. The books come in pairs -- 1 and 2 share a table, as do
-- 3 and 4, and 5 and 6 -- so there are three tiers rather than six tables.
-- The initial range widens (1-6, then 1-7, then 1-8) but the hard cap on an
-- ability stays 12 throughout.
Rules.PROFESSION_TIERS = {
    { -- Books 1-2
        Mage       = { CHARISMA = 2, COMBAT = 2, MAGIC = 6, SANCTITY = 1, SCOUTING = 5, THIEVERY = 3 },
        Priest     = { CHARISMA = 4, COMBAT = 2, MAGIC = 3, SANCTITY = 6, SCOUTING = 4, THIEVERY = 2 },
        Rogue      = { CHARISMA = 5, COMBAT = 4, MAGIC = 4, SANCTITY = 1, SCOUTING = 2, THIEVERY = 6 },
        Troubadour = { CHARISMA = 6, COMBAT = 3, MAGIC = 4, SANCTITY = 3, SCOUTING = 2, THIEVERY = 4 },
        Warrior    = { CHARISMA = 3, COMBAT = 6, MAGIC = 2, SANCTITY = 4, SCOUTING = 3, THIEVERY = 2 },
        Wayfarer   = { CHARISMA = 2, COMBAT = 5, MAGIC = 2, SANCTITY = 3, SCOUTING = 6, THIEVERY = 4 },
    },
    { -- Books 3-4
        Mage       = { CHARISMA = 3, COMBAT = 3, MAGIC = 7, SANCTITY = 1, SCOUTING = 6, THIEVERY = 4 },
        Priest     = { CHARISMA = 5, COMBAT = 3, MAGIC = 4, SANCTITY = 7, SCOUTING = 5, THIEVERY = 2 },
        Rogue      = { CHARISMA = 6, COMBAT = 5, MAGIC = 5, SANCTITY = 2, SCOUTING = 3, THIEVERY = 7 },
        Troubadour = { CHARISMA = 7, COMBAT = 4, MAGIC = 5, SANCTITY = 4, SCOUTING = 3, THIEVERY = 5 },
        Warrior    = { CHARISMA = 4, COMBAT = 7, MAGIC = 2, SANCTITY = 5, SCOUTING = 4, THIEVERY = 5 },
        Wayfarer   = { CHARISMA = 3, COMBAT = 6, MAGIC = 3, SANCTITY = 4, SCOUTING = 7, THIEVERY = 5 },
    },
    { -- Books 5-6
        Mage       = { CHARISMA = 4, COMBAT = 4, MAGIC = 8, SANCTITY = 1, SCOUTING = 7, THIEVERY = 5 },
        Priest     = { CHARISMA = 6, COMBAT = 4, MAGIC = 5, SANCTITY = 8, SCOUTING = 6, THIEVERY = 2 },
        Rogue      = { CHARISMA = 7, COMBAT = 6, MAGIC = 6, SANCTITY = 2, SCOUTING = 4, THIEVERY = 8 },
        Troubadour = { CHARISMA = 8, COMBAT = 5, MAGIC = 5, SANCTITY = 5, SCOUTING = 4, THIEVERY = 6 },
        Warrior    = { CHARISMA = 5, COMBAT = 8, MAGIC = 3, SANCTITY = 6, SCOUTING = 5, THIEVERY = 3 },
        Wayfarer   = { CHARISMA = 4, COMBAT = 7, MAGIC = 4, SANCTITY = 4, SCOUTING = 8, THIEVERY = 6 },
    },
}

--- What you begin with when you start in a given book.
-- Stamina climbs by roughly the average of a die per Rank, which is what you
-- would have gained getting there the long way.
Rules.STARTING_BOOKS = {
    { rank = 1, stamina = 9,  shards = 16, tier = 1,
      kit = { { name = "sword" }, { name = "leather jerkin", defence = 1 }, { name = "map" } } },
    { rank = 2, stamina = 13, shards = 16, tier = 1,
      kit = { { name = "sword" }, { name = "leather jerkin", defence = 1 }, { name = "map" } } },
    { rank = 3, stamina = 16, shards = 40, tier = 2,
      kit = { { name = "sword" }, { name = "chain mail", defence = 3 }, { name = "map" } } },
    { rank = 4, stamina = 20, shards = 65, tier = 2,
      kit = { { name = "sword" }, { name = "chain mail", defence = 3 }, { name = "map" } } },
    { rank = 5, stamina = 23, shards = 65, tier = 3,
      kit = { { name = "sword" }, { name = "chain mail", defence = 3 } } },
    -- Book 6 starts you with nothing but what you stand up in.
    { rank = 6, stamina = 27, shards = 0,  tier = 3,
      kit = { { name = "platinum earring" } } },
}

--- The profession table in force for a given starting book (default Book 1).
function Rules.professionsFor(book)
    local entry = Rules.STARTING_BOOKS[book or 1] or Rules.STARTING_BOOKS[1]
    return Rules.PROFESSION_TIERS[entry.tier]
end

--- Book 1's table, kept as the default for callers that do not care.
Rules.PROFESSIONS = Rules.PROFESSION_TIERS[1]

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
