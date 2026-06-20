extends Node2D
## Inkland core simulation + renderer.
##
## The arena is a W x H grid. Each cell stores an owner id (0 = neutral).
## A separate trail layer marks cells where a player is currently drawing a
## line outside their own land. Close the loop back into your land and every
## cell your line enclosed flips to your colour. Touch any trail (yours or an
## enemy's) and that trail's owner dies.
##
## This is the legal, original re-implementation of the territory-capture
## mechanic — own code, own art. No assets or trade dress from any other app.
##
## Rendering notes: the simulation runs on a fixed grid tick. The view is a
## Camera2D that smoothly chases the human head, so you play zoomed in on your
## character rather than seeing the whole board. Heads + trail-fronts are lerped
## between grid cells across each tick so motion looks fluid, not steppy.

const InkPlayer = preload("res://scripts/Player.gd")

const W := 56
const H := 96
const CELL := 20.0
const TICK := 0.10          # seconds the head spends crossing one cell
const RESPAWN := 1.6
const START_RADIUS := 2

const CAM_ZOOM := 2.6       # >1 zooms in (paper.io-style close view)
const CAM_LERP := 6.0       # camera follow stiffness

var grid: PackedByteArray          # owner id per cell, 0 = neutral
var trail_owner: PackedByteArray   # active-trail owner per cell, 0 = none
var players: Array[InkPlayer] = []
var human: InkPlayer
var _accum := 0.0
var _swipe_start := Vector2.ZERO

# A vibrant-but-original flat palette. Index 0 = neutral (unused as a fill).
var _palette := [
	Color(0.20, 0.55, 1.00),   # human  — azure
	Color(1.00, 0.42, 0.42),   # bot 1  — coral
	Color(0.30, 0.82, 0.55),   # bot 2  — mint
]
# Background & grid tones for a clean modern look.
const BG_TOP := Color(0.96, 0.97, 0.99)
const BG_BOT := Color(0.90, 0.93, 0.97)
const GRID_LINE := Color(0.0, 0.0, 0.0, 0.045)
const VOID := Color(0.78, 0.81, 0.86)   # outside-the-board frame

@onready var cam: Camera2D = $Camera2D
@onready var info: Label = $HUD/Info
@onready var pct_fill: ColorRect = $HUD/Panel/VBox/Bar/Fill
@onready var pct_label: Label = $HUD/Panel/VBox/PctLabel

func _ready() -> void:
	grid = PackedByteArray()
	grid.resize(W * H)
	trail_owner = PackedByteArray()
	trail_owner.resize(W * H)
	_spawn_players()
	if cam != null:
		cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
		cam.position = _cell_center(human.cx, human.cy)
		cam.make_current()
	_tint_hud()
	_update_info()

func idx(x: int, y: int) -> int:
	return y * W + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H

func _player(id: int) -> InkPlayer:
	return players[id - 1]

func _cell_center(x: int, y: int) -> Vector2:
	return Vector2(x * CELL + CELL * 0.5, y * CELL + CELL * 0.5)

# ---------------------------------------------------------------- spawning ---

func _spawn_players() -> void:
	var homes := [Vector2i(W / 2, H - 12), Vector2i(9, 12), Vector2i(W - 10, 16)]
	for i in 3:
		var p := InkPlayer.new()
		p.id = i + 1
		p.color = _palette[i]
		p.is_human = (i == 0)
		p.home = homes[i]
		players.append(p)
		_respawn(p)
	human = players[0]

func _respawn(p: InkPlayer) -> void:
	p.alive = true
	p.cx = p.home.x
	p.cy = p.home.y
	p.prev_cx = p.cx
	p.prev_cy = p.cy
	p.dir = Vector2i.UP if p.is_human else Vector2i.DOWN
	p.pending_dir = Vector2i.ZERO
	p.is_out = false
	p.trail.clear()
	for y in range(p.home.y - START_RADIUS, p.home.y + START_RADIUS + 1):
		for x in range(p.home.x - START_RADIUS, p.home.x + START_RADIUS + 1):
			if in_bounds(x, y):
				grid[idx(x, y)] = p.id

