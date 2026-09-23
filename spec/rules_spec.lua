--[[--
Unit tests for the Fabled Lands rules engine.

Runs under any Lua 5.1+ interpreter, including the LuaJIT bundled with
KOReader -- no KOReader modules are loaded. From the repository root:

    luajit spec/rules_spec.lua

The worked examples are taken verbatim from Book 1, pp. 5-6, so a failure
here means the plugin disagrees with the printed rules.
--]]--

package.path = "?.lua;" .. package.path
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

--- An rng that hands back a scripted sequence, so rolls are deterministic.
local function scripted(...)
    local queue, i = { ... }, 0
    return function()
        i = i + 1
        assert(queue[i], "scripted rng ran out of values")
        return queue[i]
    end
end

-- Ability checks -----------------------------------------------------------
-- Book example (p. 5): with CHARISMA 6 against Difficulty 10 the dice must
-- total 5 or more. So 2d6=4 fails and 2d6=5 passes; equalling the Difficulty
-- is NOT a success.
do
    local fail = Rules.abilityCheck(6, 0, 10, scripted(2, 2))
    eq(fail.total, 10, "charisma 2d6=4 total")
    eq(fail.success, false, "equalling the Difficulty must fail")

    local pass = Rules.abilityCheck(6, 0, 10, scripted(2, 3))
    eq(pass.total, 11, "charisma 2d6=5 total")
    eq(pass.success, true, "beating the Difficulty by 1 must succeed")
end

-- Book example (p. 7): with THIEVERY 4 against a Difficulty 9 climb, the dice
-- must total at least 6.
do
    local fail = Rules.abilityCheck(4, 0, 9, scripted(2, 3))
    eq(fail.success, false, "thievery 2d6=5 vs difficulty 9 fails")
    local pass = Rules.abilityCheck(4, 0, 9, scripted(3, 3))
    eq(pass.success, true, "thievery 2d6=6 vs difficulty 9 succeeds")
end

-- An item bonus is added on top of the ability score.
do
    local result = Rules.abilityCheck(4, 2, 9, scripted(2, 2))
    eq(result.total, 10, "score 4 + bonus 2 + 2d6=4")
    eq(result.success, true, "bonus carries the roll over the Difficulty")
end

-- Defence ------------------------------------------------------------------
-- Book example (p. 6): COMBAT 4, 3rd Rank, chain mail tabard (+2) -> Defence 9.
eq(Rules.defence(4, 3, 2), 9, "defence = combat + rank + armour")
-- A starting character: COMBAT plus 2, being 1st Rank with a +1 jerkin.
eq(Rules.defence(6, 1, 1), 8, "starting warrior defence")
eq(Rules.defence(5, 1, 0), 6, "defence with no armour")

-- Fighting -----------------------------------------------------------------
-- Book example (p. 6) in full: a 3rd Rank character with COMBAT 4 fights a
-- goblin (COMBAT 5, Defence 7, Stamina 6).
do
    -- Your blow: 2d6 = 8, plus COMBAT 4, is 12 against the goblin's Defence
    -- of 7, so it loses 5 Stamina.
    local blow = Rules.strike(4, 0, 7, scripted(5, 3))
    eq(blow.total, 12, "player attack total")
    eq(blow.damage, 5, "player damage is the margin over Defence")
    eq(blow.hit, true, "player hits")

    -- Its reply: 2d6 = 6, plus its COMBAT 5, is 11 against your Defence of 9
    -- (COMBAT 4 + Rank 3 + a +2 tabard), so you lose 2 Stamina.
    local reply = Rules.strike(5, 0, 9, scripted(4, 2))
    eq(reply.total, 11, "goblin attack total")
    eq(reply.damage, 2, "goblin damage is the margin over Defence")
end

-- Matching the Defence exactly is a miss, not a graze.
do
    local blow = Rules.strike(4, 0, 12, scripted(4, 4))
    eq(blow.total, 12, "blow equalling Defence")
    eq(blow.damage, 0, "equalling Defence deals no damage")
    eq(blow.hit, false, "equalling Defence is not a hit")
end

-- Falling short deals no damage, and never negative damage.
do
    local blow = Rules.strike(2, 0, 20, scripted(1, 1))
    eq(blow.damage, 0, "a hopeless roll deals zero, not negative")
end

-- A weapon bonus adds to the attack roll.
do
    local blow = Rules.strike(4, 1, 7, scripted(5, 3))
    eq(blow.damage, 6, "trident (COMBAT +1) adds one damage")
end

-- Non-cumulative item bonuses ---------------------------------------------
-- Book (p. 7): lockpicks (THIEVERY +1) plus magic lockpicks (THIEVERY +2)
-- gives +2, not +3.
do
    local pack = {
        { name = "lockpicks", ability = "THIEVERY", bonus = 1 },
        { name = "magic lockpicks", ability = "THIEVERY", bonus = 2 },
        { name = "mandolin", ability = "CHARISMA", bonus = 1 },
        { name = "leather jerkin", defence = 1 },
        { name = "chain mail tabard", defence = 2 },
    }
    eq(Rules.bestBonus(pack, "THIEVERY"), 2, "best thievery item only")
    eq(Rules.bestBonus(pack, "CHARISMA"), 1, "single charisma item")
    eq(Rules.bestBonus(pack, "COMBAT"), 0, "no combat item")
    eq(Rules.bestArmour(pack), 2, "only the best armour is worn")
    eq(Rules.bestBonus({}, "COMBAT"), 0, "empty pack")
    eq(Rules.bestArmour(nil), 0, "nil pack")
end

