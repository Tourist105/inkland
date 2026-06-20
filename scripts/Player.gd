extends RefCounted

## One actor in the arena — the human or a bot. Pure data + intent;
## all world mutation happens in Arena.gd so the simulation stays in one place.

var id: int
var color: Color
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

## Visual interpolation: previous cell the head occupied last tick.
## The renderer lerps from (prev_cx, prev_cy) to (cx, cy) across one TICK so
## movement reads as fluid even though the sim is locked to the grid.
var prev_cx: int = 0
var prev_cy: int = 0
