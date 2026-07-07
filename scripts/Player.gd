extends RefCounted

## One actor in the arena — the human or a bot. Pure data + intent;
## all world mutation happens in Arena.gd so the simulation stays in one place.

var id: int
var color: Color
var face: int = 0
var pattern: int = 0          # special-hero ink pattern (0 = plain)
var display_name: String = ""
var is_human: bool = false

var alive: bool = true
var cx: int = 0
var cy: int = 0
var home: Vector2i = Vector2i.ZERO

var dir: Vector2i = Vector2i.RIGHT
var pending_dir: Vector2i = Vector2i.ZERO

## True while outside our own territory (i.e. actively laying a trail).
var is_out: bool = false
var trail: Array[Vector2i] = []

## Render-only ribbon: the head's TRUE continuous path this excursion. Drawn
## instead of grid cells, so the line is pure arcs — zero grid staircase.
## ribbon_stale keeps it on screen until the claimed polygon replaces it.
var ribbon: PackedVector2Array = PackedVector2Array()
var ribbon_stale: bool = false

var respawn_in: float = 0.0
var kills: int = 0

## Smooth steering (paper.io-2 style): heads move continuously with a turn
## radius; the grid only sees discrete cell-entry events.
var pos: Vector2 = Vector2.ZERO   # float world position (px)
var heading: float = 0.0          # radians

## Legacy fields kept for compatibility (cell interpolation era).
var prev_cx: int = 0
var prev_cy: int = 0

# ------------------------------------------------------------- bot "brain" ---
## Personality knobs, rolled per bot at spawn (0..1).
var greed := 0.5       # how big a loop it dares to draw
var caution := 0.5     # how early it runs home when threatened
var aggro := 0.5       # how eagerly it hunts enemy trails

## Planned excursion: a list of {dir: Vector2i, steps: int} legs. When the plan
## runs dry the bot heads home to close its loop.
var plan: Array = []
var going_home := false