-- Ability limits (p. 7): never above 12, never below 1.
eq(Rules.clampAbility(13), 12, "abilities cap at 12")
eq(Rules.clampAbility(0), 1, "abilities floor at 1")
eq(Rules.clampAbility(7), 7, "abilities in range are untouched")

-- Rank ---------------------------------------------------------------------
eq(Rules.rankTitle(1), "Outcast", "1st Rank title")
eq(Rules.rankTitle(10), "Duke/Duchess", "10th Rank title")
eq(Rules.rankTitle(11), "Duke/Duchess", "beyond the table, clamp to the last title")
eq(Rules.ordinal(1), "1st", "ordinal 1")
eq(Rules.ordinal(2), "2nd", "ordinal 2")
eq(Rules.ordinal(3), "3rd", "ordinal 3")
eq(Rules.ordinal(4), "4th", "ordinal 4")
eq(Rules.ordinal(11), "11th", "ordinal 11 is not 11st")
eq(Rules.ordinal(12), "12th", "ordinal 12 is not 12nd")
eq(Rules.ordinal(13), "13th", "ordinal 13 is not 13rd")
eq(Rules.ordinal(21), "21st", "ordinal 21")

-- Rank-up Stamina is a single die.
eq(Rules.rankUpStamina(scripted(4)), 4, "rank-up gain is one die")
do
    local lo, hi = 99, 0
    for _ = 1, 500 do
        local gain = Rules.rankUpStamina()
        lo, hi = math.min(lo, gain), math.max(hi, gain)
    end
    check(lo >= 1 and hi <= 6, "rank-up gain stays within 1-6", ("saw %d..%d"):format(lo, hi))
end

-- Professions --------------------------------------------------------------
do
    -- The professions are NOT balanced against a common points budget -- the
    -- printed totals really do range from 19 to 22. These are transcription
    -- guards against typos in the table, not a rule.
    local printed_totals = {
        Mage = 19, Priest = 21, Rogue = 22,
        Troubadour = 22, Warrior = 20, Wayfarer = 22,
    }
    eq(#Rules.PROFESSION_NAMES, 6, "six professions")
    for _, name in ipairs(Rules.PROFESSION_NAMES) do
        local stats = Rules.PROFESSIONS[name]
        check(stats ~= nil, "profession " .. name .. " has stats")
        local total = 0
        for _, ability in ipairs(Rules.ABILITIES) do
            check(stats[ability] ~= nil, name .. " has " .. ability)
            local score = stats[ability] or 0
            check(score >= Rules.ABILITY_MIN and score <= Rules.ABILITY_MAX,
                name .. " " .. ability .. " is in range")
            total = total + score
        end
        eq(total, printed_totals[name], name .. " ability total")
    end
    -- Spot-check against the printed table (p. 5).
    eq(Rules.PROFESSIONS.Warrior.COMBAT, 6, "warrior combat")
    eq(Rules.PROFESSIONS.Mage.MAGIC, 6, "mage magic")
    eq(Rules.PROFESSIONS.Priest.SANCTITY, 6, "priest sanctity")
    eq(Rules.PROFESSIONS.Rogue.THIEVERY, 6, "rogue thievery")
    eq(Rules.PROFESSIONS.Troubadour.CHARISMA, 6, "troubadour charisma")
    eq(Rules.PROFESSIONS.Wayfarer.SCOUTING, 6, "wayfarer scouting")
end

-- The pre-generated characters on the inside cover must fall out of the rules.
-- Andriel the Hammer: Warrior, 1st Rank, leather jerkin (+1), Defence 8.
eq(Rules.defence(Rules.PROFESSIONS.Warrior.COMBAT, 1, 1), 8, "Andriel's Defence")
-- Liana the Swift: Wayfarer, 1st Rank, leather jerkin (+1), Defence 7.
eq(Rules.defence(Rules.PROFESSIONS.Wayfarer.COMBAT, 1, 1), 7, "Liana's Defence")
-- Chalor the Exiled One: Mage, 1st Rank, leather jerkin (+1), Defence 4.
eq(Rules.defence(Rules.PROFESSIONS.Mage.COMBAT, 1, 1), 4, "Chalor's Defence")
-- Marana Fireheart: Rogue, 1st Rank, leather jerkin (+1), Defence 6.
eq(Rules.defence(Rules.PROFESSIONS.Rogue.COMBAT, 1, 1), 6, "Marana's Defence")

-- Codewords ----------------------------------------------------------------
do
    local book, title = Rules.codewordBook("Aid")
    eq(book, 1, "A-codewords come from Book 1")
    eq(title, "The War-Torn Kingdom", "Book 1 title")
    -- Book (p. 7): a codeword beginning with C comes from Book 3.
    eq((Rules.codewordBook("Cargo")), 3, "C-codewords come from Book 3")
    eq((Rules.codewordBook("deliver")), 4, "lookup is case-insensitive")
    eq((Rules.codewordBook("7")), nil, "a non-letter has no book")
end

-- Dice ---------------------------------------------------------------------
do
    local dice, sum = Rules.rollDice(2, scripted(3, 5))
    eq(#dice, 2, "two dice returned")
    eq(dice[1], 3, "first die")
    eq(dice[2], 5, "second die")
    eq(sum, 8, "dice sum")

    local lo, hi = 99, 0
    for _ = 1, 2000 do
        local _, total = Rules.rollDice(2)
        lo, hi = math.min(lo, total), math.max(hi, total)
    end
    check(lo >= 2 and hi <= 12, "2d6 stays within 2-12", ("saw %d..%d"):format(lo, hi))
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