# ----------------------------------------------------------------- ticking ---

func _process(delta: float) -> void:
	_read_human_input()
	_accum += delta
	while _accum >= TICK:
		_accum -= TICK
		_tick()
	_update_camera(delta)
	queue_redraw()

## 0..1 progress of the current head through the cell it is moving into.
func _tick_alpha() -> float:
	return clampf(_accum / TICK, 0.0, 1.0)

func _tick() -> void:
	for p in players:
		if not p.alive:
			p.respawn_in -= TICK
			if p.respawn_in <= 0.0:
				_respawn(p)
			continue
		if not p.is_human:
			_bot_think(p)
		_step(p)
	_update_info()

func _step(p: InkPlayer) -> void:
	if p.pending_dir != Vector2i.ZERO and p.pending_dir != -p.dir:
		p.dir = p.pending_dir
	p.pending_dir = Vector2i.ZERO

	# Record where we were, for visual interpolation this tick.
	p.prev_cx = p.cx
	p.prev_cy = p.cy

	var nx := p.cx + p.dir.x
	var ny := p.cy + p.dir.y
	if not in_bounds(nx, ny):
		if p.is_out:
			_kill(p)          # ran into the wall mid-trail
		return                 # otherwise just idle against the edge this tick

	var ni := idx(nx, ny)

	# Crossing a live trail kills its owner.
	var to := trail_owner[ni]
	if to != 0:
		_kill(_player(to))
		if to == p.id:
			return             # we crossed our own line — we're done

	p.cx = nx
	p.cy = ny

	if grid[ni] == p.id:
		if p.is_out:
			_commit(p)         # closed the loop back home
			p.is_out = false
	else:
		p.is_out = true
		trail_owner[ni] = p.id
		p.trail.append(Vector2i(nx, ny))

func _kill(p: InkPlayer) -> void:
	if not p.alive:
		return
	p.alive = false
	p.respawn_in = RESPAWN
	for c in p.trail:
		trail_owner[idx(c.x, c.y)] = 0
	p.trail.clear()
	p.is_out = false
	for i in grid.size():            # land goes neutral, up for grabs
		if grid[i] == p.id:
			grid[i] = 0

# ------------------------------------------------------------- claim / fill --

func _commit(p: InkPlayer) -> void:
	# 1. The trail itself becomes owned land.
	for c in p.trail:
		var i := idx(c.x, c.y)
		grid[i] = p.id
		trail_owner[i] = 0
	p.trail.clear()

	# 2. Flood the "outside" from the border through every non-owned cell.
	#    Whatever the flood can't reach is enclosed -> it becomes ours.
	var visited := PackedByteArray()
	visited.resize(W * H)
	var stack: Array[int] = []
	for x in range(W):
		_seed(idx(x, 0), p.id, visited, stack)
		_seed(idx(x, H - 1), p.id, visited, stack)
	for y in range(H):
		_seed(idx(0, y), p.id, visited, stack)
		_seed(idx(W - 1, y), p.id, visited, stack)

	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % W
		var y := i / W
		for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var ax := x + d.x
			var ay := y + d.y
			if not in_bounds(ax, ay):
				continue
			var ai := idx(ax, ay)
			if visited[ai] == 0 and grid[ai] != p.id:
				visited[ai] = 1
				stack.append(ai)

	for i in range(W * H):
		if visited[i] == 0 and grid[i] != p.id:
			grid[i] = p.id

func _seed(i: int, owner: int, visited: PackedByteArray, stack: Array[int]) -> void:
	if grid[i] != owner and visited[i] == 0:
		visited[i] = 1
		stack.append(i)

# -------------------------------------------------------------------- bots ---

func _bot_think(p: InkPlayer) -> void:
	# Out and far from home -> curl back toward the home block to close a loop.
	if p.is_out and p.trail.size() >= 8:
		var hv := p.home - Vector2i(p.cx, p.cy)
		var want := Vector2i(signi(hv.x), 0) if absi(hv.x) > absi(hv.y) else Vector2i(0, signi(hv.y))
		if want != Vector2i.ZERO and want != -p.dir:
			p.pending_dir = want
		return
	# Wander, but don't drive into a wall.
	if randf() < 0.12:
		var opts := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		var pick: Vector2i = opts[randi() % 4]
		if pick != -p.dir:
			p.pending_dir = pick
	if not in_bounds(p.cx + p.dir.x, p.cy + p.dir.y):
		p.pending_dir = Vector2i(-p.dir.y, p.dir.x)

