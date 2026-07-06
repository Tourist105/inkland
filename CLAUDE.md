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
M1–M3 done (2026-07-06): full round flow (countdown → play → pause/death →
continue-offer → results), 5 bots with greed/caution/aggro personalities,
coins + 9-skin shop, settings (sound/haptics/language/privacy), help overlay,
22-locale i18n, juice (capture flash, shake, haptics, synthesized SFX).
M4 open: AdMob backend (see `scripts/Ads.gd` header), real ad ids, keystore
alias, listing, Oppo device QA. See `GAME_DESIGN.md`.

## Layout
- `scripts/Arena.gd`   — simulation + renderer + round flow + in-round HUD
- `scripts/Player.gd`  — `InkPlayer` data class incl. bot brain state
- `scripts/Game.gd`    — autoload: save/coins/skins/settings/locale
- `scripts/Sfx.gd`     — autoload: sound pool + haptics (WAVs from tools/gen_sfx.py)
- `scripts/Ads.gd`     — autoload: ad seam (banner menus-only + 1 rewarded; NO interstitials)
- `scripts/DevShot.gd` — autoload: env-var-gated screenshot tool (inert in prod)
- `scripts/Home.gd` / `Shop.gd` — menu screens (UI built in code)
- `scripts/SkinArt.gd`, `scripts/ui/*` — shared procedural art + UI kit
- `assets/translations/strings.csv` — 22 languages (CJK/ar/th need font packs → M4)
- `scenes/Home.tscn` (main), `Main.tscn` (arena), `Shop.tscn`

## Validation
Headless: `Godot_console --headless --path . --import` then
`--headless --fixed-fps 60 --path . scenes/Main.tscn --quit-after 5400`
(fixed-fps, sonst sind Frames ≠ Sekunden). Screenshots:
`INKLAND_SHOT=out.png INKLAND_SHOT_FRAME=240 Godot --path . [scene]`.
