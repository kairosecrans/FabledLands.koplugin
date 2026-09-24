# FabledLands.koplugin

A KOReader plugin for the **Fabled Lands** gamebooks by Dave Morris and Jamie
Thomson. Keeps your Adventure Sheet, rolls the dice, runs fights, and turns to
the section you were told to turn to.

Vibe coded from top to bottom with Claude Opus 5 for my own personal use.

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

Defence is derived from COMBAT, Rank and your best armour, not typed in.
Item bonuses show against the ability they help (`THIEVERY 6+2`) and never
stack.

**Ability rolls** show the arithmetic, and say what you *needed*:

```
SCOUTING roll, Difficulty 9

  Dice        4 + 3 = 7
  SCOUTING    +6
  Item bonus  +1
  Total       14

SUCCESS -- needed 10, got 14
```

*Needed 10*, not *needed 9*: the roll must beat the Difficulty outright.

**Fights**, one round per tap. You strike, then the enemy strikes back:

```
Goblin
  COMBAT 5   Defence 7   Stamina 5/6

You
  COMBAT 4   Defence 6   Stamina 1/9
  this fight: attack +3

Round 1
  You     (2+2)+7=11 vs 7 -> 4
  Goblin  (4+5)+5=14 vs 6 -> 8
```

Signed **modifiers** handle the local rules the books impose: a bonus for
carrying some item, a penalty for fighting in the dark. They last one fight
and don't touch your sheet. **Next enemy** continues the same fight for foes
fought one at a time, carrying Stamina, rounds and log across. There are also
buttons for a lone enemy blow, healing mid-fight, and fleeing.

**A dice roller** for the rolls that aren't ability checks: one to four dice,
with your Rank, Defence, Stamina and abilities beside the result for whatever
the book asks you to add or compare.

**Curses, diseases and poisons** lower the abilities they name until they're
cured, and curing gives the points back.

**Turn to section.** Section numbers aren't page numbers. Type the number and
it goes there. Every jump is remembered per book, so returning to a section
you've visited is immediate. Requires a text layer (a scan that has been
through OCR), and says so if a book has none.

**Your god and resurrection arrangements**, which the printed sheet has a box
for. When Stamina reaches zero the sheet shows the arrangement you made, since
that is the moment you need it.

**A ship** with its own roll: one die for a barque, two for a brigantine,
three for a galleon, plus one for a good crew or two for an excellent one.
Cargo is counted against the hold's capacity.

**Start in any book.** Book N begins you at Rank N with that book's own
profession table, Stamina, money and gear. One character travels the whole
series, and codewords are never erased when moving between books.

**Minimize** from any screen, while a book is open, to a small badge in the
margin, leaving the page readable. Tapping it returns you to where you were,
including a half-typed enemy stat block.

Plus possessions with the 12-item limit and money on the same screen, healing
items you can use, money and possessions stored elsewhere, codewords (with a
"do I have this one?" lookup), titles, blessings, and Rank advancement. Rank can also
be lost, as the books sometimes impose, with a separate exact undo for a
mis-tap. Name and profession can be corrected after creation, and you can keep
several characters and switch between them.

## Installing

**Easiest: the [App Store plugin](https://github.com/omer-faruq/appstore.koplugin).**
If you have it, find Fabled Lands and install. It pulls straight from this
repository, so updating is a tap.

**By hand:** clone into KOReader's `plugins` folder. The directory name must
end in `.koplugin`.

```bash
git clone https://github.com/kairosecrans/FabledLands.koplugin.git ~/.config/koreader/plugins/FabledLands.koplugin
```

On Android that folder is `/storage/emulated/0/koreader/plugins/`; on Kobo,
`.adds/koreader/plugins/`.

Restart KOReader. It appears under **Tools → More tools → Fabled Lands**.

Five actions can be bound to a gesture under *Taps and gestures*: Adventure
Sheet, ability roll, dice roller, turn to section, and restore minimized.

Characters live in KOReader's settings directory as `fabledlands.lua`, not in
the plugin folder, so reinstalling doesn't touch them.

## The rules

From Book 1, *The War-Torn Kingdom*, pp. 5-7:

- **Ability check.** 2d6 + ability, must be **strictly greater** than the
  Difficulty.
- **Defence.** COMBAT + Rank + best armour bonus.
- **A blow.** 2d6 + COMBAT against the target's Defence; the margin is the
  Stamina lost.
- **Item bonuses.** Never cumulative; only your best item counts per ability.
- **Abilities.** 1 to 12.
- **Possessions.** 12 maximum.
- **Rank change.** ±1 Rank and 1d6 Stamina, permanently.
- **Codewords.** Lettered by book (A = Book 1, B = Book 2 …), carried between
  books.
- **Starting later.** Book N starts you at Rank N, with that book's profession
  table.
- **Rolling for a ship.** One die for a barque, two for a brigantine, three
  for a galleon; +1 for a good crew, +2 for an excellent one.

The tests check these against the examples and pre-generated characters
printed in the books.

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

The first four have no KOReader imports, so they run under a bare interpreter.

Modules are prefixed `fl_` because KOReader shares one `package.path` across
every loaded plugin. `spec/lint_spec.lua` enforces the prefix, and rejects two
things that fail silently and leave the plugin loaded but unreachable:
rebinding `_` in a file that uses it as the gettext alias, and doing KOReader
work at module load.

## License

GPL-3.0, see [LICENSE](LICENSE).

*Fabled Lands* is the work of Dave Morris and Jamie Thomson. This is an
unofficial play aid and contains none of the books' text. You still need the
books.
