# FabledLands.koplugin

A KOReader plugin that keeps your Adventure Sheet and rolls the dice for the
**Fabled Lands** gamebook series by Dave Morris and Jamie Thomson.

It handles the bookkeeping so the only thing left to do by hand is turn to the
right section: abilities, Stamina, Defence, possessions, codewords, ability
checks and fights resolved round by round.

The plugin is book-agnostic — it never reads the book you are reading, so it
works with whatever edition or format you own.

Vibe coded from top to bottom with Claude Opus 5 for my own personal use.

## What it does

**The Adventure Sheet**

```
Marana
Rogue, 1st Rank Outcast

CHARISMA 5      SANCTITY 1
COMBAT   4      SCOUTING 2
MAGIC    4      THIEVERY 6

Stamina   9/9
Defence   6
Money     16 Shards
Carrying  3/12 items
```

Defence is derived, never typed in: it follows your COMBAT, your Rank and the
best armour you carry. Item bonuses show against the ability they help
(`THIEVERY 6+2`).

**Ability rolls** — pick the ability, dial in the Difficulty the book gives
you, and it rolls 2d6 and shows the arithmetic:

```
SCOUTING roll, Difficulty 9

  Dice        4 + 3 = 7
  SCOUTING          +6
  Item bonus        +1
  Total             14

SUCCESS -- needed 10, got 14
```

It says *needed 10* rather than *needed 9* on purpose. In Fabled Lands you must
beat the Difficulty outright; equalling it is a failure. That is the rule people
most often get wrong, so the plugin spells it out every time.

**Fights**, one round per tap — you strike, then the enemy strikes back if it is
still standing:

```
Goblin
  COMBAT 5   Defence 7   Stamina 5/6

You
  COMBAT 4   Defence 6   Stamina 1/9

Round 1
  You     (2+2)+4=8 vs 7 -> 1
  Goblin  (4+5)+5=14 vs 6 -> 8
```

There are buttons for a lone enemy blow (for the openings where the book gives
the enemy the first strike), for drinking a potion mid-fight, and for fleeing.
A fight is saved as you go, so you can close the panel to re-read the page and
pick it up again.

**Situational modifiers.** The books regularly adjust a fight: a bonus for
carrying a particular item, a penalty for fighting in the dark. **Modifiers**
takes a signed adjustment to your attack rolls and another to your Defence,
both lasting only for that fight and never touching your sheet. The panel
spells out what is in force (`this fight: attack +3`) so a surprising number
is always traceable.

**Several foes at once.** When the book says to fight them one at a time,
**Next enemy** continues the *same* fight: your Stamina, the round count, the
log and the modifiers all carry over rather than resetting.

**Minimising.** Every screen has a **Minimise** button. It tucks the plugin
into a small badge in the left margin showing the enemy's and your Stamina,
leaving the page readable so you can check a stat block mid-fight. Tapping the
badge returns you to exactly where you were -- including a half-typed stat
block, with the numbers you had already entered still in place. It survives
page turns and restarts.

**The rest of the sheet** — possessions with the 12-item carry limit,
codewords (with a "do I have this one?" lookup), titles, blessings, the Ship's
Manifest, money, and Rank advancement that rolls your permanent Stamina gain.

**Starting in any book.** You need only one book to start, and a later one
begins you further along. Character creation asks which book you are starting
in and applies what that book prints: Rank, Stamina, money and starting gear,
with ability scores from that book's own profession table. The books scale in
pairs -- 1 and 2 share a table, 3 and 4 another, 5 and 6 a third -- with the
initial range widening from 1-6 to 1-8, though the hard cap stays 12.

One character travels the whole series, and codewords are never erased when you
move between books, so characters are stored globally rather than per-document.
You can keep several characters and switch between them.

## Installing

The repository *is* the plugin directory, so clone it straight into KOReader's
`plugins` folder. The directory name must end in `.koplugin`.

