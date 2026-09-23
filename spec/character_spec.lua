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
    eq(hero.codewords[1], "Anchor", "list is kept sorted")
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

io.write(("\n%d checks, %d failures\n"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
