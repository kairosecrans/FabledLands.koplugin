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

local Badge = require("fl_badge")
local Character = require("fl_character")
local Combat = require("fl_combat")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Format = require("fl_format")
local Inventory = require("fl_inventory")
local LuaSettings = require("luasettings")
local logger = require("logger")
local Prompts = require("fl_prompts")
local Rules = require("fl_rules")
local Sections = require("fl_sections")
local UIManager = require("ui/uimanager")
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
    -- Register the menu entry first, and never behind anything that can fail.
    -- Everything below touches the filesystem, the dispatcher or the widget
    -- stack, any of which might behave differently on a KOReader build this
    -- has not been tried against. If one of them throws while registration is
    -- still pending, the plugin loads with no way to reach it -- which is
    -- indistinguishable, from the outside, from not loading at all.
    self.ui.menu:registerToMainMenu(self)

    local ok, err = pcall(function()
        self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/fabledlands.lua")
        self.roster = self.settings:readSetting("characters", {})
        self.active = self.settings:readSetting("active", 1)
        self:useCharacter(self.active)
        self:onDispatcherRegisterActions()
    end)
    if not ok then
        -- Recorded rather than swallowed: the menu entry reports it, so a
        -- failure is visible instead of silent.
        self.startup_error = tostring(err)
        logger.warn("Fabled Lands: startup failed:", err)
        self.roster = self.roster or {}
    end

    -- The badge is the most version-sensitive part of the plugin, so it is
    -- kept out of the path that everything else depends on.
    if self.settings then
        local fine, oops = pcall(function()
            self.minimized = self.settings:readSetting("minimized")
            if self.minimized then self:showBadge() end
        end)
        if not fine then
            self.minimized = nil
            logger.warn("Fabled Lands: could not restore the badge:", oops)
        end
    end
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
    if not self.settings then return end
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
    -- Worth binding to a gesture: it reopens whatever you minimized, without
    -- the stray page turn a tap on the badge can cause.
    Dispatcher:registerAction("fabledlands_section", {
        category = "none",
        event = "FabledLandsSection",
        title = _("Fabled Lands: turn to section"),
        general = true,
    })
    Dispatcher:registerAction("fabledlands_restore", {
        category = "none",
        event = "FabledLandsRestore",
        title = _("Fabled Lands: restore minimized"),
        general = true,
    })
end

-- Turning to a section -----------------------------------------------------

--- Asks for a section number and jumps to the page it is printed on.
--
-- Section numbers are not page numbers, so this binary-searches the book's
-- own text. It needs a text layer: a scan without OCR, or a reflowable EPUB
-- with no printed markers, will find nothing, and the failure says so rather
-- than jumping somewhere arbitrary.
function FabledLands:turnToSection()
    if not (self.ui and self.ui.document) then
        Prompts.info(_("Open a gamebook first."))
        return
    end
    local doc = self:documentName()
    local trail = self.character and self.character:sectionTrail(doc) or {}

    local items = { {
        text = _("Enter a section number"),
        callback = function() self:askSection() end,
    } }
    -- Somewhere you have already been needs no search: the page was recorded
    -- the first time, so going back is immediate.
    for _i, entry in ipairs(trail) do
        table.insert(items, {
            text = ("Section %d   (page %d)"):format(entry.section, entry.page),
            callback = function()
                self.ui:handleEvent(Event:new("GotoPage", entry.page))
            end,
        })
    end
    if #trail > 0 then
        table.insert(items, {
            text = _("Forget this book's trail"),
            callback = function()
                Prompts.confirm{
                    text = _("Forget the sections visited in this book?"),
                    ok_text = _("Forget"),
                    ok_callback = function()
                        self.character:clearTrail(doc)
                        self:save()
                        self:turnToSection()
                    end,
                    cancel_callback = function() self:turnToSection() end,
                }
            end,
        })
    end

    Prompts.menu{
        title = #trail > 0
            and _("Turn to section\n\nRecently visited, most recent first:")
            or _("Turn to section"),
        items = items,
        close_callback = function() self:showSheet() end,
    }
end

--- The document's filename, used to keep one book's trail out of another's.
function FabledLands:documentName()
    local file = self.ui and self.ui.document and self.ui.document.file
    return file and file:match("([^/]+)$") or "?"
