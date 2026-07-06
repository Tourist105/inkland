# Inkland — Game Design Doc

Working title. Original territory-capture arena game in the **paper.io genre**.
Reference studied: **Paper.io 2** by Voodoo (`io.voodoo.paper2`, v4.33.0 / vc472,
149 MB, Unity IL2CPP, AppLovin MAX + 15-network ad waterfall). We build our own
in **Godot 4.6** — original code, original art, lighter monetisation.

> **Legal line (non-negotiable):** mechanics are free to copy, *assets are not*.
> No paper.io sprites, palette, name, characters, fonts, sounds or trade dress.
> Our whole portfolio is on one Play account; a copycat strike risks everything.

---

## 1. What Paper.io 2 actually is (and why it's sticky)

- **Core loop (15–60 s/round):** you are a coloured square in a square arena.
  Most of the arena starts neutral; you own a small home block. Drive *out* of
  your land and you leave a trail. Loop back into your land and **everything the
  loop enclosed becomes yours**. Repeat until you own the most, or you die.
- **Risk:** while your trail is out, you're vulnerable. If anyone (a bot, or you
  on your own line) touches that trail, you die instantly. Bigger grabs = longer
  trail out = more risk. That risk/greed tension is the entire game.
- **Opponents:** ~6–8 bots of other colours doing the same thing. You can kill
  them by cutting their trail; they can kill you. Killing a player frees their
  land back to neutral.
- **Why it retains:** instant restart, zero learning curve, a clean "one more
  go" greed loop, a visible **% of map** number to beat, and a **skin
  collection** meta that gives a reason to keep coins.
- **How it earns (heavy):** interstitial after most deaths, **rewarded video**
  for revives / coin-doubling / skin unlocks, banner. The 15-network mediation
  waterfall squeezes max eCPM. It is monetised aggressively to the point of
  friction — which is our opening.

## 2. Where Paper.io 2 is weak → our wedge ("better than every competitor")

| Their weakness (common review complaints) | Inkland's answer |
|---|---|
| Ad-saturated: interstitial after almost every death | Banner-first; **at most one** optional *rewarded* (revive / 2× coins). Never interstitial. (Matches portfolio rule.) |
| 149 MB download (Unity + ad SDKs) | Godot 4, flat vector art, target **< 40 MB** |
| Bots feel dumb / suicidal | Smarter bots: greed/caution personalities, real loop-closing, ambush behaviour |
| No offline play (ads need network) | **Fully offline** single-player vs bots; online is optional later |
| Privacy: AD_ID + install-referrer + heavy SDKs | One ad SDK (AdMob), clear "no data sold", empty-ish Data Safety |
| Identical every round | **Daily seed + modifiers** (hazards, power cells, shrinking arena) for variety |
| Pure twitch, no depth | Optional **objectives** ("capture the centre", "survive 60 s") for a reason to play beyond %|

Our positioning: *"the territory game that respects you — no ad after every
death, plays offline, half the size, smarter rivals."*

## 3. Name options (pick one — folder/package rename is trivial)

`ch.roethlisberger.<name>`. Avoid "paper", ".io", and anything near Voodoo's marks.

1. **Inkland** (current working title) — ink theme, claim the land
2. **Splotch** — playful, the blob/spread motif
3. **Claimed** — blunt, keyword-friendly
4. **Territo** / **Conqur** — coined, brandable
5. **Inkby** — short, app-store-clean

ASO title pattern (per portfolio rule): `Inkland — Territory Arena`.

## 4. Design spec

- **Arena:** square grid, full-view at first (whole board visible) for game feel;
  camera-follow + zoom is a polish milestone. Default 36×64 cells in the
  scaffold; tune to taste.
