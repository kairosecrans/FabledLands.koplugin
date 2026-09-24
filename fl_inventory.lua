--[[--
Editors for the parts of the Adventure Sheet you write in with a pencil:
possessions and money, codewords, titles, blessings, curses and diseases,
the Ship's Manifest, Stamina and abilities.

Every screen returns to the one that opened it, so the whole thing behaves
like a stack of sheets rather than a maze.

@module koplugin.FabledLands.inventory
--]]--

local Format = require("fl_format")
local Prompts = require("fl_prompts")
local Rules = require("fl_rules")
local _ = require("gettext")

local Inventory = {}

local describeItem = Format.item

-- Possessions --------------------------------------------------------------

--- Asks what a new item does, then adds it.
local function askItemEffect(plugin, name, back)
    local character = plugin.character

    local function add(item)
        local ok, err = character:addPossession(item)
        if not ok then
            Prompts.info(err)
        else
            plugin:save()
        end
        back()
    end

    Prompts.menu{
        title = ("%s\n\n%s"):format(name, _("What does it do?")),
        items = {
            {
                text = _("Nothing special"),
                callback = function() add({ name = name }) end,
            },
            {
                text = _("Gives an ability bonus"),
                callback = function()
                    local abilities = {}
                    for _i, ability in ipairs(Rules.ABILITIES) do
                        table.insert(abilities, {
                            text = ability,
                            callback = function()
                                Prompts.number{
                                    title = ("%s %s"):format(name, ability),
                                    info = _("How big is the bonus?"),
                                    value = 1, min = 1, max = 6,
                                    ok_text = _("Add"),
                                    cancel_callback = back,
                                    callback = function(bonus)
                                        add({ name = name, ability = ability, bonus = bonus })
                                    end,
                                }
                            end,
                        })
                    end
                    Prompts.menu{
                        title = _("Which ability?"),
                        items = abilities,
                        close_callback = back,
                    }
                end,
            },
            {
                text = _("Restores Stamina when used"),
                callback = function()
                    Prompts.menu{
                        title = ("%s\n\n%s"):format(name, _("How much Stamina does it restore?")),
                        items = {
                            {
                                text = _("All of it"),
                                callback = function() add({ name = name, heals = "all" }) end,
                            },
                            {
                                text = _("A set amount"),
                                callback = function()
                                    Prompts.number{
                                        title = name,
                                        info = _("Stamina restored"),
                                        value = 5, min = 1, max = 50,
                                        ok_text = _("Add"),
                                        cancel_callback = back,
                                        callback = function(amount)
                                            add({ name = name, heals = amount })
                                        end,
                                    }
                                end,
                            },
                        },
                        close_callback = back,
                    }
                end,
            },
            {
                text = _("It is armour"),
                callback = function()
                    Prompts.number{
                        title = ("%s"):format(name),
                        info = _("Defence bonus"),
                        value = 1, min = 1, max = 6,
                        ok_text = _("Add"),
                        cancel_callback = back,
                        callback = function(defence)
                            add({ name = name, defence = defence })
                        end,
                    }
                end,
            },
        },
        close_callback = back,
    }
end

--- Asks for an amount of Shards. Typed, not a spinner: a purse runs to
-- hundreds.
local function askShards(plugin, title, value, ok_text, apply, back)
    Prompts.text{
        title = title,
        value = value,
        input_type = "number",
        ok_text = ok_text,
        cancel_callback = back,
        callback = function(text)
            local amount = tonumber(text)
            if not amount or amount < 0 or amount ~= math.floor(amount) then
                Prompts.info(_("That is not a number of Shards."))
            else
                apply(amount)
                plugin:save()
            end
            back()
        end,
    }
end

