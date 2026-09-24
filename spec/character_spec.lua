--[[--
Unit tests for the Adventure Sheet model.

    luajit spec/character_spec.lua
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
    check(haystack:find(needle, 1, true) ~= nil, label, ("%q not found"):format(needle))
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

-- The trail of sections visited -------------------------------------------
do
    local hero = Character.create("Wanderer", "Rogue")
    eq(#hero:sectionTrail("book1.pdf"), 0, "trail starts empty")

    hero:recordSection(1, 9, "book1.pdf")
    hero:recordSection(20, 14, "book1.pdf")
    hero:recordSection(38, 20, "book1.pdf")

    local trail = hero:sectionTrail("book1.pdf")
    eq(#trail, 3, "three sections remembered")
    eq(trail[1].section, 38, "most recent first")
    eq(trail[1].page, 20, "with the page it was on")
    eq(trail[3].section, 1, "oldest last")

    -- Page numbers mean nothing in another book, so trails are kept apart.
    hero:recordSection(7, 55, "book3.pdf")
    eq(#hero:sectionTrail("book1.pdf"), 3, "the other book's trail is unaffected")
    eq(#hero:sectionTrail("book3.pdf"), 1, "and has its own")
    eq(hero:sectionTrail("book3.pdf")[1].page, 55, "with its own page")

    -- Re-visiting moves a section up rather than duplicating it.
    hero:recordSection(20, 14, "book1.pdf")
    local again = hero:sectionTrail("book1.pdf")
    eq(#again, 3, "still three, not four")
    eq(again[1].section, 20, "the revisited section is now most recent")

    -- The trail is capped, oldest dropped first.
    for n = 100, 100 + Character.TRAIL_LENGTH do
        hero:recordSection(n, n, "book1.pdf")
    end
    local capped = hero:sectionTrail("book1.pdf")
    check(#capped <= Character.TRAIL_LENGTH, "trail is capped",
        ("%d entries"):format(#capped))
    eq(capped[1].section, 100 + Character.TRAIL_LENGTH, "newest survives")

    hero:clearTrail("book1.pdf")
    eq(#hero:sectionTrail("book1.pdf"), 0, "trail cleared for that book")
    eq(#hero:sectionTrail("book3.pdf"), 1, "but not for the other")

    -- It survives a round-trip through storage.
    local function strip(v)
        if type(v) ~= "table" then return v end
        local c = {} for k, x in pairs(v) do c[k] = strip(x) end return c
    end
    local revived = Character.restore(strip(hero))
    eq(#revived:sectionTrail("book3.pdf"), 1, "trail persists")
    eq(revived:sectionTrail("book3.pdf")[1].section, 7, "with its section")
end

-- Correcting name and profession ------------------------------------------
do
    local hero = Character.create("Marana", "Rogue", 3)
    local before = {}
    for _, a in ipairs(Rules.ABILITIES) do before[a] = hero.abilities[a] end

    eq(hero:rename("  Marana Fireheart  "), true, "renamed")
    eq(hero.name, "Marana Fireheart", "trimmed")
    eq(hero:rename("   "), false, "a blank name is refused")
    eq(hero.name, "Marana Fireheart", "and the old name survives the refusal")

    -- Profession is a label once play has begun: the scores have moved on.
    hero:adjustAbility("THIEVERY", 2)
    local thievery = hero.abilities.THIEVERY
    eq(hero:setProfession("Warrior"), true, "profession changed")
    eq(hero.profession, "Warrior", "recorded")
    eq(hero.abilities.THIEVERY, thievery, "abilities are not rewritten")
    for _, a in ipairs(Rules.ABILITIES) do
        if a ~= "THIEVERY" then
            eq(hero.abilities[a], before[a], a .. " untouched by the change")
        end
    end

    local ok, err = hero:setProfession("Necromancer")
    eq(ok, false, "an unknown profession is refused")
    check(err ~= nil, "refusal explains itself")
    eq(hero.profession, "Warrior", "profession unchanged by a refusal")
end

-- Your god, and dying ------------------------------------------------------
do
    local hero = Character.create("Faithful", "Priest")
    eq(hero.god, nil, "no god to begin with")
    eq(hero:arrangementCount(), 0, "and nothing arranged")

    eq(hero:setGod("  Nagil  "), "Nagil", "god recorded and trimmed")
    eq(hero:addResurrection("Temple of Nagil, Marlock City", 478), true, "arrangement made")
    eq(hero:addResurrection("Temple of Sig", "33"), true, "section accepts a string")
    eq(hero:arrangementCount(), 2, "two outstanding")
    eq(hero.resurrection[2].section, 33, "section stored as a number")
    eq(hero:addResurrection("   ", 1), false, "an arrangement needs a place")

    -- Renouncing costs the arrangements, which were made with that temple.
    local lost = hero:renounceGod()
    eq(lost, 2, "renouncing reports what it cost")
    eq(hero.god, nil, "god cleared")
    eq(hero:arrangementCount(), 0, "arrangements gone with it")

    -- Clearing a god by setting an empty name does the same as unsetting.
    hero:setGod("Tyrnai")
    eq(hero:setGod(""), nil, "an empty name clears the god")

    -- Taking up a different god renounces the old one, arrangements and all.
    -- Naming a first god, or correcting the case of the current one, does not.
    hero:addResurrection("Temple of Sig", 33)
    eq(hero:godChangeCost("Sig"), 0, "naming a first god costs nothing")
    local _god, lost = hero:setGod("Sig")
    eq(lost, 0, "and nothing was lost")
    eq(hero:arrangementCount(), 1, "the arrangement stands")
    eq(hero:godChangeCost("  SIG "), 0, "retyping the same god in other case costs nothing")
    hero:setGod("  SIG ")
    eq(hero:arrangementCount(), 1, "arrangement kept through a case correction")
    eq(hero:godChangeCost("Tyrnai"), 1, "switching gods puts the arrangement at stake")
    eq(hero:godChangeCost(""), 1, "so does clearing the box")
    local god, cost = hero:setGod("Tyrnai")
    eq(god, "Tyrnai", "new god recorded")
    eq(cost, 1, "switching reports what it cost")
    eq(hero:arrangementCount(), 0, "arrangements gone with the old god")
    hero:setGod("")

    -- The sheet shows the arrangement exactly when it is needed.
    hero:setGod("Nagil")
    hero:addResurrection("Temple of Nagil", 478)
    local alive = Format.sheet(hero)
    contains(alive, "Nagil", "god shown on the sheet")
    lacks(alive, "turn to 478", "but not the arrangement while alive")

    hero:takeDamage(99)
    local dead = Format.sheet(hero)
    contains(dead, "DEAD", "death called out")
    contains(dead, "turn to 478", "and the arrangement surfaces with it")

    local unprepared = Character.create("Rash", "Warrior")
    unprepared:takeDamage(99)
    contains(Format.sheet(unprepared), "No resurrection arranged",
        "and says so when nothing was arranged")
end

-- Rolling for the ship -----------------------------------------------------
do
    -- One die for a barque, two for a brigantine, three for a galleon;
    -- +1 for a good crew, +2 for an excellent one.
    local barque = Rules.shipRoll("barque", "average", scripted(4))
    eq(#barque.dice, 1, "a barque rolls one die")
    eq(barque.total, 4, "no bonus for an average crew")

    local brig = Rules.shipRoll("brigantine", "good", scripted(3, 5))
    eq(#brig.dice, 2, "a brigantine rolls two")
    eq(brig.total, 9, "3 + 5 + 1 for a good crew")

    local galleon = Rules.shipRoll("galleon", "excellent", scripted(1, 2, 3))
    eq(#galleon.dice, 3, "a galleon rolls three")
    eq(galleon.total, 8, "1 + 2 + 3 + 2 for an excellent crew")

    eq(Rules.shipRoll("Galleon", "POOR", scripted(6, 6, 6)).total, 18, "case-insensitive")
    eq(Rules.shipRoll("raft", "good"), nil, "an unknown hull cannot be rolled")
    eq(Rules.shipRoll(nil, nil), nil, "nor can no hull at all")
    eq(Rules.shipRoll("barque", nil, scripted(2)).total, 2, "no crew means no bonus")
end

-- Cargo against capacity ---------------------------------------------------
do
    local hero = Character.create("Trader", "Rogue")
    hero.ship = { name = "Sea Dog", type = "brigantine", crew = "good",
                  capacity = 6, cargo = { "timber", "wine" } }
    contains(Format.ship(hero.ship), "cargo 2/6", "the hold shows what is used")
    contains(Format.sheet(hero), "cargo 2/6", "and it reaches the sheet")

    hero.ship.capacity = nil
    lacks(Format.ship(hero.ship), "cargo", "no capacity set means no cargo line")
end

-- Ships saved by 0.3.0 -----------------------------------------------------
-- Every Manifest field used to be typed text. Cargo was a description, and
-- reading it as a list either threw or counted its letters as units.
do
    local legacy = Character.restore({ name = "Old", profession = "Rogue",
        ship = { name = "Sea Dog", type = " Brigantine ", crew = "GOOD",
                 capacity = "6", cargo = "timber", docked = "Yellowport" } })
    local ship = legacy.ship
    eq(type(ship.cargo), "table", "text cargo becomes a list")
    eq(#ship.cargo, 1, "holding the one description that was typed")
    eq(ship.cargo[1], "timber", "unchanged")
    eq(ship.capacity, 6, "capacity becomes a number")
    eq(ship.type, "brigantine", "type lower-cased and trimmed for the picker")
    eq(ship.crew, "good", "crew lower-cased for the picker")
    eq(ship.name, "Sea Dog", "name untouched")
    contains(Format.ship(ship), "cargo 1/6", "the sheet counts units, not letters")

    -- The roll works on migrated data.
    eq(#Rules.shipRoll(ship.type, ship.crew, scripted(1, 1)).dice, 2, "a migrated brigantine rolls two dice")

    -- Blank fields from the old form become absent rather than empty.
    local blank = Character.restore({ ship = { name = "Raft", type = "", crew = "  ",
                                               capacity = "", cargo = "   " } })
    eq(#blank.ship.cargo, 0, "blank cargo text becomes an empty hold")
    eq(blank.ship.capacity, nil, "blank capacity becomes unset")
    eq(blank.ship.type, nil, "blank type becomes unset")
    eq(blank.ship.crew, nil, "blank crew becomes unset")

    -- Current data passes through untouched.
    local current = Character.restore({ ship = { type = "galleon", crew = "excellent",
                                                 capacity = 10, cargo = { "wine", "silk" } } })
    eq(#current.ship.cargo, 2, "a list of units is left as it is")
    eq(current.ship.capacity, 10, "numeric capacity kept")

    -- Restoring twice changes nothing further.
    local twice = Character.restore(Character.restore({ ship = { cargo = "furs", capacity = "4" } }))
    eq(#twice.ship.cargo, 1, "restoring is idempotent")
    eq(twice.ship.cargo[1], "furs", "and does not nest the list")
end

-- Trails recorded under a filename move to the book's checksum -------------
do
    local hero = Character.create("Mover", "Rogue")
    hero:recordSection(10, 5, "book1.pdf")
    hero:recordSection(20, 9, "book1.pdf")
    hero:recordSection(7, 3, "book2.pdf")

    eq(hero:rekeyTrail("book1.pdf", "abc123"), 2, "both entries moved")
    eq(#hero:sectionTrail("book1.pdf"), 0, "nothing left under the filename")
    local moved = hero:sectionTrail("abc123")
    eq(#moved, 2, "found under the checksum")
    eq(moved[1].section, 20, "order kept, most recent first")
    eq(#hero:sectionTrail("book2.pdf"), 1, "another book's trail untouched")
    eq(hero:rekeyTrail("book1.pdf", "abc123"), 0, "a second pass moves nothing")
    eq(hero:rekeyTrail("abc123", "abc123"), 0, "same key is a no-op")

    -- A book with entries under both keys keeps the latest visit per section.
    hero:recordSection(10, 6, "abc123")
    hero:recordSection(10, 5, "book1.pdf")
    hero:recordSection(30, 12, "book1.pdf")
    hero:rekeyTrail("book1.pdf", "abc123")
    local merged = hero:sectionTrail("abc123")
    eq(#merged, 3, "duplicate section merged")
    eq(merged[1].section, 30, "latest first")
    eq(merged[2].section, 10, "section 10 kept once")
    eq(merged[2].page, 5, "at its most recent page")

    -- And stays within the length limit.
    local long = Character.create("Long", "Rogue")
    for n = 1, Character.TRAIL_LENGTH do long:recordSection(n, n, "old.pdf") end
    for n = 101, 105 do long:recordSection(n, n, "md5") end
    long:rekeyTrail("old.pdf", "md5")
    eq(#long:sectionTrail("md5"), Character.TRAIL_LENGTH, "merged trail trimmed")
    local trail = long:sectionTrail("md5")
    eq(trail[1].section, 105, "the newest visit survives the trim")
    eq(trail[#trail].section, 6, "the five oldest were dropped")
    eq(Character.create("Empty", "Rogue"):rekeyTrail("a", "b"), 0, "no trail at all is fine")
end

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
