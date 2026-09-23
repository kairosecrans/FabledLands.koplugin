--[[--
The Adventure Sheet: a character's state, and the operations the rules allow
on it.

Like rules.lua this is plain Lua with no KOReader dependency, so it can be
unit-tested. A character is an ordinary table with a metatable bolted on,
which means it round-trips through LuaSettings without any conversion --
persistence just stores the raw table and calls Character.restore() on the
way back.

In Fabled Lands one persona travels across the whole series, so a character
is never tied to a particular book or document.

@module koplugin.FabledLands.character
--]]--

local Rules = require("fl_rules")

local Character = {}
Character.__index = Character

--- Builds a fresh character of the given profession, ready to start in a book.
--
-- You may begin the series at any book, and a later one starts you further
-- along: higher Rank, more Stamina, more money and better gear, with ability
-- scores drawn from that book's own profession table. Defaults to Book 1.
-- @string name
-- @string profession
-- @int book 1-6, defaults to 1
function Character.create(name, profession, book)
    book = book or 1
    local start = Rules.STARTING_BOOKS[book]
    if not start then return nil, "unknown starting book: " .. tostring(book) end

    local stats = Rules.professionsFor(book)[profession]
    if not stats then return nil, "unknown profession: " .. tostring(profession) end

    local abilities = {}
    for ability, score in pairs(stats) do
        abilities[ability] = score
    end

    -- Copied, not referenced: the kit is shared template data and a character
    -- must be free to drop or upgrade its own gear.
    local possessions = {}
    for _i, item in ipairs(start.kit) do
        possessions[#possessions + 1] = { name = item.name, ability = item.ability,
            bonus = item.bonus, defence = item.defence }
    end

    return Character.restore({
        name = name,
        profession = profession,
        started_in = book,
        rank = start.rank,
        abilities = abilities,
        stamina = start.stamina,
        stamina_max = start.stamina,
        shards = start.shards,
        possessions = possessions,
        codewords = {},
        titles = {},
        blessings = {},
        notes = "",
    })
end

--- Re-attaches behaviour to a plain data table loaded from disk, filling in
-- any field a character saved by an older version might be missing.
function Character.restore(data)
    data = data or {}
    data.abilities = data.abilities or {}
    data.possessions = data.possessions or {}
    data.codewords = data.codewords or {}
    data.titles = data.titles or {}
    data.blessings = data.blessings or {}
    data.rank_gains = data.rank_gains or {}
    data.rank = data.rank or 1
    data.shards = data.shards or 0
    data.stamina_max = data.stamina_max or Rules.STARTING_STAMINA
    data.stamina = data.stamina or data.stamina_max
    for _, ability in ipairs(Rules.ABILITIES) do
        data.abilities[ability] = data.abilities[ability] or Rules.ABILITY_MIN
    end
    return setmetatable(data, Character)
end

-- Derived scores -----------------------------------------------------------

function Character:armourBonus()
    return Rules.bestArmour(self.possessions)
end

--- The best item bonus for an ability. Bonuses never stack (p. 7).
function Character:itemBonus(ability)
    return Rules.bestBonus(self.possessions, ability)
end

function Character:defence()
    return Rules.defence(self.abilities.COMBAT, self.rank, self:armourBonus())
end

function Character:rankTitle()
    return Rules.rankTitle(self.rank)
end

function Character:isDead()
    return self.stamina <= 0
end

-- Rolling ------------------------------------------------------------------

--- Makes an ability check, applying the best relevant item bonus.
function Character:check(ability, difficulty, rng)
    return Rules.abilityCheck(self.abilities[ability], self:itemBonus(ability), difficulty, rng)
end

--- Strikes at a Defence score, applying the best weapon bonus.
function Character:attack(target_defence, rng)
    return Rules.strike(self.abilities.COMBAT, self:itemBonus("COMBAT"), target_defence, rng)
end

-- Stamina ------------------------------------------------------------------

--- Applies damage. Stamina floors at zero, which is death (p. 5).
-- @treturn int the Stamina actually lost
function Character:takeDamage(amount)
    local before = self.stamina
    self.stamina = math.max(0, self.stamina - amount)
    return before - self.stamina
end

--- Restores Stamina, never above the unwounded score (p. 5).
-- @treturn int the Stamina actually regained
function Character:heal(amount)
    local before = self.stamina
    self.stamina = math.min(self.stamina_max, self.stamina + amount)
    return self.stamina - before
end

