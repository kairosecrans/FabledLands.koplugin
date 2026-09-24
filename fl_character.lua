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
        afflictions = {},
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
    data.afflictions = data.afflictions or {}
    data.rank_gains = data.rank_gains or {}
    data.trail = data.trail or {}
    data.resurrection = data.resurrection or {}
    data.rank = data.rank or 1
    data.shards = data.shards or 0
    data.stamina_max = data.stamina_max or Rules.STARTING_STAMINA
    data.stamina = data.stamina or data.stamina_max
    for _, ability in ipairs(Rules.ABILITIES) do
        data.abilities[ability] = data.abilities[ability] or Rules.ABILITY_MIN
    end
    -- Tidy codewords saved before they were normalised, so an old list reads
    -- the same as a new one.
    for i, word in ipairs(data.codewords) do
        data.codewords[i] = Character.normaliseCodeword(word)
    end
    if data.ship then Character.restoreShip(data.ship) end
    return setmetatable(data, Character)
end

--- Brings a ship saved by 0.3.0 up to the current shape.
--
-- 0.3.0 kept every Manifest field as typed text. Cargo in particular was a
-- description rather than a list of units, so reading it as a list either
-- threw an error or, worse, counted the letters in "timber" as six units.
function Character.restoreShip(ship)
    local function tidy(text)
        text = type(text) == "string" and text:match("^%s*(.-)%s*$") or nil
        return text ~= "" and text or nil
    end
    if type(ship.cargo) == "string" then
        local described = tidy(ship.cargo)
        ship.cargo = described and { described } or {}
    elseif type(ship.cargo) ~= "table" then
        ship.cargo = {}
    end
    ship.capacity = tonumber(ship.capacity)
    -- Lower case, so the type and crew pickers recognise what is stored and
    -- the ship roll can look up its dice.
    ship.type = tidy(ship.type) and tidy(ship.type):lower()
    ship.crew = tidy(ship.crew) and tidy(ship.crew):lower()
    return ship
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

-- Identity -----------------------------------------------------------------

--- Renames a character. Trims, and refuses to leave them nameless.
-- @treturn bool success
function Character:rename(name)
    name = tostring(name):match("^%s*(.-)%s*$")
    if name == "" then return false end
    self.name = name
    return true
end

--- Changes profession without touching the ability scores.
--
-- The scores came from the profession's starting table, but by now they have
-- been raised and lowered in play, so rewriting them would throw away the
-- character. Profession is a label after this point; only the sheet shows it.
-- @treturn bool success
-- @treturn string|nil reason for refusal
function Character:setProfession(profession)
    if not Rules.professionsFor(self.started_in)[profession] then
        return false, "unknown profession: " .. tostring(profession)
    end
    self.profession = profession
    return true
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

--- Normalises a codeword to the way the books print them: one leading capital,
-- the rest lower case. Comparison is case-insensitive either way, so this is
-- purely so the list reads consistently however it was typed.
function Character.normaliseCodeword(word)
    word = tostring(word):match("^%s*(.-)%s*$")
    if word == "" then return "" end
    return word:sub(1, 1):upper() .. word:sub(2):lower()
end

--- Records a codeword, keeping the list sorted and free of duplicates.
-- @treturn bool false if it was already held
function Character:addCodeword(word)
    word = Character.normaliseCodeword(word)
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

-- Where you have been ------------------------------------------------------

--- How many section jumps to remember.
Character.TRAIL_LENGTH = 30

--- Records a section you turned to, so you can get back to it.
--
-- The page is stored alongside, which makes returning instant -- no search --
-- and the document too, because a page number means nothing in a different
-- book. Re-visiting a section moves it to the top rather than duplicating it.
function Character:recordSection(section, page, doc)
    self.trail = self.trail or {}
    for i = #self.trail, 1, -1 do
        local entry = self.trail[i]
        if entry.section == section and entry.doc == doc then
            table.remove(self.trail, i)
        end
    end
    table.insert(self.trail, { section = section, page = page, doc = doc })

    -- Trim per document, not globally: reading deeply into one book must not
    -- silently evict the trail you left in another.
    local seen = 0
    for i = #self.trail, 1, -1 do
        if self.trail[i].doc == doc then
            seen = seen + 1
            if seen > Character.TRAIL_LENGTH then table.remove(self.trail, i) end
        end
    end
end