**Android**

```bash
git clone https://github.com/kairosecrans/FabledLands.koplugin.git /storage/emulated/0/koreader/plugins/FabledLands.koplugin
```

**Linux (AppImage / desktop)**

```bash
git clone https://github.com/kairosecrans/FabledLands.koplugin.git ~/.config/koreader/plugins/FabledLands.koplugin
```

**Kobo / Kindle**

Copy the folder to `.adds/koreader/plugins/` (Kobo) or `koreader/plugins/`
(Kindle), keeping the `FabledLands.koplugin` name.

Then restart KOReader. While reading, the plugin sits in the **first tab of
the reader menu**, next to Table of contents -- two taps from the page, since
you reach for it constantly mid-fight. In the file manager it lives with the
other tools, under **Tools → More tools → Fabled Lands**.

It also registers three actions you can bind to a gesture or key: *Fabled
Lands: Adventure Sheet*, *Fabled Lands: ability roll*, and *Fabled Lands:
restore minimised*.

Your characters are stored in KOReader's settings directory as
`fabledlands.lua`, well away from the plugin folder, so updating or reinstalling
the plugin never touches them.

## The rules

The mechanics were transcribed from the rules in Book 1, *The War-Torn Kingdom*
(pp. 5–7), not from memory:

| | |
|---|---|
| Ability check | 2d6 + ability, must be **strictly greater** than the Difficulty |
| Defence | COMBAT + Rank + best armour bonus |
| A blow | 2d6 + COMBAT against the target's Defence; the margin is the Stamina lost |
| Item bonuses | Never cumulative — only your best item counts per ability |
| Abilities | 1 to 12 |
| Possessions | 12 maximum |
| Rank-up | +1 Rank and 1d6 Stamina, gained permanently |
| Codewords | Lettered by book (A = Book 1, B = Book 2 …) and carried between books |

The test suite encodes the worked examples printed in the book — the goblin
fight on p. 6, the Difficulty 10 CHARISMA roll on p. 5, the non-stacking
lockpicks on p. 7 — so a failure means the plugin disagrees with the printed
rules. The four pre-generated characters on the inside cover are checked too:
their Defence scores have to fall out of the formula.

## Development

```bash
./run_tests.sh
```

342 checks across four suites, run with any Lua 5.1+ interpreter — the suites
load no KOReader modules. The script finds the LuaJIT bundled with KOReader if
an extracted AppImage is nearby, otherwise anything on `PATH`. Override with
`LUA=/path/to/luajit ./run_tests.sh`.

| file | |
|---|---|
| `fl_rules.lua` | Dice and the rules. No KOReader dependency. |
| `fl_character.lua` | The Adventure Sheet model. No KOReader dependency. |
| `fl_format.lua` | Renders sheets, rolls and fights as text. No KOReader dependency. |
| `fl_prompts.lua` | Thin wrappers over the KOReader widgets. |
| `fl_combat.lua` | The combat tracker. |
| `fl_inventory.lua` | Editors for possessions, codewords and the rest. |
| `main.lua` | Plugin lifecycle, menu, persistence. |

The three rules-bearing modules are deliberately free of KOReader imports,
which is what makes them testable from a bare interpreter.

Modules are prefixed `fl_` because KOReader shares one `package.path` across
every loaded plugin: a bare `rules.lua` could be shadowed by another plugin's
file depending on load order. `spec/lint_spec.lua` enforces the prefix, and
also guards against rebinding `_` in files that use it as the gettext alias —
a shadowing bug that crashes only at the moment a button is tapped.

## Licence

GPL-3.0, see [LICENSE](LICENSE). That sits comfortably with KOReader, which is
AGPL-3.0 and whose modules this plugin imports at runtime.

*Fabled Lands* is the work of Dave Morris and Jamie Thomson. This plugin is an
unofficial play aid and reproduces none of the books' text — you still need the
books to play.
