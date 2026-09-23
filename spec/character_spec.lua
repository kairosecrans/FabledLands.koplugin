--[[--
Unit tests for the Adventure Sheet model.

    luajit spec/character_spec.lua
--]]--

package.path = "?.lua;" .. package.path
local Character = require("fl_character")
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

local function scripted(...)
    local queue, i = { ... }, 0
    return function()
        i = i + 1
        assert(queue[i], "scripted rng ran out of values")
        return queue[i]
    end
end

-- Creation -----------------------------------------------------------------
-- A new Warrior should match Andriel the Hammer on the inside cover:
-- Stamina 9, Defence 8, 16 Shards.
do
    local hero = Character.create("Andriel the Hammer", "Warrior")
    eq(hero.name, "Andriel the Hammer", "name")
    eq(hero.profession, "Warrior", "profession")
    eq(hero.rank, 1, "starts at 1st Rank")
    eq(hero:rankTitle(), "Outcast", "1st Rank title")
    eq(hero.abilities.COMBAT, 6, "warrior COMBAT")
    eq(hero.abilities.SANCTITY, 4, "warrior SANCTITY")
    eq(hero.stamina, 9, "starting Stamina")
    eq(hero.stamina_max, 9, "starting unwounded Stamina")
    eq(hero.shards, 16, "starting Shards")
    eq(#hero.possessions, 3, "sword, jerkin and map")
    eq(hero:armourBonus(), 1, "leather jerkin is +1")
    eq(hero:defence(), 8, "Defence = COMBAT 6 + Rank 1 + jerkin 1")
    eq(hero:isDead(), false, "starts alive")
    eq(hero:isEncumbered(), false, "starts unencumbered")

    local bad, err = Character.create("Nobody", "Necromancer")
    eq(bad, nil, "unknown profession is refused")
    check(err ~= nil, "unknown profession explains itself")
end

-- Creating each profession should reproduce its printed starting Defence.
do
    local expected = { Mage = 4, Priest = 4, Rogue = 6, Troubadour = 5, Warrior = 8, Wayfarer = 7 }
    for _, name in ipairs(Rules.PROFESSION_NAMES) do
        local hero = Character.create("Test", name)
        eq(hero:defence(), expected[name], name .. " starting Defence")
    end
end

-- Persistence round-trip ---------------------------------------------------
-- LuaSettings stores the raw table, so a character must survive losing its
-- metatable and getting it back.
do
    local hero = Character.create("Marana Fireheart", "Rogue")
    hero:addCodeword("Aid")
    hero:takeDamage(3)

    local function strip(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for k, v in pairs(value) do copy[k] = strip(v) end
        return copy -- deliberately no metatable, as if read back from disk
    end

    local revived = Character.restore(strip(hero))
    eq(revived.name, "Marana Fireheart", "name survives")
    eq(revived.stamina, 6, "current Stamina survives")
    eq(revived:defence(), 6, "derived Defence still works")
    eq(revived:hasCodeword("Aid"), true, "codewords survive")
end

-- restore() should tolerate a sparse or legacy table without crashing.
do
    local sparse = Character.restore({ name = "Fragment" })
    eq(sparse.rank, 1, "missing Rank defaults")
    eq(sparse.stamina, Rules.STARTING_STAMINA, "missing Stamina defaults")
    eq(sparse.abilities.COMBAT, Rules.ABILITY_MIN, "missing abilities default to 1")
    eq(#sparse.possessions, 0, "missing possessions default to empty")
    eq(sparse:defence(), 2, "Defence still computable")
    eq(Character.restore(nil).rank, 1, "restore(nil) does not crash")

    -- Codewords saved before normalisation existed get tidied on load.
    local legacy = Character.restore({ codewords = { "ALMANAC", "deLIVER", "Aid" } })
    eq(legacy.codewords[1], "Almanac", "shouted legacy codeword normalised")
    eq(legacy.codewords[2], "Deliver", "mixed-case legacy codeword normalised")
    eq(legacy.codewords[3], "Aid", "already-correct codeword left alone")
    eq(legacy:hasCodeword("almanac"), true, "still found case-insensitively")
end

-- Stamina ------------------------------------------------------------------
do
    local hero = Character.create("Wounded", "Warrior")
    eq(hero:takeDamage(4), 4, "damage reported")
    eq(hero.stamina, 5, "Stamina reduced")
    eq(hero:isDead(), false, "still alive")

    eq(hero:heal(2), 2, "healing reported")
    eq(hero.stamina, 7, "Stamina restored")

    -- Stamina cannot go above the unwounded score until you advance in Rank.
    eq(hero:heal(99), 2, "healing stops at the unwounded score")
    eq(hero.stamina, 9, "capped at max")

    -- Damage floors at zero rather than going negative, and zero is death.
    eq(hero:takeDamage(99), 9, "overkill only reports the Stamina actually lost")
    eq(hero.stamina, 0, "Stamina floors at zero")
    eq(hero:isDead(), true, "zero Stamina is death")
end

-- Rank-up ------------------------------------------------------------------
do
    local hero = Character.create("Rising", "Warrior")
    hero:takeDamage(4) -- 5/9
    local gain = hero:rankUp(scripted(4))
    eq(gain, 4, "rank-up rolled one die")
    eq(hero.rank, 2, "Rank advanced")
    eq(hero:rankTitle(), "Commoner", "2nd Rank title")
    eq(hero.stamina_max, 13, "unwounded score gained the die")
    eq(hero.stamina, 9, "current Stamina gained the die too")
    eq(hero:defence(), 9, "Defence follows Rank")
end

-- Abilities ----------------------------------------------------------------
do
    local hero = Character.create("Learner", "Mage")
    eq(hero:adjustAbility("MAGIC", 1), 7, "ability raised")
    eq(hero:adjustAbility("MAGIC", 99), 12, "abilities cap at 12")
    eq(hero:adjustAbility("SANCTITY", -1), 1, "SANCTITY 1 cannot drop below 1")
    eq(hero.abilities.SANCTITY, 1, "floor holds")
end

-- Possessions --------------------------------------------------------------
do
    local hero = Character.create("Hoarder", "Warrior")
    -- Starts with 3; the limit is 12.
    for i = 4, Rules.MAX_POSSESSIONS do
        local ok = hero:addPossession({ name = "trinket " .. i })
        eq(ok, true, "item " .. i .. " fits")
    end
    eq(#hero.possessions, 12, "carrying twelve")
    eq(hero:isEncumbered(), true, "encumbered at the limit")

    local ok, err = hero:addPossession({ name = "one too many" })
    eq(ok, false, "thirteenth item refused")
    check(err ~= nil, "refusal explains itself")
    eq(#hero.possessions, 12, "pack unchanged by a refused item")

    local dropped = hero:removePossession(1)
    eq(dropped.name, "sword", "removal returns the item")
    eq(#hero.possessions, 11, "pack shrank")
    eq(hero:addPossession({ name = "now it fits" }), true, "room again after dropping")
end

-- Item bonuses feed the derived scores -------------------------------------
do
    local hero = Character.create("Armed", "Wayfarer")
    eq(hero:defence(), 7, "Defence before upgrades")

    hero:addPossession({ name = "trident", ability = "COMBAT", bonus = 1 })
    hero:addPossession({ name = "chain mail tabard", defence = 2 })
    eq(hero:itemBonus("COMBAT"), 1, "weapon bonus found")
    eq(hero:armourBonus(), 2, "better armour supersedes the jerkin")
    eq(hero:defence(), 8, "Defence = COMBAT 5 + Rank 1 + tabard 2")

    -- An attack applies the weapon bonus: 2d6=8, +COMBAT 5, +1 = 14 vs 7 -> 7.
    local blow = hero:attack(7, scripted(5, 3))
    eq(blow.total, 14, "attack total includes the weapon bonus")
    eq(blow.damage, 7, "damage is the margin")

    -- Checks apply the best item bonus for that ability only.
    hero:addPossession({ name = "lockpicks", ability = "THIEVERY", bonus = 1 })
    hero:addPossession({ name = "magic lockpicks", ability = "THIEVERY", bonus = 2 })
    eq(hero:itemBonus("THIEVERY"), 2, "thievery bonuses do not stack")
    local climb = hero:check("THIEVERY", 9, scripted(2, 2)) -- 4 + THIEVERY 4 + 2 = 10
    eq(climb.total, 10, "check total includes the item bonus")
    eq(climb.success, true, "10 beats Difficulty 9")
end

-- Codewords ----------------------------------------------------------------
do
    local hero = Character.create("Traveller", "Rogue")
    eq(hero:addCodeword("Deliver"), true, "codeword recorded")
    eq(hero:hasCodeword("Deliver"), true, "codeword found")
    eq(hero:hasCodeword("deliver"), true, "lookup is case-insensitive")
    eq(hero:addCodeword("deliver"), false, "duplicates refused case-insensitively")
    eq(#hero.codewords, 1, "still one codeword")

    eq(hero:addCodeword("  Anchor  "), true, "surrounding space is trimmed")

    -- However they are typed, codewords are stored the way the books print
    -- them: one leading capital, the rest lower case.
    eq(hero:addCodeword("ALMANAC"), true, "shouted codeword accepted")
    eq(hero:hasCodeword("ALMANAC"), true, "found however it was typed")
    eq(hero:addCodeword("Almanac"), false, "and not addable a second time")
    eq(hero:addCodeword("aLmAnAc"), false, "nor in any other casing")
    local stored
    for _, held in ipairs(hero.codewords) do
        if held:lower() == "almanac" then stored = held end
    end
    eq(stored, "Almanac", "stored with a single leading capital")
    eq(Character.normaliseCodeword("  wILd bOAR "), "Wild boar", "normalisation trims and cases")
    eq(Character.normaliseCodeword("   "), "", "blank normalises to empty")
    -- Sortedness is the invariant; pinning an index just breaks whenever the
    -- fixture gains another codeword.
    local sorted = true
    for i = 2, #hero.codewords do
        if hero.codewords[i - 1]:lower() > hero.codewords[i]:lower() then sorted = false end
    end
    check(sorted, "list is kept sorted", table.concat(hero.codewords, ", "))
    eq(hero:addCodeword("   "), false, "blank codeword refused")
    eq(hero:hasCodeword("Artefact"), false, "codeword not held")

    eq(hero:removeCodeword("DELIVER"), true, "removal is case-insensitive")
    eq(hero:hasCodeword("Deliver"), false, "codeword gone")
    eq(hero:removeCodeword("Nonesuch"), false, "removing what you lack is a no-op")
end

-- Blessings ----------------------------------------------------------------
do
    local hero = Character.create("Blessed", "Priest")
    eq(hero:addBlessing({ name = "Blessing of Nagil", ability = "COMBAT" }), true, "first blessing")
    eq(hero:addBlessing({ name = "Blessing of Tyrnai", ability = "THIEVERY" }), true,
        "a different type is allowed")

    local ok, err = hero:addBlessing({ name = "Another war blessing", ability = "COMBAT" })
    eq(ok, false, "a second blessing of the same type is refused")
    check(err ~= nil, "refusal explains itself")
    eq(#hero.blessings, 2, "blessing list unchanged")

    -- Untyped blessings (Safety from Storms, say) are not restricted.
    eq(hero:addBlessing({ name = "Safety from Storms" }), true, "untyped blessing allowed")
    eq(hero:addBlessing({ name = "Safe passage" }), true, "a second untyped blessing allowed")
    eq(#hero.blessings, 4, "four blessings held")

    local removed = hero:removeBlessing(1)
    eq(removed.name, "Blessing of Nagil", "removal returns the blessing")
    eq(hero:addBlessing({ name = "New war blessing", ability = "COMBAT" }), true,
        "the COMBAT slot frees up again")
end

-- Starting in a later book ------------------------------------------------
-- You need only one book to start, and a later one begins you further along.
-- These are the printed values from each book's front matter.
do
    local expected = {
        [1] = { rank = 1, stamina = 9,  shards = 16 },
        [2] = { rank = 2, stamina = 13, shards = 16 },
        [3] = { rank = 3, stamina = 16, shards = 40 },
        [4] = { rank = 4, stamina = 20, shards = 65 },
        [5] = { rank = 5, stamina = 23, shards = 65 },
        [6] = { rank = 6, stamina = 27, shards = 0  },
    }
    for book, want in pairs(expected) do
        local hero = Character.create("Traveller", "Warrior", book)
        eq(hero.rank, want.rank, ("book %d starting Rank"):format(book))
        eq(hero.stamina, want.stamina, ("book %d starting Stamina"):format(book))
        eq(hero.stamina_max, want.stamina, ("book %d unwounded Stamina"):format(book))
        eq(hero.shards, want.shards, ("book %d starting Shards"):format(book))
        eq(hero.started_in, book, ("book %d recorded"):format(book))
    end

    -- Book 1 stays the default, so old callers are unaffected.
    local default = Character.create("Default", "Warrior")
    eq(default.rank, 1, "no book given means Book 1")
    eq(default.stamina, 9, "default Stamina")
    eq(default.shards, 16, "default Shards")

    local bad, err = Character.create("Nobody", "Warrior", 99)
    eq(bad, nil, "unknown starting book refused")
    check(err ~= nil, "unknown starting book explains itself")
end

-- The later books scale the profession tables, and their Defence scores must
-- reproduce the pre-generated characters printed in each book.
do
    -- Book 3 Warrior: COMBAT 7, 3rd Rank, chain mail (+3) -> Defence 13.
    local b3 = Character.create("Third", "Warrior", 3)
    eq(b3.abilities.COMBAT, 7, "book 3 Warrior COMBAT")
    eq(b3:armourBonus(), 3, "book 3 starts in chain mail")
    eq(b3:defence(), 13, "book 3 Warrior Defence matches the printed 13")

    -- Book 4 Warrior: COMBAT 7, 4th Rank, chain mail (+3) -> Defence 14.
    eq(Character.create("Fourth", "Warrior", 4):defence(), 14, "book 4 Warrior Defence")
    -- Book 4 Priest: COMBAT 3, 4th Rank, chain mail (+3) -> Defence 10.
    eq(Character.create("Fourth", "Priest", 4):defence(), 10, "book 4 Priest Defence")
    -- Book 5 Troubadour: COMBAT 5, 5th Rank, chain mail (+3) -> Defence 13.
    eq(Character.create("Fifth", "Troubadour", 5):defence(), 13, "book 5 Troubadour Defence")
    -- Book 6 Warrior: COMBAT 8, 6th Rank, no armour -> Defence 14.
    local b6 = Character.create("Sixth", "Warrior", 6)
    eq(b6:armourBonus(), 0, "book 6 starts with no armour")
    eq(b6:defence(), 14, "book 6 Warrior Defence matches the printed 14")
    eq(#b6.possessions, 1, "book 6 starts with almost nothing")

    -- Books pair up: 1-2, 3-4 and 5-6 share a profession table.
    for _, pair in ipairs({ {1,2}, {3,4}, {5,6} }) do
        for _, ability in ipairs(Rules.ABILITIES) do
            eq(Rules.professionsFor(pair[1]).Rogue[ability],
               Rules.professionsFor(pair[2]).Rogue[ability],
               ("books %d and %d share %s"):format(pair[1], pair[2], ability))
        end
    end
    -- ...and the tiers really do differ from one another.
    check(Rules.professionsFor(1).Warrior.COMBAT ~= Rules.professionsFor(3).Warrior.COMBAT,
        "tier 1 and tier 2 differ")
    check(Rules.professionsFor(3).Warrior.COMBAT ~= Rules.professionsFor(5).Warrior.COMBAT,
        "tier 2 and tier 3 differ")

    -- Every starting score must still sit inside the 1-12 range.
    for book = 1, #Rules.STARTING_BOOKS do
        for _, profession in ipairs(Rules.PROFESSION_NAMES) do
            for _, ability in ipairs(Rules.ABILITIES) do
                local score = Rules.professionsFor(book)[profession][ability]
                check(score >= Rules.ABILITY_MIN and score <= Rules.ABILITY_MAX,
                    ("book %d %s %s in range"):format(book, profession, ability))
            end
        end
    end

    -- A character's kit must be its own, not shared template data.
    local a = Character.create("A", "Warrior", 3)
    local b = Character.create("B", "Warrior", 3)
    a.possessions[1].name = "changed"
    eq(b.possessions[1].name, "sword", "one character's gear does not affect another's")
end

-- Losing a Rank, and undoing one ------------------------------------------
do
    -- A genuine Rank loss rolls its own die (Book 4).
    local hero = Character.create("Faller", "Warrior", 4)   -- 4th Rank, 20 Stamina
    eq(hero.rank, 4, "starts 4th Rank")
    local loss = hero:rankDown(scripted(5))
    eq(loss, 5, "rank loss rolled one die")
    eq(hero.rank, 3, "Rank dropped")
    eq(hero.stamina_max, 15, "unwounded score lost the die")
    eq(hero.stamina, 15, "current Stamina cannot exceed the new maximum")
    eq(hero:defence(), 13, "Defence follows the lower Rank")

    -- It will not go below the lowest Rank.
    local low = Character.create("Bottom", "Warrior", 1)
    local nope, err = low:rankDown(scripted(3))
    eq(nope, nil, "cannot drop below 1st Rank")
    check(err ~= nil, "refusal explains itself")
    eq(low.rank, 1, "Rank unchanged by a refused drop")

    -- Stamina never falls below one point.
    local frail = Character.create("Frail", "Mage", 2)
    frail.stamina_max, frail.stamina = 2, 2
    frail:rankDown(scripted(6))
    eq(frail.stamina_max, 1, "unwounded score floors at 1")
    eq(frail.stamina, 1, "current Stamina floors with it")
end

-- Undo reverses exactly, rather than rolling again.
do
    local hero = Character.create("Mistap", "Warrior")   -- 1st Rank, 9 Stamina
    eq(hero:canUndoRankUp(), false, "nothing to undo at the start")

    hero:rankUp(scripted(6))
    eq(hero.rank, 2, "ranked up")
    eq(hero.stamina_max, 15, "gained 6")
    eq(hero:canUndoRankUp(), true, "the gain is remembered")

    local back = hero:undoRankUp()
    eq(back, 6, "undo returns the original roll, not a new one")
    eq(hero.rank, 1, "Rank restored")
    eq(hero.stamina_max, 9, "unwounded score exactly restored")
    eq(hero.stamina, 9, "current Stamina restored")
    eq(hero:canUndoRankUp(), false, "nothing left to undo")
    eq(hero:undoRankUp(), nil, "a second undo does nothing")

    -- Undo unwinds several gains in order, most recent first.
    hero:rankUp(scripted(2)); hero:rankUp(scripted(5))
    eq(hero.stamina_max, 16, "two gains applied")
    eq(hero:undoRankUp(), 5, "most recent gain undone first")
    eq(hero:undoRankUp(), 2, "then the earlier one")
    eq(hero.stamina_max, 9, "back where it started")

    -- A real Rank loss is not an undo: it consumes the remembered gain so a
    -- later undo cannot hand the Stamina back a second time.
    hero:rankUp(scripted(4))
    eq(hero.stamina_max, 13, "gained 4")
    hero:rankDown(scripted(1))
    eq(hero.stamina_max, 12, "lost its own roll of 1, not the remembered 4")
    eq(hero:canUndoRankUp(), false, "the remembered gain was consumed")

    -- A character created in a later book has no history to undo.
    local later = Character.create("Later", "Rogue", 5)
    eq(later:canUndoRankUp(), false, "no phantom undo for a later-book start")
    eq(later.rank, 5, "still 5th Rank")
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
