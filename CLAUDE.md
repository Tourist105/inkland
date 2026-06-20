# Inkland — Godot 4 2D territory-capture arena

> **Master rules live in `../AppRecovery/CLAUDE.md`.** Read that first.

## Quick facts
- **Game:** Inkland (working title — see GAME_DESIGN.md §3 for name options)
- **One-liner:** Original take on the territory-capture arena (paper.io genre)
- **Engine:** Godot 4.6 2D (per master policy: games are Godot 4; KorGE retired)
- **Package:** `ch.roethlisberger.inkland`
- **Run:** open `project.godot` in Godot 4.6, press F5. Android via Project > Export.

## Hard rule for this repo
This is a **mechanic clone, not an asset clone.** Game mechanics are not
copyrightable; art, name, characters and trade dress ARE. Everything here is
original code + original art. Do **NOT** import, trace, or pixel-copy paper.io
(or any other app's) sprites, palette, sounds, fonts, or name. The whole
`ch.roethlisberger.*` portfolio rides on one Play account — a copycat strike
risks all of it. Keep it clean.

## Status
Scaffold stage. Core sim works: human + 2 bots, grid ownership, trail-laying,
enclosure flood-fill capture, trail-cross death, respawn, live % HUD.
Keyboard (arrows/WASD) + touch-swipe controls. See `GAME_DESIGN.md` for the
full design and the M0–M4 roadmap.

## Layout
- `scripts/Arena.gd`  — the whole simulation + renderer (grid, fill, bots, draw)
- `scripts/Player.gd` — `InkPlayer` data class
- `scenes/Main.tscn`  — Arena node + HUD label
