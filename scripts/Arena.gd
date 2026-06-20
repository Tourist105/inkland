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

const InkPlayer = preload("res://scripts/Player.gd")

const W := 36
const H := 64
const CELL := 20.0
const TICK := 0.08          # seconds the head spends crossing one cell
const RESPAWN := 1.6
const START_RADIUS := 2

var grid: PackedByteArray          # owner id per cell, 0 = neutral
var trail_owner: PackedByteArray   # active-trail owner per cell, 0 = none
var players: Array[InkPlayer] = []
var human: InkPlayer
var _accum := 0.0
var _swipe_start := Vector2.ZERO

@onready var info: Label = $HUD/Info

func _ready() -> void:
	grid = PackedByteArray()
	grid.resize(W * H)
	trail_owner = PackedByteArray()
	trail_owner.resize(W * H)
	_spawn_players()
	_update_info()

func idx(x: int, y: int) -> int:
	return y * W + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < W and y >= 0 and y < H

func _player(id: int) -> InkPlayer:
	return players[id - 1]

# ---------------------------------------------------------------- spawning ---

func _spawn_players() -> void:
	var palette := [
		Color(0.20, 0.55, 1.00),   # human  — blue
		Color(1.00, 0.36, 0.36),   # bot 1  — red
		Color(0.33, 0.85, 0.47),   # bot 2  — green
	]
	var homes := [Vector2i(W / 2, H - 9), Vector2i(7, 9), Vector2i(W - 8, 12)]
	for i in 3:
		var p := InkPlayer.new()
		p.id = i + 1
		p.color = palette[i]
		p.is_human = (i == 0)
		p.home = homes[i]
		players.append(p)
		_respawn(p)
	human = players[0]

func _respawn(p: InkPlayer) -> void:
	p.alive = true
	p.cx = p.home.x
	p.cy = p.home.y
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
	queue_redraw()

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

# ------------------------------------------------------------------- render --

func _update_info() -> void:
	var counts := [0, 0, 0, 0]
	for i in grid.size():
		counts[grid[i]] += 1
	var total := float(W * H)
	if info != null:
		info.text = "YOU %.1f%%    RED %.1f%%    GREEN %.1f%%" % [
			counts[1] / total * 100.0,
			counts[2] / total * 100.0,
			counts[3] / total * 100.0,
		]

func _draw() -> void:
	draw_rect(Rect2(0, 0, W * CELL, H * CELL), Color(0.12, 0.13, 0.16))
	for y in range(H):
		for x in range(W):
			var o := grid[idx(x, y)]
			if o != 0:
				var col: Color = players[o - 1].color
				col.a = 0.55
				draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), col)
	for i in trail_owner.size():
		var t := trail_owner[i]
		if t != 0:
			draw_rect(Rect2((i % W) * CELL, (i / W) * CELL, CELL, CELL), players[t - 1].color)
	for p in players:
		if p.alive:
			var c := Vector2(p.cx * CELL + CELL * 0.5, p.cy * CELL + CELL * 0.5)
			draw_circle(c, CELL * 0.55, p.color)
			draw_circle(c, CELL * 0.55, Color(0, 0, 0, 0.5), false, 2.0)