# -------------------------------------------------------------------- input --

func _read_human_input() -> void:
	if human == null or not human.alive:
		return
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		human.pending_dir = Vector2i.UP
	elif Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		human.pending_dir = Vector2i.DOWN
	elif Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		human.pending_dir = Vector2i.LEFT
	elif Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		human.pending_dir = Vector2i.RIGHT

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_start = event.position
	elif event is InputEventScreenDrag and human != null and human.alive:
		var d: Vector2 = event.position - _swipe_start
		if d.length() > 24.0:
			if absf(d.x) > absf(d.y):
				human.pending_dir = Vector2i.RIGHT if d.x > 0.0 else Vector2i.LEFT
			else:
				human.pending_dir = Vector2i.DOWN if d.y > 0.0 else Vector2i.UP
			_swipe_start = event.position

# ------------------------------------------------------------------- camera --

func _update_camera(delta: float) -> void:
	if cam == null or human == null:
		return
	# Follow the human's *interpolated* head so the camera glides.
	var target := _head_visual(human)
	var t := clampf(CAM_LERP * delta, 0.0, 1.0)
	cam.position = cam.position.lerp(target, t)

## The smoothed on-screen position of a player's head this frame.
func _head_visual(p: InkPlayer) -> Vector2:
	var from := _cell_center(p.prev_cx, p.prev_cy)
	var to := _cell_center(p.cx, p.cy)
	return from.lerp(to, _tick_alpha())

# ------------------------------------------------------------------- render --

func _update_info() -> void:
	var counts := [0, 0, 0, 0]
	for i in grid.size():
		counts[grid[i]] += 1
	var total := float(W * H)
	if info != null:
		info.text = "RED %.1f%%    MINT %.1f%%" % [
			counts[2] / total * 100.0,
			counts[3] / total * 100.0,
		]
	var you: float = float(counts[1]) / total * 100.0
	if pct_label != null:
		pct_label.text = "YOU  %.1f%%" % you
	if pct_fill != null:
		# Bar fill width tracks the human's share (0..100% of a 220px track).
		pct_fill.custom_minimum_size = Vector2(220.0 * clampf(you / 100.0, 0.0, 1.0), 16.0)

func _tint_hud() -> void:
	if info != null:
		info.add_theme_color_override("font_color", Color(0.20, 0.23, 0.30))
	if pct_label != null:
		pct_label.add_theme_color_override("font_color", _palette[0].darkened(0.15))
	if pct_fill != null:
		pct_fill.color = _palette[0]

func _draw() -> void:
	var board := Rect2(0, 0, W * CELL, H * CELL)
	# Void frame behind/around the board.
	draw_rect(Rect2(-CELL * 4, -CELL * 4, board.size.x + CELL * 8, board.size.y + CELL * 8), VOID)
	# Soft vertical gradient background for the playfield.
	_draw_vgradient(board, BG_TOP, BG_BOT)

	# Territory fills (flat) plus a darker outline on each region's exposed
	# edges — gives a clean, modern, slightly rounded silhouette.
	for y in range(H):
		for x in range(W):
			var o := grid[idx(x, y)]
			if o == 0:
				continue
			var base: Color = players[o - 1].color
			var fill := base
			fill.a = 0.88
			draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), fill)
	_draw_region_outlines()

	# Subtle grid lines for the paper-grid feel (drawn over fills, faint).
	for x in range(W + 1):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, H * CELL), GRID_LINE, 1.0)
	for y in range(H + 1):
		draw_line(Vector2(0, y * CELL), Vector2(W * CELL, y * CELL), GRID_LINE, 1.0)

	# Active trails: bright, rounded, slightly inset.
	for i in trail_owner.size():
		var t := trail_owner[i]
		if t != 0:
			var c: Color = players[t - 1].color
			var x := i % W
			var y := i / W
			var pad := CELL * 0.14
			_draw_rounded(Rect2(x * CELL + pad, y * CELL + pad, CELL - pad * 2, CELL - pad * 2), c, CELL * 0.28)

	# Heads — interpolated, with a soft drop shadow and (for the human) a face.
	for p in players:
		if p.alive:
			_draw_head(p)

