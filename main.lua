--[[--
Fabled Lands: an Adventure Sheet and combat tracker for the gamebook series
by Dave Morris and Jamie Thomson.

Keeps the character sheet, rolls the dice and runs fights round by round, so
the only thing left to do by hand is turn to the right section.

One persona travels the whole series, so characters are stored globally
rather than against a document -- and codewords, which are explicitly never
erased when you move between books, come along with them.

@module koplugin.FabledLands
--]]--

local Character = require("fl_character")
local Combat = require("fl_combat")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Format = require("fl_format")
local Inventory = require("fl_inventory")
local LuaSettings = require("luasettings")
local Prompts = require("fl_prompts")
local Rules = require("fl_rules")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

-- Seeds math.random from the clock. Without this the dice would roll the same
-- sequence after every restart, and nothing else guarantees it is loaded.
require("random")

local FabledLands = WidgetContainer:extend{
    name = "fabledlands",
    is_doc_only = false,
}

function FabledLands:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/fabledlands.lua")
    self.roster = self.settings:readSetting("characters", {})
    self.active = self.settings:readSetting("active", 1)
    self:useCharacter(self.active)

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

-- Persistence --------------------------------------------------------------

--- Points self.character at a roster slot, reattaching its behaviour.
function FabledLands:useCharacter(index)
    self.active = index
    local data = self.roster[index]
    self.character = data and Character.restore(data) or nil
    if self.character then
        self.roster[index] = self.character
    end
end

--- Writes the roster to disk. Called after every change, because losing an
-- hour of adventuring to a crash would be worse than a few extra writes.
function FabledLands:save()
    self.settings:saveSetting("characters", self.roster)
    self.settings:saveSetting("active", self.active)
    self.settings:flush()
end

-- Menu and gestures --------------------------------------------------------

function FabledLands:onDispatcherRegisterActions()
    Dispatcher:registerAction("fabledlands_sheet", {
        category = "none",
        event = "FabledLandsSheet",
        title = _("Fabled Lands: Adventure Sheet"),
        general = true,
    })
    Dispatcher:registerAction("fabledlands_roll", {
        category = "none",
        event = "FabledLandsRoll",
        title = _("Fabled Lands: ability roll"),
        general = true,
    })
end

function FabledLands:addToMainMenu(menu_items)
    menu_items.fabled_lands = {
        text = _("Fabled Lands"),
        sorting_hint = "more_tools",
        callback = function() self:showSheet() end,
    }
end

function FabledLands:onFabledLandsSheet()
    self:showSheet()
    return true
end

function FabledLands:onFabledLandsRoll()
    if self.character then
        self:showRoll()
    else
        self:showSheet()
    end
    return true
end

-- The Adventure Sheet ------------------------------------------------------

function FabledLands:showSheet()
    if not self.character then
        self:showWelcome()
        return
    end
    local character = self.character
    local fighting = character.fight ~= nil

    Prompts.panel{
        title = Format.sheet(character),
        buttons = {
            {
                {
                    text = _("Ability roll"),
                    callback = function() self:showRoll() end,
                },
                {
                    text = fighting and _("Resume fight") or _("Fight"),
                    callback = function() Combat.show(self) end,
                },
            },
            {
                {
                    text = _("Stamina"),
                    callback = function() Inventory.stamina(self) end,
                },
                {
                    text = _("Possessions"),
                    callback = function() Inventory.possessions(self) end,
                },
            },
            {
                {
                    text = _("Codewords"),
                    callback = function() Inventory.codewords(self) end,
                },
                {
                    text = _("More"),
                    callback = function() self:showMore() end,
                },
            },
        },
    }
end

function FabledLands:showMore()
    local character = self.character
    local back = function() self:showSheet() end

    Prompts.menu{
        title = _("Adventure Sheet"),
        items = {
            { text = _("Abilities"), callback = function() Inventory.abilities(self) end },
            { text = _("Money"), callback = function() Inventory.money(self) end },
            { text = _("Titles and honours"), callback = function() Inventory.titles(self) end },
            { text = _("Blessings"), callback = function() Inventory.blessings(self) end },
            { text = _("Ship's Manifest"), callback = function() Inventory.ship(self) end },
            { text = _("Notes"), callback = function() Inventory.notes(self) end },
            {
                text = ("Go up to %s Rank"):format(Rules.ordinal(character.rank + 1)),
                callback = function() self:rankUp() end,
            },
            { text = _("Characters"), callback = function() self:showCharacters() end },
        },
        close_callback = back,
    }
end