- **Controls:** swipe to set heading (4-dir now, **analog steering** is a M2
  upgrade to match Paper.io 2's smoother turns); arrows/WASD on desktop.
- **Win/lose:** round ends on death or when a target % is hit; show your %,
  rank, kills, coins earned. Instant retry.
- **Economy:** coins from area captured + kills. Spend on **skins** (pure
  cosmetic colour/face/trail-effect sets — all original art).
- **Progression:** unlock skins; daily challenge with a fixed seed; optional
  per-round modifiers.
- **Monetisation:** AdMob **banner** during menus only (not over the arena);
  **one** rewarded video — revive once, or 2× round coins. No interstitials.
- **Haptics + juice:** capture pop, kill flash, trail hum. Cheap, high-impact.

## 5. Tech

- **Engine:** Godot 4.6, mobile renderer, portrait. Flat `draw_rect` grid —
  no texture memory, tiny build.
- **Model:** `grid` = owner id per cell; `trail_owner` = active-trail layer.
- **Capture algorithm:** add trail to land, then **flood-fill the outside from
  the border through all non-owned cells; everything unreached is enclosed →
  becomes yours.** O(cells) per capture, runs every loop-close. (Implemented.)
- **Death:** head enters any trail cell → that trail's owner dies, land neutralised.
- **Bots:** per-tick intent in `_bot_think` (wander out, curl home to close).
  Personalities + threat awareness are M2.

## 6. What's built (M0–M3 — done 2026-07-06)

- ✅ Grid sim, ownership, trail-laying, **enclosure flood-fill capture**
- ✅ Trail-cross death, neutralise, timed respawn (bots at fresh free spots)
- ✅ Camera follow + zoom, interpolated movement, ribbon trails
- ✅ Human + **5 bots** with greed/caution/aggro personalities, loop planning,
  threat awareness, opportunistic trail-cutting
- ✅ Round flow: 3-2-1 countdown → play → pause → death (cause shown) →
  continue-offer (rewarded seam) → results → retry/menu; win at 100%
- ✅ Juice: capture flash + floating "+x%", kill/death rings, screen shake,
  haptics, 7 synthesized original SFX (tools/gen_sfx.py)
- ✅ Meta: coins (territory + eliminations), **9-skin shop** (procedural faces),
  best-score record, save via ConfigFile
- ✅ Home / settings (sound, vibration, language, privacy) / help overlay
- ✅ **22 UI languages** (strings.csv), in-app switcher, system-locale default
- ✅ Ad seam (`scripts/Ads.gd`): banner menus-only + ONE rewarded (2× coins /
  continue). Google TEST ids. Editor simulates rewarded so UX is testable.
- ✅ Headless-validated (import + 90 s fixed-fps sim) + rendered screenshots
  via the DevShot autoload

## 7. Roadmap — what's left to ship (M4)

1. **AdMob backend:** install a Godot-4.6-compatible AdMob Android editor
   plugin, implement `res://scripts/AdsBackend.gd` (contract in Ads.gd header),
   gradle build ON in the export preset. Keep TEST ids until prod moment.
2. **AdMob console:** Nils creates the Inkland app entry → real app/banner/
   rewarded ids into Ads.gd right before the production upload.
3. **UMP consent** (portfolio standard) via the same plugin.
4. **Fonts for CJK/ar/th/hi locales** (Noto subsets) + extend strings.csv,
   or ship v1 with the 22 current locales.
5. **Keystore:** add `inkland` alias (KEYSTORE_GUIDE.md), signed AAB.
6. **Store listing:** 88-locale ASO texts + localized screenshots
   (DevShot produces the frames), icon exports.
7. **Device QA on the Oppo** per the portfolio Definition-of-Done (swipe feel,
   haptics, back button, language switch, banner layout with cutouts).
8. Optional post-v1: daily seed challenge, modifiers, in-app review hook.
   **Upload only when it clearly beats Paper.io 2.**

## 8. Open decisions for Nils

1. **Name** (§3) — which one? Drives package + repo + AdMob entry.
2. **Online or offline-only** for v1? Offline-vs-bots ships far faster and is a
   genuine differentiator; real-time multiplayer is a big lift.
3. **Pixel reference:** want me to pull 3–4 screenshots of Paper.io 2 from the
   Oppo so the *feel* (not the assets) is dialled in? (Earlier capture was
   stopped — say the word and I'll grab them.)