--- The sections visited in a given book, most recent first.
-- Filtered by document: jumping to a page recorded in another book would
-- land somewhere meaningless.
function Character:sectionTrail(doc)
    local out = {}
    for i = #(self.trail or {}), 1, -1 do
        local entry = self.trail[i]
        if entry.doc == doc then out[#out + 1] = entry end
    end
    return out
end

--- Moves the trail recorded under one document key to another, for when
-- the way books are identified changes. Returns how many entries moved.
function Character:rekeyTrail(from, to)
    if not self.trail or from == to then return 0 end
    local moved = 0
    for _, entry in ipairs(self.trail) do
        if entry.doc == from then
            entry.doc = to
            moved = moved + 1
        end
    end
    if moved == 0 then return 0 end

    -- The book may have gathered a trail under both keys. Keep the most
    -- recent visit to each section, and keep within the length limit.
    local seen, kept = {}, 0
    for i = #self.trail, 1, -1 do
        local entry = self.trail[i]
        if entry.doc == to then
            if seen[entry.section] or kept >= Character.TRAIL_LENGTH then
                table.remove(self.trail, i)
            else
                seen[entry.section] = true
                kept = kept + 1
            end
        end
    end
    return moved
end

function Character:clearTrail(doc)
    if not self.trail then return end
    for i = #self.trail, 1, -1 do
        if self.trail[i].doc == doc then table.remove(self.trail, i) end
    end
end

-- Your god, and dying -------------------------------------------------------

--- Sets the god in the God box. One at a time; the books have you renounce
-- one before taking up another, so naming a different god (or clearing the
-- box) renounces the old one, arrangements and all.
-- @treturn string|nil the god now worshipped
-- @treturn int how many resurrection arrangements that gave up
function Character:setGod(name)
    local lost = self:godChangeCost(name)
    if lost > 0 then self.resurrection = {} end
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    self.god = name ~= "" and name or nil
    return self.god, lost
end

--- How many resurrection arrangements setting `name` would give up, so the
-- caller can ask first. Naming a first god, or retyping the current one in
-- different case, costs nothing.
function Character:godChangeCost(name)
    if not self.god then return 0 end
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name:lower() == self.god:lower() then return 0 end
    return self:arrangementCount()
end

--- Renouncing a god costs any outstanding resurrection arrangements, since
-- those were made with that god's temple. Returns how many are at stake so
-- the caller can say so before doing it.
function Character:arrangementCount()
    return #(self.resurrection or {})
end

function Character:renounceGod()
    local lost = self:arrangementCount()
    self.god = nil
    self.resurrection = {}
    return lost
end

--- Records a resurrection deal: where it was made, and the section to turn to
-- if you die. The section is what you actually need at the time, and it is
-- the thing hardest to remember.
function Character:addResurrection(where, section)
    where = tostring(where):match("^%s*(.-)%s*$")
    if where == "" then return false end
    self.resurrection = self.resurrection or {}
    table.insert(self.resurrection, { where = where, section = tonumber(section) })
    return true
end

function Character:removeResurrection(index)
    return table.remove(self.resurrection or {}, index)
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

-- Curses, diseases and poisons --------------------------------------------

--- Records an affliction and takes its toll on your abilities.
--
-- The books word these as "lose 1 point from your CHARISMA and COMBAT until
-- the curse is lifted", so this does exactly that to the scores themselves.
-- Rolls, fights and Defence then follow without knowing afflictions exist.
-- What was actually taken is kept, since a score already at 1 cannot lose
-- anything, and a cure should not hand back points that were never lost.
-- @tparam string name
-- @tparam table penalties { ABILITY = points, ... }, may be empty
-- @treturn table|nil the affliction as recorded, or nil for a blank name
function Character:addAffliction(name, penalties)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then return nil end
    local taken = {}
    for _, ability in ipairs(Rules.ABILITIES) do
        local points = tonumber((penalties or {})[ability]) or 0
        if points > 0 then
            local before = self.abilities[ability]
            self.abilities[ability] = Rules.clampAbility(before - points)
            if before - self.abilities[ability] > 0 then
                taken[ability] = before - self.abilities[ability]
            end
        end
    end
    local affliction = { name = name, penalties = taken }
    table.insert(self.afflictions, affliction)
    return affliction
end

--- Cures an affliction, giving back what it took.
function Character:cureAffliction(index)
    local affliction = table.remove(self.afflictions, index)
    if not affliction then return nil end
    for ability, points in pairs(affliction.penalties or {}) do
        if self.abilities[ability] then
            self.abilities[ability] = Rules.clampAbility(self.abilities[ability] + points)
        end
    end
    return affliction
end

return Character