--- Advances a Rank: +1 Rank and 1d6 permanent Stamina, gained on both the
-- current and the unwounded score.
--
-- The roll is remembered so it can be reversed exactly. Rolling a fresh die
-- to undo a mis-tap would quietly change the character.
-- @treturn int the Stamina gained
function Character:rankUp(rng)
    local gain = Rules.rankUpStamina(rng)
    self.rank = self.rank + 1
    self.stamina_max = self.stamina_max + gain
    self.stamina = self.stamina + gain
    self.rank_gains = self.rank_gains or {}
    table.insert(self.rank_gains, gain)
    return gain
end

--- Losing a Rank, as the books occasionally impose: -1 Rank and a die's worth
-- of Stamina, lost permanently. Not an undo -- it rolls afresh.
-- @treturn int|nil the Stamina lost, or nil if already at the lowest Rank
-- @treturn string|nil reason for refusal
function Character:rankDown(rng)
    if self.rank <= Rules.MIN_RANK then
        return nil, ("You cannot go below %s Rank."):format(Rules.ordinal(Rules.MIN_RANK))
    end
    local loss = Rules.rankUpStamina(rng)
    self.rank = self.rank - 1
    -- A character always keeps at least one point to stand up in.
    self.stamina_max = math.max(1, self.stamina_max - loss)
    self.stamina = math.min(self.stamina, self.stamina_max)
    -- A genuine Rank loss is not an undo, so it consumes any remembered gain:
    -- the Stamina that gain added is gone by another route.
    if self.rank_gains then table.remove(self.rank_gains) end
    return loss
end

--- True when there is a remembered rank-up that can be reversed exactly.
function Character:canUndoRankUp()
    return self.rank_gains ~= nil and #self.rank_gains > 0 and self.rank > Rules.MIN_RANK
end

--- Reverses the most recent rank-up exactly, for a mis-tap.
-- @treturn int|nil the Stamina taken back, or nil if there is nothing to undo
function Character:undoRankUp()
    if not self:canUndoRankUp() then return nil end
    local gain = table.remove(self.rank_gains)
    self.rank = self.rank - 1
    self.stamina_max = math.max(1, self.stamina_max - gain)
    self.stamina = math.min(self.stamina, self.stamina_max)
    return gain
end

-- Abilities ----------------------------------------------------------------

--- Adjusts an ability, clamped to 1..12 (p. 7).
-- @treturn int the new score
function Character:adjustAbility(ability, delta)
    self.abilities[ability] = Rules.clampAbility(self.abilities[ability] + delta)
    return self.abilities[ability]
end

-- Possessions --------------------------------------------------------------

function Character:isEncumbered()
    return #self.possessions >= Rules.MAX_POSSESSIONS
end

--- Adds an item, refusing to exceed the 12-item carry limit (p. 6).
-- @treturn bool success
-- @treturn string|nil reason for refusal
function Character:addPossession(item)
    if self:isEncumbered() then
        return false, "You can carry only " .. Rules.MAX_POSSESSIONS .. " possessions."
    end
    table.insert(self.possessions, item)
    return true
end

function Character:removePossession(index)
    return table.remove(self.possessions, index)
end

-- Codewords ----------------------------------------------------------------
-- Codewords persist across books and are never erased when moving between
-- them (p. 7).

function Character:hasCodeword(word)
    local wanted = tostring(word):lower()
    for _, held in ipairs(self.codewords) do
        if held:lower() == wanted then return true end
    end
    return false
end

--- Records a codeword, keeping the list sorted and free of duplicates.
-- @treturn bool false if it was already held
function Character:addCodeword(word)
    word = tostring(word):match("^%s*(.-)%s*$")
    if word == "" or self:hasCodeword(word) then return false end
    table.insert(self.codewords, word)
    table.sort(self.codewords, function(a, b) return a:lower() < b:lower() end)
    return true
end

function Character:removeCodeword(word)
    local wanted = tostring(word):lower()
    for i, held in ipairs(self.codewords) do
        if held:lower() == wanted then
            table.remove(self.codewords, i)
            return true
        end
    end
    return false
end

-- Blessings ----------------------------------------------------------------

--- Adds a blessing. You may hold any number, but never two of the same type
-- (p. 7) -- so a second COMBAT blessing is refused.
-- @tparam table blessing { name = string, ability = string|nil }
-- @treturn bool success
-- @treturn string|nil reason for refusal
function Character:addBlessing(blessing)
    if blessing.ability then
        for _, held in ipairs(self.blessings) do
            if held.ability == blessing.ability then
                return false, "You already have a " .. blessing.ability .. " blessing."
            end
        end
    end
    table.insert(self.blessings, blessing)
    return true
end

function Character:removeBlessing(index)
    return table.remove(self.blessings, index)
end

return Character
