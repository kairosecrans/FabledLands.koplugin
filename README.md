# FabledLands.koplugin

A KOReader plugin for the **Fabled Lands** gamebooks by Dave Morris and Jamie
Thomson. Keeps your Adventure Sheet, rolls the dice, runs fights, and turns to
the section you were told to turn to.

Vibe coded from top to bottom with Claude for my own personal use. *Fabled Lands*
is the work of Dave Morris and Jamie Thomson. This is an unofficial play aid and
contains none of the books' text. You still need the books to play.

## What it does

**The Adventure Sheet**

```
Marana
Rogue, 1st Rank Outcast

CHARISMA 5     SANCTITY 1
COMBAT   4     SCOUTING 2
MAGIC    4     THIEVERY 6

Stamina   9/9
Defence   6
Money     16 Shards
Carrying  3/12 items
```

Defence is automatically calculated from COMBAT, Rank and your best armour. Item bonuses
appear beside their ability (`THIEVERY 6+2`).

**Ability rolls**, with the arithmetic shown.

**Automated combat**, one round per tap.

**Turn to section.** Type a section number and the reader goes to its page.
Sections you've visited are remembered per book. Needs a text layer, so a
scanned book must have been through OCR.

**Curses, diseases and poisons** lower the abilities they name until cured.

**God and resurrection.** When Stamina reaches zero, the sheet shows the
arrangement you made.

**Start in any book**, at that book's Rank and with its profession table and
gear. One character can play the whole series.

**Dice roller.** One to four dice, with your stats alongside for whatever the
book asks you to add or compare.

**Minimize** the sheet, a roll, a fight, your possessions or codewords to a
badge in the margin. Tap it to return where you left off, half-typed input
included.

Also: possessions and money, ships, healing items, things stored elsewhere,
codewords, titles, blessings, Rank changes with an undo, and multiple
characters.

There is currently no system for handling section-specific ticks. I recommend
using a separate drawn annotations plugin for handling this.

## Installing

Easiest is the [App Store plugin](https://github.com/omer-faruq/appstore.koplugin) or [Storefront plugin](https://github.com/ultimatejimmy/storefront.koplugin):
simply use the UI to find Fabled Lands and install.

By hand, clone into KOReader's `plugins` folder:

```bash
git clone https://github.com/kairosecrans/FabledLands.koplugin.git ~/.config/koreader/plugins/FabledLands.koplugin
```

On Android that folder is `/storage/emulated/0/koreader/plugins/`; on Kobo,
`.adds/koreader/plugins/`.

Restart KOReader and open **Tools → More tools → Fabled Lands**. Gesture
actions, under *Taps and gestures*: Adventure Sheet, ability roll, dice
roller, turn to section, and restore minimized.

## The rules

- **Ability check.** 2d6 + ability, must be **strictly greater** than the
  Difficulty.
- **Defence.** COMBAT + Rank + best armour bonus.
- **A blow.** 2d6 + COMBAT against the target's Defence; the margin is the
  Stamina lost.
- **Item bonuses.** Only your best item counts per ability.
- **Abilities.** 1 to 12.
- **Possessions.** 12 maximum.
- **Rank change.** ±1 Rank and 1d6 Stamina, permanently.
- **Codewords.** Lettered by book (A = Book 1, B = Book 2 …), carried between
  books.
- **Starting later.** Book N starts you at Rank N, with that book's profession
  table.
- **Rolling for a ship.** One die for a barque, two for a brigantine, three
  for a galleon; +1 for a good crew, +2 for an excellent one.

The tests check these against the books' worked examples and pre-generated
characters.

## Development

```bash
./run_tests.sh      # 943 checks, any Lua 5.1+
./build-release.sh  # archive that extracts to FabledLands.koplugin/
```

| file | what it does |
|---|---|
| `fl_rules.lua` | Dice and the rules |
| `fl_character.lua` | The Adventure Sheet model |
| `fl_format.lua` | Renders sheets, rolls and fights as text |
| `fl_sections.lua` | Finding the page a section is printed on |
| `fl_prompts.lua` | Wrappers over the KOReader widgets |
| `fl_combat.lua` | The combat tracker |
| `fl_inventory.lua` | Editors for possessions, codewords and the rest |
| `fl_badge.lua` | The minimized badge |
| `main.lua` | Plugin lifecycle, menu, persistence |

## License

GPL-3.0, see [LICENSE](LICENSE).