func _draw_head(p: InkPlayer) -> void:
	var c := _head_visual(p)
	var r := CELL * 0.6
	# Shadow.
	draw_circle(c + Vector2(0, r * 0.18), r, Color(0, 0, 0, 0.16))
	# Body.
	draw_circle(c, r, p.color)
	draw_circle(c, r, p.color.lightened(0.25), false, 2.5)
	if p.is_human:
		_draw_face(c, r, p.dir)

## Two simple eyes that look in the direction of travel — original, genre-typical.
func _draw_face(c: Vector2, r: float, dir: Vector2i) -> void:
	var look := Vector2(dir.x, dir.y)
	if look == Vector2.ZERO:
		look = Vector2.UP
	# Perpendicular axis to place the two eyes side by side.
	var perp := Vector2(-look.y, look.x)
	var eye_off := perp * r * 0.42
	var fwd := look * r * 0.18
	var eye_r := r * 0.30
	var pupil_r := r * 0.15
	var pupil_shift := look * eye_r * 0.45
	for s: float in [1.0, -1.0]:
		var ec: Vector2 = c + eye_off * s + fwd
		draw_circle(ec, eye_r, Color.WHITE)
		draw_circle(ec + pupil_shift, pupil_r, Color(0.10, 0.12, 0.18))

# --- drawing helpers ---------------------------------------------------------

func _draw_vgradient(rect: Rect2, top: Color, bot: Color) -> void:
	# Cheap vertical gradient via a few horizontal bands.
	var bands := 24
	var bh := rect.size.y / bands
	for b in range(bands):
		var ct := top.lerp(bot, float(b) / float(bands - 1))
		draw_rect(Rect2(rect.position.x, rect.position.y + b * bh, rect.size.x, bh + 1.0), ct)

func _owned(x: int, y: int, owner: int) -> bool:
	return in_bounds(x, y) and grid[idx(x, y)] == owner

## Draw a darker border line along every edge where an owned cell meets a cell
## of a different owner. Cheap, robust, and gives each region a crisp outline.
func _draw_region_outlines() -> void:
	for y in range(H):
		for x in range(W):
			var o := grid[idx(x, y)]
			if o == 0:
				continue
			var edge: Color = players[o - 1].color.darkened(0.30)
			edge.a = 0.9
			var ox := x * CELL
			var oy := y * CELL
			if not _owned(x, y - 1, o):
				draw_line(Vector2(ox, oy), Vector2(ox + CELL, oy), edge, 2.0)
			if not _owned(x, y + 1, o):
				draw_line(Vector2(ox, oy + CELL), Vector2(ox + CELL, oy + CELL), edge, 2.0)
			if not _owned(x - 1, y, o):
				draw_line(Vector2(ox, oy), Vector2(ox, oy + CELL), edge, 2.0)
			if not _owned(x + 1, y, o):
				draw_line(Vector2(ox + CELL, oy), Vector2(ox + CELL, oy + CELL), edge, 2.0)

## A rounded-rect fill approximated by a plus-shape of two rects plus corner
## discs — used for trail segments so the active line reads soft, not blocky.
func _draw_rounded(rect: Rect2, col: Color, r: float) -> void:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - 2 * r, rect.size.y), col)
	draw_rect(Rect2(rect.position.x, rect.position.y + r, rect.size.x, rect.size.y - 2 * r), col)
	draw_circle(rect.position + Vector2(r, r), r, col)
	draw_circle(rect.position + Vector2(rect.size.x - r, r), r, col)
	draw_circle(rect.position + Vector2(r, rect.size.y - r), r, col)
	draw_circle(rect.position + Vector2(rect.size.x - r, rect.size.y - r), r, col)

