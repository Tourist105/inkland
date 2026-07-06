extends RefCounted

## One actor in the arena — the human or a bot. Pure data + intent;
## all world mutation happens in Arena.gd so the simulation stays in one place.

var id: int
var color: Color
var face: int = 0
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

var respawn_in: float = 0.0
var kills: int = 0

## Visual interpolation: previous cell the head occupied last tick.
## The renderer lerps from (prev_cx, prev_cy) to (cx, cy) across one TICK so
## movement reads as fluid even though the sim is locked to the grid.
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
