--[[--
Editors for the parts of the Adventure Sheet you write in with a pencil:
possessions, codewords, titles, blessings, the Ship's Manifest, Stamina,
money and abilities.

Every screen returns to the one that opened it, so the whole thing behaves
like a stack of sheets rather than a maze.

@module koplugin.FabledLands.inventory
--]]--

local Prompts = require("fl_prompts")
local Rules = require("fl_rules")
local _ = require("gettext")

local Inventory = {}

local function describeItem(item)
    if item.ability and (item.bonus or 0) > 0 then
        return ("%s (%s +%d)"):format(item.name, item.ability, item.bonus)
    elseif (item.defence or 0) > 0 then
        return ("%s (Defence +%d)"):format(item.name, item.defence)
    end
    return item.name
end

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
                text = _("It is armour"),
                callback = function()
                    Prompts.number{
                        title = ("%s"):format(name),
                        info = _("Defence bonus"),
                        value = 1, min = 1, max = 6,
                        ok_text = _("Add"),
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

function Inventory.possessions(plugin)
    local character = plugin.character
    local back = function() Inventory.possessions(plugin) end
    local items = {}

    for index, item in ipairs(character.possessions) do
        table.insert(items, {
            text = describeItem(item),
            callback = function()
                Prompts.menu{
                    title = describeItem(item),
                    items = { {
                        text = _("Drop it"),
                        callback = function()
                            character:removePossession(index)
                            plugin:save()
                            back()
                        end,
                    } },
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
        callback = function() plugin:minimize(back, "sheet") end,
    })

    Prompts.menu{
        title = ("%s  %d/%d\n\n%s"):format(_("Possessions"), #character.possessions,
            Rules.MAX_POSSESSIONS, _("Only your best weapon and armour count.")),
        items = items,
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

-- Ship's Manifest ----------------------------------------------------------

function Inventory.ship(plugin)
    local character = plugin.character
    local ship = character.ship or {}

    Prompts.fields{
        title = _("Ship's Manifest"),
        fields = {
            { description = _("Ship's name"), text = ship.name or "", hint = _("Sea Dog") },
            {
                description = _("Type: barque, brigantine or galleon"),
                text = ship.type or "",
                hint = table.concat(Rules.SHIP_TYPES, ", "),
            },
            {
                description = _("Crew quality"),
                text = ship.crew or "",
                hint = table.concat(Rules.CREW_QUALITY, ", "),
            },
            { description = _("Cargo capacity"), text = ship.capacity or "", hint = "6" },
            { description = _("Current cargo"), text = ship.cargo or "", hint = _("timber") },
            { description = _("Where docked"), text = ship.docked or "", hint = _("Yellowport") },
        },
        ok_text = _("Save"),
        callback = function(values)
            local name, kind = values[1], values[2]
            if (name .. kind):match("^%s*$") then
                -- Both blank means "I no longer have a ship".
                character.ship = nil
            else
                character.ship = {
                    name = name, type = kind, crew = values[3],
                    capacity = values[4], cargo = values[5], docked = values[6],
                }
            end
            plugin:save()
            plugin:showSheet()
        end,
    }
end

-- Stamina, money, abilities ------------------------------------------------

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

function Inventory.money(plugin)
    local character = plugin.character
    local back = function() Inventory.money(plugin) end

    local function adjust(title, ok_text, sign)
        Prompts.number{
            title = title,
            value = 1, min = 1, max = 9999, hold_step = 50,
            ok_text = ok_text,
            callback = function(amount)
                character.shards = math.max(0, character.shards + sign * amount)
                plugin:save()
                back()
            end,
        }
    end

    Prompts.menu{
        title = ("%s  %d Shards"):format(_("Money"), character.shards),
        items = {
            {
                text = _("Gain Shards"),
                callback = function() adjust(_("Gain how many Shards?"), _("Gain"), 1) end,
            },
            {
                text = _("Spend Shards"),
                callback = function() adjust(_("Spend how many Shards?"), _("Spend"), -1) end,
            },
            {
                text = _("Set the exact amount"),
                callback = function()
                    Prompts.number{
                        title = _("How many Shards do you have?"),
                        value = character.shards, min = 0, max = 99999, hold_step = 100,
                        ok_text = _("Set"),
                        callback = function(value)
                            character.shards = value
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
        callback = function(text)
            character.notes = text
            plugin:save()
            plugin:showSheet()
        end,
    }
end

return Inventory