--- Advancing a Rank: +1 Rank and 1d6 Stamina, gained permanently (p. 6).
function FabledLands:rankUp()
    local character = self.character
    Prompts.confirm{
        text = ("Go up to %s Rank?\n\nYou will roll one die for the Stamina you gain permanently.")
            :format(Rules.ordinal(character.rank + 1)),
        ok_text = _("Advance"),
        ok_callback = function()
            local gain = character:rankUp()
            self:save()
            Prompts.panel{
                title = ("You are now %s Rank, a %s.\n\nYou rolled %d, so your Stamina rises to %d/%d.\nYour Defence is now %d.")
                    :format(Rules.ordinal(character.rank), character:rankTitle(),
                        gain, character.stamina, character.stamina_max, character:defence()),
                buttons = {},
                close_text = _("Onward"),
                close_callback = function() self:showSheet() end,
            }
        end,
        cancel_callback = function() self:showSheet() end,
    }
end

-- Ability rolls ------------------------------------------------------------

function FabledLands:showRoll()
    local character = self.character
    local items = {}

    for _i, ability in ipairs(Rules.ABILITIES) do
        local bonus = character:itemBonus(ability)
        table.insert(items, {
            text = bonus > 0
                and ("%s  %d +%d"):format(ability, character.abilities[ability], bonus)
                or ("%s  %d"):format(ability, character.abilities[ability]),
            callback = function() self:askDifficulty(ability) end,
        })
    end

    Prompts.menu{
        title = _("Which ability is the book asking for?"),
        items = items,
        close_callback = function() self:showSheet() end,
    }
end

function FabledLands:askDifficulty(ability)
    Prompts.number{
        title = ("%s roll"):format(ability),
        info = _("Difficulty given in the book"),
        value = self.last_difficulty or 9,
        min = 2,
        max = 25,
        ok_text = _("Roll"),
        callback = function(difficulty)
            self.last_difficulty = difficulty
            self:rollAbility(ability, difficulty)
        end,
    }
end

function FabledLands:rollAbility(ability, difficulty)
    local result = self.character:check(ability, difficulty)
    Prompts.panel{
        title = Format.check(ability, result),
        buttons = { {
            {
                text = _("Roll again"),
                callback = function() self:rollAbility(ability, difficulty) end,
            },
            {
                text = _("Another ability"),
                callback = function() self:showRoll() end,
            },
        } },
        close_text = _("Adventure Sheet"),
        close_callback = function() self:showSheet() end,
    }
end

-- Characters ---------------------------------------------------------------

function FabledLands:showWelcome()
    Prompts.panel{
        title = _([[Fabled Lands

No character yet. Create one and it will travel with you through every book in the series.]]),
        buttons = { { {
            text = _("Create a character"),
            callback = function() self:createCharacter() end,
        } } },
    }
end

function FabledLands:showCharacters()
    local items = {}
    for index, data in ipairs(self.roster) do
        local who = Character.restore(data)
        table.insert(items, {
            text = ("%s%s -- %s, %s"):format(
                index == self.active and "> " or "   ",
                who.name ~= "" and who.name or _("(unnamed)"),
                who.profession or "?", Format.rank(who)),
            callback = function()
                self:useCharacter(index)
                self:save()
                self:showSheet()
            end,
        })
    end

    table.insert(items, {
        text = _("Create a character"),
        callback = function() self:createCharacter() end,
    })
    if self.character then
        table.insert(items, {
            text = _("Delete the current character"),
            callback = function() self:deleteCharacter() end,
        })
    end

    Prompts.menu{
        title = _("Characters"),
        items = items,
        close_callback = function() self:showSheet() end,
    }
end

function FabledLands:createCharacter()
    Prompts.text{
        title = _("What is your character called?"),
        hint = _("Andriel the Hammer"),
        ok_text = _("Next"),
        callback = function(name)
            name = name:match("^%s*(.-)%s*$")
            if name == "" then name = _("Adventurer") end

            -- Two names per row: the comparison table lives in the title, so
            -- the buttons only have to carry a profession name.
            local rows, row = {}, {}
            for _i, profession in ipairs(Rules.PROFESSION_NAMES) do
                table.insert(row, {
                    text = profession,
                    callback = function()
                        local character = Character.create(name, profession)
                        table.insert(self.roster, character)
                        self:useCharacter(#self.roster)
                        self:save()
                        self:showSheet()
                    end,
                })
                if #row == 2 then
                    table.insert(rows, row)
                    row = {}
                end
            end
            if #row > 0 then table.insert(rows, row) end

            Prompts.panel{
                title = ("%s\n\n%s\n\n%s"):format(name, Format.professionTable(),
                    _("Choose a profession.")),
                buttons = rows,
                close_callback = function() self:showSheet() end,
            }
        end,
    }
end

function FabledLands:deleteCharacter()
    local name = self.character.name
    Prompts.confirm{
        text = ("Delete %s for good?\n\nThe sheet, possessions and codewords all go with them."):format(
            name ~= "" and name or _("this character")),
        ok_text = _("Delete"),
        ok_callback = function()
            table.remove(self.roster, self.active)
            self:useCharacter(math.min(self.active, #self.roster))
            self:save()
            self:showSheet()
        end,
        cancel_callback = function() self:showCharacters() end,
    }
end

return FabledLands