end

function FabledLands:askSection()
    -- A typed field, not a spinner: these numbers run to three digits and
    -- nobody wants to tap an arrow four hundred times.
    Prompts.text{
        title = _("Turn to section"),
        description = _("The number the book tells you to turn to."),
        hint = "412",
        input_type = "number",
        ok_text = _("Go"),
        callback = function(text)
            local target = tonumber(text)
            if not target or target < 1 or target > Sections.MAX_SECTION then
                Prompts.info(_("That is not a section number."))
                return
            end
            self.last_section = target
            self:jumpToSection(target)
        end,
    }
end

--- Searches for the section and goes there. No confirmation: the whole point
-- is to replace flipping pages, and a dialog in the way defeats that.
--
-- A nearest match just moves. It goes to the log rather than the screen: you
-- can see for yourself whether the page is right, so saying so on top of the
-- page you asked for is noise.
function FabledLands:jumpToSection(target)
    local found
    local ok = pcall(function() found = Sections.find(self.ui.document, target) end)

    if not ok or not found then
        Prompts.info(_([[Could not read section numbers from this book.

It needs a text layer -- a scan that has been through OCR. Use the reader's own "Go to page" instead.]]))
        return
    end

    if self.character then
        self.character:recordSection(target, found.page, self:documentName())
        self:save()
    end
    self.ui:handleEvent(Event:new("GotoPage", found.page))

    if not found.exact then
        logger.info("Fabled Lands: section", target,
            "not found; nearest page", found.page, "after", found.reads, "reads")
    end
end

-- Minimizing ---------------------------------------------------------------

--- Hides the plugin behind a small floating badge, remembering exactly how to
-- come back. Any screen can call this: it hands over a closure that reopens
-- itself, so a half-typed stat block or a deep list comes back as it was.
--
-- The closure cannot survive a restart, so a plain name is stored alongside
-- it; after a restart the badge reappears and falls back to that screen.
-- @func reopen called on restore to rebuild the screen
-- @string name coarse fallback: "combat" or "sheet"
function FabledLands:minimize(reopen, name)
    self.reopen = reopen
    self.minimized = name or "sheet"
    if self.settings then
        self.settings:saveSetting("minimized", self.minimized)
        self.settings:flush()
    end
    self:showBadge()
end

function FabledLands:showBadge()
    self:hideBadge()
    if not self.minimized or not self.character then return end

    self.badge = Badge:new{
        text = Format.badge(self.character, self.character.fight),
        on_tap = function() self:restore() end,
    }
    -- The refresh type matters: show() without one queues the widget but
    -- never actually paints it, so the badge would be invisible.
    UIManager:show(self.badge, "ui", self.badge.dimen)
end

function FabledLands:hideBadge()
    if self.badge then
        UIManager:close(self.badge)
        self.badge = nil
    end
end

--- Undoes the page turn a badge tap causes in passing.
--
-- A toast never stops event propagation -- that is the whole reason page
-- turns still work while the badge is up -- but it means the tap that
-- restores also reaches the reader and moves the page. So note where we
-- were, let the turn happen, then put it back on the next tick.
function FabledLands:keepPagePut()
    if not (self.ui and self.ui.document and self.ui.getCurrentPage) then return end
    local ok, before = pcall(function() return self.ui:getCurrentPage() end)
    if not ok or not before then return end

    UIManager:nextTick(function()
        local fine, after = pcall(function() return self.ui:getCurrentPage() end)
        if fine and after and after ~= before then
            self.ui:handleEvent(Event:new("GotoPage", before))
        end
    end)
end

--- Reopens exactly the screen that was minimized.
function FabledLands:restore()
    local reopen, screen = self.reopen, self.minimized
    self.reopen, self.minimized = nil, nil
    if self.settings then
        self.settings:delSetting("minimized")
        self.settings:flush()
    end
    self:keepPagePut()
    self:hideBadge()

    if reopen then
        -- Same session: rebuild the exact screen, partial input and all.
        reopen()
    elseif screen == "combat" and self.character and self.character.fight then
        -- After a restart the closure is gone, so fall back to the fight.
        Combat.show(self)
    else
        self:showSheet()
    end
end

function FabledLands:onFabledLandsSection()
    -- Straight to the input. The menu with the history behind it is reachable
    -- from the Adventure Sheet; a gesture mid-read wants the fewest taps.
    if self.ui and self.ui.document then
        self:askSection()
    else
        Prompts.info(_("Open a gamebook first."))
    end
    return true
end

function FabledLands:onFabledLandsRestore()
    if self.minimized then
        self:restore()
    else
        self:showSheet()
    end
    return true
end

--- The badge must be torn down with the document, or it would paint over the
-- file manager after the book closes.
function FabledLands:onCloseWidget()
    self:hideBadge()
end

--- Returns `wanted` only if this build's menu actually has such a section.
--
-- MenuSorter does not tolerate an unknown sorting_hint: it looks the hint up,
-- gets nil back, and immediately indexes the result, so the entry is lost.
-- With no hint at all the item is appended to the first tab instead, which
-- always works. Menu sections get renamed between KOReader versions, and a
-- plugin you cannot reach is worse than one in a slightly odd place -- so the
-- hint is used only once it has been confirmed present.
local function existingSection(is_reader, wanted)
    local module = is_reader and "ui/elements/reader_menu_order"
        or "ui/elements/filemanager_menu_order"
    local ok, order = pcall(require, module)
    if ok and type(order) == "table" and order[wanted] ~= nil then
        return wanted
    end
    logger.warn("Fabled Lands: no", wanted, "menu section on this build; using the default")
    return nil
end

function FabledLands:addToMainMenu(menu_items)
    -- One location, both contexts. An earlier version put this in the reader's
    -- navigation tab to save taps while reading, which was a mistake: the same
    -- plugin then lived in two different places depending on whether a book
    -- was open, and "it moved" is indistinguishable from "it broke". Bind a
    -- gesture to the dispatcher actions if you want it faster than a menu.
    menu_items.fabled_lands = {
        text = _("Fabled Lands"),
        sorting_hint = existingSection(self.ui.document ~= nil, "more_tools"),
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
    if self.startup_error then
        Prompts.panel{
            title = ("Fabled Lands could not start up.\n\n%s\n\nPlease report this with your KOReader version."):format(self.startup_error),
            buttons = {},
        }
        return
    end
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
            {
                {
                    text = _("Turn to section"),
                    enabled = self.ui.document ~= nil,
                    callback = function() self:turnToSection() end,
                },
                {
                    text = _("Minimize"),
                    callback = function()
                        self:minimize(function() self:showSheet() end, "sheet")
                    end,
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
            {
                text = character:canUndoRankUp()
                    and _("Undo the last Rank gain")
                    or ("Go down to %s Rank"):format(Rules.ordinal(character.rank - 1)),
                enabled = character.rank > Rules.MIN_RANK,
                callback = function()
                    -- Undoing a mis-tap and suffering a Rank loss are different
                    -- things: one puts back exactly what was taken, the other
                    -- rolls a fresh die. Offer the undo while it is available,
                    -- since that is the case people hit by accident.
                    if character:canUndoRankUp() then
                        self:undoRankUp()
                    else
                        self:rankDown()
                    end
                end,
                hold_callback = function() self:rankDown() end,
            },
            { text = _("Name and profession"), callback = function() self:editIdentity() end },
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

--- Correcting a name or profession after the fact.
--
-- Changing profession leaves the ability scores alone: they started from the
-- profession's table but have been raised and lowered in play since, so
-- rewriting them would discard the character.
function FabledLands:editIdentity()
    local character = self.character
    local back = function() self:editIdentity() end

    Prompts.menu{
        title = ("%s\n%s"):format(character.name ~= "" and character.name or _("(unnamed)"),
            character.profession or "?"),
        items = {
            {
                text = _("Rename"),
                callback = function()
                    Prompts.text{
                        title = _("What is your character called?"),
                        value = character.name,
                        ok_text = _("Rename"),
                        callback = function(name)
                            if character:rename(name) then
                                self:save()
                            else
                                Prompts.info(_("A character needs a name."))
                            end
                            back()
                        end,
                    }
                end,
            },
            {
                text = _("Change profession"),
                callback = function()
                    local items = {}
                    for _i, profession in ipairs(Rules.PROFESSION_NAMES) do
                        table.insert(items, {
                            text = profession,
                            callback = function()
                                local ok, err = character:setProfession(profession)
                                if not ok then Prompts.info(err) else self:save() end
                                back()
                            end,
                        })
                    end
                    Prompts.menu{
                        title = _("Change profession\n\nYour ability scores are left as they are."),
                        items = items,
                        close_callback = back,
                    }
                end,
            },
        },
        close_callback = function() self:showSheet() end,
    }
end

--- Losing a Rank, as the books sometimes impose (Book 4): -1 Rank and a die's
-- worth of Stamina, lost permanently.
function FabledLands:rankDown()
    local character = self.character
    Prompts.confirm{
        text = ("Go down to %s Rank?\n\nYou will roll one die for the Stamina you lose permanently. This is the rule the books impose, not an undo.")
            :format(Rules.ordinal(character.rank - 1)),
        ok_text = _("Lose a Rank"),
        ok_callback = function()
            local loss, err = character:rankDown()
            if not loss then
                Prompts.info(err)
                self:showSheet()
                return
            end
            self:save()
            Prompts.panel{
                title = ("You are now %s Rank, a %s.\n\nYou rolled %d, so your Stamina falls to %d/%d.\nYour Defence is now %d.")
                    :format(Rules.ordinal(character.rank), character:rankTitle(),
                        loss, character.stamina, character.stamina_max, character:defence()),
                buttons = {},
                close_text = _("Onward"),
                close_callback = function() self:showSheet() end,
            }
        end,
        cancel_callback = function() self:showSheet() end,
    }
end

--- Puts back exactly what the last rank-up gave, for a mis-tap.
function FabledLands:undoRankUp()
    local character = self.character
    Prompts.confirm{
        text = ("Undo the last Rank gain, back to %s Rank?\n\nThis takes back exactly the Stamina it gave, rather than rolling again.")
            :format(Rules.ordinal(character.rank - 1)),
        ok_text = _("Undo"),
        ok_callback = function()
            local gain = character:undoRankUp()
            self:save()
            Prompts.info(gain
                and ("Back to %s Rank; %d Stamina taken back (now %d/%d)."):format(
                    Rules.ordinal(character.rank), gain, character.stamina, character.stamina_max)
                or _("There was no Rank gain to undo."))
            self:showSheet()
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

    table.insert(items, {
        text = _("Minimize"),
        callback = function()
            self:minimize(function() self:showRoll() end, "sheet")
        end,
    })

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
        }, {
            {
                text = _("Minimize"),
                callback = function()
                    self:minimize(function() self:rollAbility(ability, difficulty) end, "sheet")
                end,
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

            self:chooseStartingBook(name)
        end,
    }
end

--- Which book you are starting in. A later one begins you further along, so
-- this has to come before the profession table -- the scores differ.
function FabledLands:chooseStartingBook(name)
    local items = {}
    for book = 1, #Rules.STARTING_BOOKS do
        local start = Rules.STARTING_BOOKS[book]
        table.insert(items, {
            text = ("Book %d  --  %s Rank, %d Stamina"):format(
                book, Rules.ordinal(start.rank), start.stamina),
            callback = function() self:chooseProfession(name, book) end,
        })
    end
    Prompts.menu{
        title = ("%s\n\n%s"):format(name,
            _("Which book are you starting in?\nA later one starts you further along.")),
        items = items,
        close_callback = function() self:showSheet() end,
    }
end

function FabledLands:chooseProfession(name, book)
    -- Two names per row: the comparison table lives in the title, so the
    -- buttons only have to carry a profession name.
    local rows, row = {}, {}
    for _i, profession in ipairs(Rules.PROFESSION_NAMES) do
        table.insert(row, {
            text = profession,
            callback = function()
                local character, err = Character.create(name, profession, book)
                if not character then
                    Prompts.info(err)
                    return
                end
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
        title = ("%s\n\n%s\n\n%s"):format(Format.startingBook(book),
            Format.professionTable(book), _("Choose a profession.")),
        buttons = rows,
        close_callback = function() self:showSheet() end,
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