--- Possessions, with money on the same screen: buying and selling touch
--- both, so they belong together.
function Inventory.possessions(plugin)
    local character = plugin.character
    local back = function() Inventory.possessions(plugin) end
    local items = {}

    for index, item in ipairs(character.possessions) do
        table.insert(items, {
            text = describeItem(item),
            callback = function()
                local actions = {}
                if item.heals then
                    table.insert(actions, {
                        text = _("Use it"),
                        callback = function()
                            local gained = character:useItem(index)
                            plugin:save()
                            Prompts.info(("You regain %d Stamina, and %s is used up."):format(gained, item.name))
                            back()
                        end,
                    })
                end
                table.insert(actions, {
                    text = _("Drop it"),
                    callback = function()
                        character:removePossession(index)
                        plugin:save()
                        back()
                    end,
                })
                Prompts.menu{
                    title = describeItem(item),
                    items = actions,
                    close_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Pick something up"),
        callback = function()
            if character:isEncumbered() then
                Prompts.info(("You are already carrying %d possessions."):format(Rules.MAX_POSSESSIONS))
                back()
                return
            end
            Prompts.text{
                title = _("What have you found?"),
                hint = _("rune-engraved trident"),
                ok_text = _("Next"),
                cancel_callback = back,
                callback = function(name)
                    name = name:match("^%s*(.-)%s*$")
                    if name == "" then back() return end
                    askItemEffect(plugin, name, back)
                end,
            }
        end,
    })

    table.insert(items, {
        text = _("Minimize"),
        enabled = plugin:canMinimize(),
        callback = function() plugin:minimize(back, "sheet") end,
    })

    local function adjust(title, ok_text, sign)
        askShards(plugin, title, "", ok_text, function(amount)
            character.shards = math.max(0, character.shards + sign * amount)
        end, back)
    end

    local rows = { {
        {
            text = _("Gain"),
            callback = function() adjust(_("Gain how many Shards?"), _("Gain"), 1) end,
        },
        {
            text = _("Spend"),
            callback = function() adjust(_("Spend how many Shards?"), _("Spend"), -1) end,
        },
        {
            text = _("Set"),
            callback = function()
                askShards(plugin, _("How many Shards do you have?"), tostring(character.shards),
                    _("Set"), function(value) character.shards = value end, back)
            end,
        },
    } }
    for _i, item in ipairs(items) do table.insert(rows, { item }) end

    Prompts.panel{
        -- Money last, so its line sits directly above its buttons.
        title = ("%s  %d/%d\n%s\n\n%s  %d Shards"):format(
            _("Possessions"), #character.possessions, Rules.MAX_POSSESSIONS,
            _("Only your best weapon and armour count."),
            _("Money"), character.shards),
        buttons = rows,
        close_callback = function() plugin:showSheet() end,
    }
end

-- Codewords ----------------------------------------------------------------

function Inventory.codewords(plugin)
    local character = plugin.character
    local back = function() Inventory.codewords(plugin) end
    local items = {}

    for _i, word in ipairs(character.codewords) do
        local book = Rules.codewordBook(word)
        table.insert(items, {
            text = book and ("%s  (Book %d)"):format(word, book) or word,
            callback = function()
                Prompts.confirm{
                    text = ("Erase the codeword %s?"):format(word),
                    ok_text = _("Erase"),
                    ok_callback = function()
                        character:removeCodeword(word)
                        plugin:save()
                        back()
                    end,
                    cancel_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Record a codeword"),
        callback = function()
            Prompts.text{
                title = _("Which codeword have you gained?"),
                hint = _("Deliver"),
                ok_text = _("Record"),
                cancel_callback = back,
                callback = function(word)
                    if not character:addCodeword(word) then
                        Prompts.info(_("You already have that codeword."))
                    else
                        plugin:save()
                    end
                    back()
                end,
            }
        end,
    })

    table.insert(items, {
        text = _("Do I have a codeword?"),
        callback = function()
            Prompts.text{
                title = _("Which codeword is the book asking about?"),
                hint = _("Artefact"),
                ok_text = _("Check"),
                cancel_callback = back,
                callback = function(word)
                    word = word:match("^%s*(.-)%s*$")
                    if word == "" then back() return end
                    Prompts.info(character:hasCodeword(word)
                        and ("Yes -- you have %s."):format(word)
                        or ("No -- you do not have %s."):format(word))
                    back()
                end,
            }
        end,
    })

    table.insert(items, {
        text = _("Minimize"),
        enabled = plugin:canMinimize(),
        callback = function() plugin:minimize(back, "sheet") end,
    })

    Prompts.menu{
        title = ("%s  (%d)\n\n%s"):format(_("Codewords"), #character.codewords,
            _("These carry across every book in the series.")),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

-- Titles and blessings -----------------------------------------------------

function Inventory.titles(plugin)
    local character = plugin.character
    local back = function() Inventory.titles(plugin) end
    local items = {}

    for index, title in ipairs(character.titles) do
        table.insert(items, {
            text = title,
            callback = function()
                Prompts.confirm{
                    text = ("Give up the title %s?"):format(title),
                    ok_text = _("Give up"),
                    ok_callback = function()
                        table.remove(character.titles, index)
                        plugin:save()
                        back()
                    end,
                    cancel_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Record a title"),
        callback = function()
            Prompts.text{
                title = _("Titles and honours"),
                hint = _("Illuminate of Molhern"),
                ok_text = _("Record"),
                cancel_callback = back,
                callback = function(title)
                    title = title:match("^%s*(.-)%s*$")
                    if title ~= "" then
                        table.insert(character.titles, title)
                        plugin:save()
                    end
                    back()
                end,
            }
        end,
    })

    Prompts.menu{
        title = _("Titles and honours"),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

function Inventory.blessings(plugin)
    local character = plugin.character
    local back = function() Inventory.blessings(plugin) end
    local items = {}

    for index, blessing in ipairs(character.blessings) do
        table.insert(items, {
            text = blessing.ability
                and ("%s  (%s)"):format(blessing.name, blessing.ability)
                or blessing.name,
            callback = function()
                Prompts.confirm{
                    text = ("Cross off %s?"):format(blessing.name),
                    ok_text = _("Cross off"),
                    ok_callback = function()
                        character:removeBlessing(index)
                        plugin:save()
                        back()
                    end,
                    cancel_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Receive a blessing"),
        callback = function()
            Prompts.text{
                title = _("Which blessing?"),
                hint = _("Safety from Storms"),
                ok_text = _("Next"),
                cancel_callback = back,
                callback = function(name)
                    name = name:match("^%s*(.-)%s*$")
                    if name == "" then back() return end

                    local function record(blessing)
                        local ok, err = character:addBlessing(blessing)
                        if not ok then Prompts.info(err) else plugin:save() end
                        back()
                    end

                    local choices = { {
                        text = _("No particular ability"),
                        callback = function() record({ name = name }) end,
                    } }
                    for _i, ability in ipairs(Rules.ABILITIES) do
                        table.insert(choices, {
                            text = ability,
                            callback = function() record({ name = name, ability = ability }) end,
                        })
                    end
                    Prompts.menu{
                        title = ("%s\n\n%s"):format(name,
                            _("Which ability does it bless? You may hold only one of each type.")),
                        items = choices,
                        close_callback = back,
                    }
                end,
            }
        end,
    })

    Prompts.menu{
        title = _("Blessings"),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

-- Curses, diseases and poisons --------------------------------------------

local function describePenalties(penalties, sign)
    local parts = {}
    for _i, ability in ipairs(Rules.ABILITIES) do
        local points = (penalties or {})[ability]
        if points and points > 0 then
            table.insert(parts, ("%s %s%d"):format(ability, sign, points))
        end
    end
    return table.concat(parts, ", ")
end

--- Which abilities a new affliction lowers, and by how much. The book says
-- so in the same breath as naming it.
local function askPenalties(plugin, name, penalties, back)
    local again = function() askPenalties(plugin, name, penalties, back) end
    local items = {}
    for _i, ability in ipairs(Rules.ABILITIES) do
        local points = penalties[ability] or 0
        table.insert(items, {
            text = points > 0 and ("%s  -%d"):format(ability, points) or ability,
            callback = function()
                Prompts.number{
                    title = ("%s: %s"):format(name, ability),
                    info = _("How many points does it take?"),
                    value = points > 0 and points or 1, min = 0, max = 11,
                    ok_text = _("Set"),
                    cancel_callback = again,
                    callback = function(value)
                        penalties[ability] = value > 0 and value or nil
                        again()
                    end,
                }
            end,
        })
    end
    table.insert(items, {
        text = _("Record it"),
        callback = function()
            plugin.character:addAffliction(name, penalties)
            plugin:save()
            back()
        end,
    })

    Prompts.menu{
        title = ("%s\n\n%s"):format(name,
            _("Tap each ability it lowers until it is cured, then Record it.")),
        items = items,
        close_callback = back,
    }
end

function Inventory.afflictions(plugin)
    local character = plugin.character
    local back = function() Inventory.afflictions(plugin) end
    local items = {}

    for index, affliction in ipairs(character.afflictions) do
        local cost = describePenalties(affliction.penalties, "-")
        table.insert(items, {
            text = cost ~= "" and ("%s  (%s)"):format(affliction.name, cost) or affliction.name,
            callback = function()
                local refund = describePenalties(affliction.penalties, "+")
                Prompts.confirm{
                    text = refund ~= ""
                        and ("Cured of %s?\n\nYou get back %s."):format(affliction.name, refund)
                        or ("Cured of %s?"):format(affliction.name),
                    ok_text = _("Cured"),
                    ok_callback = function()
                        character:cureAffliction(index)
                        plugin:save()
                        back()
                    end,
                    cancel_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Record a curse, disease or poison"),
        callback = function()
            Prompts.text{
                title = _("What has befallen you?"),
                hint = _("Swamp fever"),
                ok_text = _("Next"),
                cancel_callback = back,
                callback = function(name)
                    name = name:match("^%s*(.-)%s*$")
                    if name == "" then back() return end
                    askPenalties(plugin, name, {}, back)
                end,
            }
        end,
    })

    Prompts.menu{
        title = ("%s\n\n%s"):format(_("Curses, diseases and poisons"),
            _("Each lowers your abilities until it is cured. Tap one once it is.")),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

-- Your god, and dying -------------------------------------------------------

--- Asks before leaving a god costs resurrection arrangements.
local function confirmLeavingGod(character, verb, at_stake, ok_callback, back)
    Prompts.confirm{
        text = at_stake > 0
            and ("%s %s?\n\nThis also gives up %d resurrection arrangement%s, which were made with that temple."):format(
                verb, character.god, at_stake, at_stake == 1 and "" or "s")
            or ("%s %s?"):format(verb, character.god),
        ok_text = verb,
        ok_callback = ok_callback,
        cancel_callback = back,
    }
end

function Inventory.faith(plugin)
    local character = plugin.character
    local back = function() Inventory.faith(plugin) end
    local items = {}

    table.insert(items, {
        text = character.god and ("God: %s"):format(character.god) or _("Name your god"),
        callback = function()
            Prompts.text{
                title = _("Which god do you worship?"),
                value = character.god or "",
                hint = _("Nagil"),
                ok_text = _("Set"),
                cancel_callback = back,
                callback = function(name)
                    local function apply()
                        character:setGod(name)
                        plugin:save()
                        back()
                    end
                    local at_stake = character:godChangeCost(name)
                    if at_stake > 0 then
                        confirmLeavingGod(character, _("Leave"), at_stake, apply, back)
                    else
                        apply()
                    end
                end,
            }
        end,
    })

    if character.god then
        table.insert(items, {
            text = _("Renounce this god"),
            callback = function()
                confirmLeavingGod(character, _("Renounce"), character:arrangementCount(), function()
                    character:renounceGod()
                    plugin:save()
                    back()
                end, back)
            end,
        })
    end

    for index, deal in ipairs(character.resurrection or {}) do
        table.insert(items, {
            text = deal.section
                and ("%s -- turn to %d"):format(deal.where, deal.section)
                or deal.where,
            callback = function()
                Prompts.confirm{
                    text = ("Give up the arrangement at %s?"):format(deal.where),
                    ok_text = _("Give up"),
                    ok_callback = function()
                        character:removeResurrection(index)
                        plugin:save()
                        back()
                    end,
                    cancel_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Arrange a resurrection"),
        callback = function()
            Prompts.fields{
                title = _("Resurrection arrangement"),
                fields = {
                    { text = "", hint = _("Where, e.g. Temple of Nagil") },
                    { input_type = "number", text = "", hint = _("Turn to which section on death") },
                },
                ok_text = _("Arrange"),
                cancel_callback = back,
                callback = function(values)
                    if not character:addResurrection(values[1], values[2]) then
                        Prompts.info(_("An arrangement needs somewhere it was made."))
                    else
                        plugin:save()
                    end
                    back()
                end,
            }
        end,
    })

    Prompts.menu{
        title = character:isDead()
            and ("%s\n\n%s"):format(_("You are dead."), Format.resurrection(character))
            or _("God and resurrection"),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

-- Ship's Manifest ----------------------------------------------------------

function Inventory.ship(plugin)
    local character = plugin.character
    local ship = character.ship
    local back = function() Inventory.ship(plugin) end

    if not ship then
        Prompts.menu{
            title = _("Ship's Manifest\n\nYou have no ship."),
            items = { {
                text = _("Record a ship"),
                callback = function()
                    character.ship = { cargo = {} }
                    plugin:save()
                    back()
                end,
            } },
            close_callback = function() plugin:showSheet() end,
        }
        return
    end
    ship.cargo = ship.cargo or {}

    local function pick(label, options, current, apply)
        local items = {}
        for _i, option in ipairs(options) do
            table.insert(items, {
                text = option == current and ("> " .. option) or option,
                callback = function() apply(option); plugin:save(); back() end,
            })
        end
        Prompts.menu{ title = label, items = items, close_callback = back }
    end

    local capacity = tonumber(ship.capacity)
    local items = {
        {
            text = ("Name: %s"):format(ship.name ~= "" and ship.name or "-"),
            callback = function()
                Prompts.text{
                    title = _("Ship's name"), value = ship.name or "", hint = _("Sea Dog"),
                    ok_text = _("Set"),
                    cancel_callback = back,
                    callback = function(v) ship.name = v; plugin:save(); back() end,
                }
            end,
        },
        {
            text = ("Type: %s"):format(ship.type or "-"),
            callback = function()
                pick(_("Ship type"), Rules.SHIP_TYPES, ship.type,
                    function(v) ship.type = v end)
            end,
        },
        {
            text = ("Crew: %s"):format(ship.crew or "-"),
            callback = function()
                pick(_("Crew quality"), Rules.CREW_QUALITY, ship.crew,
                    function(v) ship.crew = v end)
            end,
        },
        {
            text = ("Cargo: %d/%s"):format(#ship.cargo, capacity or "?"),
            callback = function() Inventory.cargo(plugin) end,
        },
        {
            text = ("Docked at: %s"):format(ship.docked ~= "" and ship.docked or "-"),
            callback = function()
                Prompts.text{
                    title = _("Where docked"), value = ship.docked or "", hint = _("Yellowport"),
                    ok_text = _("Set"),
                    cancel_callback = back,
                    callback = function(v) ship.docked = v; plugin:save(); back() end,
                }
            end,
        },
        {
            text = _("Roll for the ship"),
            callback = function() Inventory.shipRoll(plugin) end,
        },
        {
            text = _("Lose the ship"),
            callback = function()
                Prompts.confirm{
                    text = _("Give up this ship and its cargo?"),
                    ok_text = _("Give up"),
                    ok_callback = function()
                        character.ship = nil
                        plugin:save()
                        plugin:showSheet()
                    end,
                    cancel_callback = back,
                }
            end,
        },
    }

    Prompts.menu{
        title = _("Ship's Manifest"),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

--- Cargo as units against the hold's capacity, rather than a line of text:
--- the question in play is always whether there is room for more.
function Inventory.cargo(plugin)
    local ship = plugin.character.ship
    local back = function() Inventory.cargo(plugin) end
    ship.cargo = ship.cargo or {}
    local capacity = tonumber(ship.capacity)

    local items = {}
    for index, unit in ipairs(ship.cargo) do
        table.insert(items, {
            text = unit,
            callback = function()
                Prompts.confirm{
                    text = ("Unload %s?"):format(unit),
                    ok_text = _("Unload"),
                    ok_callback = function()
                        table.remove(ship.cargo, index)
                        plugin:save()
                        back()
                    end,
                    cancel_callback = back,
                }
            end,
        })
    end

    table.insert(items, {
        text = _("Take on cargo"),
        callback = function()
            if capacity and #ship.cargo >= capacity then
                Prompts.info(("The hold is full at %d units."):format(capacity))
                back()
                return
            end
            Prompts.text{
                title = _("What are you loading?"),
                hint = _("timber"),
                ok_text = _("Load"),
                cancel_callback = back,
                callback = function(name)
                    name = name:match("^%s*(.-)%s*$")
                    if name ~= "" then
                        table.insert(ship.cargo, name)
                        plugin:save()
                    end
                    back()
                end,
            }
        end,
    })

    table.insert(items, {
        text = ("Hold capacity: %s"):format(capacity or "not set"),
        callback = function()
            Prompts.number{
                title = _("Cargo capacity"),
                info = _("How many units the hold takes."),
                value = capacity or 6, min = 0, max = 50,
                ok_text = _("Set"),
                cancel_callback = back,
                callback = function(v) ship.capacity = v; plugin:save(); back() end,
            }
        end,
    })

    Prompts.menu{
        title = ("%s  %d/%s"):format(_("Cargo"), #ship.cargo, capacity or "?"),
        items = items,
        close_callback = function() Inventory.ship(plugin) end,
    }
end

--- The books roll for the ship by hull and crew: one die for a barque, two
--- for a brigantine, three for a galleon, plus the crew's bonus.
function Inventory.shipRoll(plugin)
    local ship = plugin.character.ship
    local result = Rules.shipRoll(ship.type, ship.crew)
    if not result then
        Prompts.info(_("Set the ship's type first: the hull decides how many dice."))
        Inventory.ship(plugin)
        return
    end
    Prompts.panel{
        title = Format.shipRoll(result),
        buttons = { { {
            text = _("Roll again"),
            callback = function() Inventory.shipRoll(plugin) end,
        } } },
        close_text = _("Done"),
        close_callback = function() Inventory.ship(plugin) end,
    }
end

-- Stamina and abilities --------------------------------------------------

function Inventory.stamina(plugin)
    local character = plugin.character
    local back = function() Inventory.stamina(plugin) end

    Prompts.menu{
        title = ("%s  %d/%d"):format(_("Stamina"), character.stamina, character.stamina_max),
        items = {
            {
                text = _("Lose Stamina"),
                callback = function()
                    Prompts.number{
                        title = _("Lose how much Stamina?"),
                        value = 1, min = 1, max = 99,
                        ok_text = _("Lose"),
                        cancel_callback = back,
                        callback = function(amount)
                            character:takeDamage(amount)
                            plugin:save()
                            if character:isDead() then
                                Prompts.info(_("Your Stamina has reached zero. You are dead."))
                                plugin:showSheet()
                            else
                                back()
                            end
                        end,
                    }
                end,
            },
            {
                text = _("Restore Stamina"),
                callback = function()
                    Prompts.number{
                        title = _("Restore how much Stamina?"),
                        info = _("Never above your unwounded score."),
                        value = 1, min = 1, max = 99,
                        ok_text = _("Restore"),
                        cancel_callback = back,
                        callback = function(amount)
                            character:heal(amount)
                            plugin:save()
                            back()
                        end,
                    }
                end,
            },
            {
                text = _("Restore to full"),
                callback = function()
                    character.stamina = character.stamina_max
                    plugin:save()
                    back()
                end,
            },
            {
                text = _("Change unwounded score"),
                callback = function()
                    Prompts.number{
                        title = _("Unwounded Stamina"),
                        info = _("Your maximum, which rises with Rank."),
                        value = character.stamina_max, min = 1, max = 99,
                        ok_text = _("Set"),
                        cancel_callback = back,
                        callback = function(value)
                            character.stamina_max = value
                            character.stamina = math.min(character.stamina, value)
                            plugin:save()
                            back()
                        end,
                    }
                end,
            },
        },
        close_callback = function() plugin:showSheet() end,
    }
end

function Inventory.abilities(plugin)
    local character = plugin.character
    local back = function() Inventory.abilities(plugin) end
    local items = {}

    for _i, ability in ipairs(Rules.ABILITIES) do
        local bonus = character:itemBonus(ability)
        table.insert(items, {
            text = bonus > 0
                and ("%s  %d (+%d from gear)"):format(ability, character.abilities[ability], bonus)
                or ("%s  %d"):format(ability, character.abilities[ability]),
            callback = function()
                Prompts.number{
                    title = ability,
                    info = _("Abilities run from 1 to 12."),
                    value = character.abilities[ability],
                    min = Rules.ABILITY_MIN,
                    max = Rules.ABILITY_MAX,
                    ok_text = _("Set"),
                    cancel_callback = back,
                    callback = function(value)
                        character.abilities[ability] = Rules.clampAbility(value)
                        plugin:save()
                        back()
                    end,
                }
            end,
        })
    end

    Prompts.menu{
        title = _("Abilities"),
        items = items,
        close_callback = function() plugin:showSheet() end,
    }
end

function Inventory.notes(plugin)
    local character = plugin.character
    Prompts.text{
        title = _("Notes"),
        description = _("Anything the sheet has no box for."),
        value = character.notes or "",
        ok_text = _("Save"),
        cancel_callback = function() plugin:showSheet() end,
        callback = function(text)
            character.notes = text
            plugin:save()
            plugin:showSheet()
        end,
    }
end

return Inventory
