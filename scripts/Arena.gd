extends Node2D
## Inkland core simulation + renderer + round flow.
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
## Round flow: COUNTDOWN -> PLAYING -> (PAUSED) -> OVER (continue-offer ->
## results). The human's death ends the round; bots respawn forever.

const InkPlayer = preload("res://scripts/Player.gd")

const W := 56
const H := 96
const CELL := 20.0
const TICK := 0.10          # bot-brain cadence (movement itself is continuous)
const SPEED := 200.0        # px/s — one cell per TICK, like the grid era
const TURN_RATE := 4.8      # rad/s, human (paper.io-2-style arc turns)
const BOT_TURN := 4.0
const RESPAWN := 2.0
const START_RADIUS := 2
const BOT_COUNT := 5

const CAM_ZOOM := 2.6       # >1 zooms in (close chase view)
const CAM_LERP := 6.0       # camera follow stiffness

const BOT_NAMES := ["Momo", "Rex", "Ziggy", "Nori", "Pip", "Kato", "Luna", "Bolt"]
const BOT_COLORS := [
	Color(1.00, 0.42, 0.42),   # coral
	Color(0.30, 0.82, 0.55),   # mint
	Color(1.00, 0.72, 0.20),   # amber
	Color(0.62, 0.44, 0.98),   # violet
	Color(0.18, 0.75, 0.80),   # teal
	Color(0.95, 0.40, 0.75),   # magenta
	Color(0.62, 0.85, 0.25),   # lime
]

# Background & grid tones for a clean modern look.
const BG_TOP := Color(0.96, 0.97, 0.99)
const BG_BOT := Color(0.90, 0.93, 0.97)
const GRID_LINE := Color(0.0, 0.0, 0.0, 0.045)
const VOID := Color(0.78, 0.81, 0.86)   # outside-the-board frame

enum State { COUNTDOWN, PLAYING, PAUSED, OVER }

var grid: PackedByteArray          # owner id per cell, 0 = neutral
var trail_owner: PackedByteArray   # active-trail owner per cell, 0 = none
var players: Array[InkPlayer] = []
var human: InkPlayer
var state: int = State.COUNTDOWN

var _accum := 0.0
var _swipe_start := Vector2.ZERO
var _human_target := 0.0          # drag steering angle (radians)
var _human_has_target := false
var _count_t := 3.0
var _go_flash := 0.0
var _shake := 0.0
var _max_pct := 0.0
var _revive_used := false
var _doubled := false
var _best_flashed := false
var _earned := 0
var _final_pct := 0.0
var _counts: Array[int] = []

# Juice: fading white flash on freshly captured cells, floating texts, rings.
var _flash := {}                   # cell index -> remaining seconds
var _fx: Array[Dictionary] = []

@onready var cam: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD

# HUD nodes (built in code in _build_hud)
var _pct_label: Label
var _bar_fill: Panel
var _lb_dots: Array[Panel] = []
var _lb_labels: Array[Label] = []
var _minimap: MiniMap
var _info_acc := 0.0
var _count_label: Label
var _hint_label: Label
var _dim: ColorRect
var _pause_panel: PanelContainer
var _continue_panel: PanelContainer
var _results_panel: PanelContainer

func _ready() -> void:
	randomize()
	grid = PackedByteArray()
	grid.resize(W * H)
	trail_owner = PackedByteArray()
	trail_owner.resize(W * H)
	_counts.resize(BOT_COUNT + 2)
	_spawn_players()
	if cam != null:
		cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
		cam.position = _cell_center(human.cx, human.cy)
		cam.limit_left = int(-CELL * 3)
		cam.limit_top = int(-CELL * 3)
		cam.limit_right = int(W * CELL + CELL * 3)
		cam.limit_bottom = int(H * CELL + CELL * 3)
		cam.make_current()
	_build_hud()
	Ads.hide_banner()          # never over the arena
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
	var skin: Dictionary = Game.skin()
	var me := InkPlayer.new()
	me.id = 1
	me.color = skin.color
	me.face = skin.face
	me.is_human = true
	me.display_name = tr("T_YOU")
	me.home = Vector2i(W / 2, H - 14)
	players.append(me)
	human = me

	var colors := _bot_palette(skin.color)
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var homes := [
		Vector2i(10, 12), Vector2i(W - 11, 14), Vector2i(9, H / 2),
		Vector2i(W - 10, H / 2 + 6), Vector2i(W / 2, 16),
	]
	# Difficulty scales with the player's proven skill (best %): rookies get
	# timid bots, record-chasers get hunters. Keeps rounds tense but fair.
	var skill := clampf(Game.best_pct / 60.0, 0.0, 1.0)
	for i in BOT_COUNT:
		var b := InkPlayer.new()
		b.id = i + 2
		b.color = colors[i]
		b.face = randi() % 6
		b.display_name = names[i]
		b.home = homes[i]
		b.greed = randf_range(0.2 + 0.3 * skill, 1.0)
		b.caution = randf_range(0.2, 1.0 - 0.35 * skill)
		b.aggro = randf_range(0.1 + 0.45 * skill, 1.0)
		players.append(b)
	for p in players:
		_respawn(p)

## Bot colours, avoiding anything too close to the human's skin colour.
func _bot_palette(mine: Color) -> Array:
	var pool := []
	for c: Color in BOT_COLORS:
		if absf(angle_difference(c.h * TAU, mine.h * TAU)) > 0.55 or absf(c.v - mine.v) > 0.45:
			pool.append(c)
	pool.shuffle()
	while pool.size() < BOT_COUNT:
		pool.append(BOT_COLORS[pool.size() % BOT_COLORS.size()])
	return pool.slice(0, BOT_COUNT)

func _respawn(p: InkPlayer) -> void:
	if not p.is_human:
		var spot := _find_free_spot()
		if spot != Vector2i(-1, -1):
			p.home = spot
	p.alive = true
	p.cx = p.home.x
	p.cy = p.home.y
	p.pos = _cell_center(p.cx, p.cy)
	p.dir = Vector2i.UP if p.cy > H / 2 else Vector2i.DOWN
	p.heading = Vector2(p.dir).angle()
	p.pending_dir = Vector2i.ZERO
	if p.is_human:
		_human_has_target = false
	p.is_out = false
	p.going_home = false
	p.plan.clear()
	p.trail.clear()
	var rad := START_RADIUS
	if p.is_human and Game.start_boost:
		rad = 5                        # rewarded "start big" (~5x area)
		Game.start_boost = false
		Game.save_state()
	for y in range(p.home.y - rad, p.home.y + rad + 1):
		for x in range(p.home.x - rad, p.home.x + rad + 1):
			if in_bounds(x, y):
				grid[idx(x, y)] = p.id

## A random mostly-neutral 5x5 patch, or (-1,-1) if none found.
func _find_free_spot() -> Vector2i:
	for _try in 40:
		var x := randi_range(START_RADIUS + 2, W - START_RADIUS - 3)
		var y := randi_range(START_RADIUS + 2, H - START_RADIUS - 3)
		var ok := true
		for dy in range(-START_RADIUS, START_RADIUS + 1):
			for dx in range(-START_RADIUS, START_RADIUS + 1):
				var i := idx(x + dx, y + dy)
				if grid[i] != 0 or trail_owner[i] != 0:
					ok = false
					break
			if not ok:
				break
		if ok:
			return Vector2i(x, y)
	return Vector2i(-1, -1)

# ----------------------------------------------------------------- ticking ---

func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_read_human_input()
			_count_t -= delta
			if _count_t <= 0.0:
				state = State.PLAYING
				_go_flash = 0.7
				_count_label.text = tr("T_GO")
				Sfx.play("go")
			else:
				var n := int(ceil(_count_t))
				if _count_label.text != str(n):
					_count_label.text = str(n)
					Sfx.play("tick")
			_update_camera(delta)
			queue_redraw()
		State.PLAYING:
			if _go_flash > 0.0:
				_go_flash -= delta
				if _go_flash <= 0.0:
					_count_label.visible = false
					_hint_label.visible = false
			_read_human_input()
			_accum += delta
			while _accum >= TICK and state == State.PLAYING:
				_accum -= TICK
				_think_tick()
			if state == State.PLAYING:
				_move_actors(minf(delta, 1.0 / 30.0))
				_info_acc += delta
				if _info_acc >= 0.1:      # counts + minimap at 10 Hz
					_info_acc = 0.0
					_update_info()
					_minimap.refresh()
			_age_fx(delta)
			_update_camera(delta)
			queue_redraw()
		_:
			pass   # PAUSED / OVER: everything freezes

## Bot brains + respawn timers run on the old grid cadence.
func _think_tick() -> void:
	for p in players:
		if not p.alive:
			p.respawn_in -= TICK
			if p.respawn_in <= 0.0:
				_respawn(p)
			continue
		if not p.is_human:
			_bot_think(p)

## Continuous paper.io-2-style movement: heads fly at SPEED with a turn
## radius; the grid only reacts to discrete cell-entry events.
func _move_actors(dt: float) -> void:
	for p in players:
		if state != State.PLAYING:
			return
		if not p.alive:
			continue
		# Steering target: human drag angle or the (bot/keyboard) grid intent.
		var target := p.heading
		if p.is_human and _human_has_target:
			target = _human_target
		elif p.pending_dir != Vector2i.ZERO:
			target = Vector2(p.pending_dir).angle()
		var diff := angle_difference(p.heading, target)
		var rate := (TURN_RATE if p.is_human else BOT_TURN) * dt
		p.heading += clampf(diff, -rate, rate)
		p.pos += Vector2.from_angle(p.heading) * SPEED * dt
		p.dir = _cardinal(p.heading)          # bots' brain works in cardinals

		# Board edge: sliding is fine inside your land, fatal mid-trail.
		var m := CELL * 0.5
		var clamped := Vector2(clampf(p.pos.x, m, W * CELL - m),
			clampf(p.pos.y, m, H * CELL - m))
		if clamped != p.pos:
			p.pos = clamped
			if p.is_out:
				_kill(p, null, "wall")
				continue
		# Cell-entry events (one axis at a time — no corner skipping).
		var nx := int(p.pos.x / CELL)
		var ny := int(p.pos.y / CELL)
		while (p.cx != nx or p.cy != ny) and p.alive and state == State.PLAYING:
			if p.cx != nx:
				_enter_cell(p, p.cx + signi(nx - p.cx), p.cy)
			else:
				_enter_cell(p, p.cx, p.cy + signi(ny - p.cy))

static func _cardinal(heading: float) -> Vector2i:
	var v := Vector2.from_angle(heading)
	if absf(v.x) >= absf(v.y):
		return Vector2i(signi(int(signf(v.x))), 0) if v.x != 0.0 else Vector2i.RIGHT
	return Vector2i(0, signi(int(signf(v.y))))

func _enter_cell(p: InkPlayer, nx: int, ny: int) -> void:
	var ni := idx(nx, ny)
	# Crossing a live trail kills its owner.
	var to := trail_owner[ni]
	if to != 0:
		var victim := _player(to)
		if to != p.id:
			p.kills += 1
			if p.is_human:
				Sfx.play("kill")
				Sfx.haptic(60)
				_add_text_fx(_cell_center(nx, ny), "+1", p.color)
			_kill(victim, p, "cut")
		else:
			_kill(victim, null, "self")
			return                      # we crossed our own line — done
	if state != State.PLAYING or not p.alive:
		return
	p.cx = nx
	p.cy = ny
	if grid[ni] == p.id:
		if p.is_out:
			_commit(p)                  # closed the loop back home
			p.is_out = false
			p.going_home = false
			p.plan.clear()
	else:
		p.is_out = true
		trail_owner[ni] = p.id
		p.trail.append(Vector2i(nx, ny))

func _kill(p: InkPlayer, killer: InkPlayer, cause: String) -> void:
	if not p.alive:
		return
	for c in p.trail:
		trail_owner[idx(c.x, c.y)] = 0
	p.trail.clear()
	p.is_out = false
	if p.is_human:
		_human_died(cause, killer)      # land stays put (revive keeps it)
		return
	p.alive = false
	p.respawn_in = RESPAWN
	for i in grid.size():               # bot land goes neutral, up for grabs
		if grid[i] == p.id:
			grid[i] = 0
	_add_ring_fx(_cell_center(p.cx, p.cy), p.color)
	if _on_screen(_cell_center(p.cx, p.cy)):
		_shake = maxf(_shake, 5.0)

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

	var gained := 0
	for i in range(W * H):
		if visited[i] == 0 and grid[i] != p.id:
			grid[i] = p.id
			gained += 1
			_flash[i] = 0.45
	if gained > 0 and p.is_human:
		Sfx.play("capture", 0.9 + randf() * 0.2)
		Sfx.haptic(25)
		var pct := gained * 100.0 / float(W * H)
		_add_text_fx(_head_visual(p) - Vector2(0, CELL * 1.4),
			"+%.1f%%" % pct, p.color.darkened(0.2))

func _seed(i: int, owner: int, visited: PackedByteArray, stack: Array[int]) -> void:
	if grid[i] != owner and visited[i] == 0:
		visited[i] = 1
		stack.append(i)

# -------------------------------------------------------------------- bots ---
## Per-tick bot brain. Personality knobs: greed (loop size), caution (when to
## flee home), aggro (hunting enemy trails).

func _bot_think(p: InkPlayer) -> void:
	# Hunt: cut an adjacent enemy trail, or chase one spotted nearby.
	if randf() < 0.25 + p.aggro * 0.6:
		if _try_cut(p):
			return
		var hunt := _find_enemy_trail(p, 6)
		if hunt.x >= 0 and (not p.is_out or p.trail.size() < 14):
			_steer(p, _axis_dir(p, hunt))
			return
	if p.is_out:
		var max_out := 8 + int(p.greed * 18.0)
		if p.trail.size() >= max_out or p.plan.is_empty():
			p.going_home = true
		if not p.going_home and _threat_dist(p) < 3.0 + p.caution * 4.0:
			p.going_home = true
		if p.going_home:
			_steer(p, _dir_home(p))
		else:
			_follow_plan(p)
	else:
		p.going_home = false
		if p.plan.is_empty() and randf() < 0.10 + p.greed * 0.08:
			_make_plan(p)
		if not p.plan.is_empty():
			_follow_plan(p)
		elif randf() < 0.25:
			_steer(p, _dir_toward(p, p.home))

## Plan a rectangular excursion: out, across, and back toward the territory.
func _make_plan(p: InkPlayer) -> void:
	var d0 := _open_dir(p)
	var perp := Vector2i(-d0.y, d0.x) if randf() < 0.5 else Vector2i(d0.y, -d0.x)
	var a := 3 + int(randf() * (3.0 + p.greed * 7.0))
	var b := 2 + int(randf() * (2.0 + p.greed * 6.0))
	p.plan = [
		{"dir": d0, "steps": a},
		{"dir": perp, "steps": b},
		{"dir": -d0, "steps": a},
	]

func _follow_plan(p: InkPlayer) -> void:
	if p.plan.is_empty():
		return
	var leg: Dictionary = p.plan[0]
	_steer(p, leg.dir)
	leg.steps -= 1
	if leg.steps <= 0:
		p.plan.pop_front()

## The direction with the most non-owned space ahead of the head.
func _open_dir(p: InkPlayer) -> Vector2i:
	var best := p.dir
	var best_score := -1
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if d == -p.dir:
			continue
		var score := 0
		for s in range(1, 9):
			var x := p.cx + d.x * s
			var y := p.cy + d.y * s
			if not in_bounds(x, y):
				break
			if grid[idx(x, y)] != p.id:
				score += 1
		if score > best_score:
			best_score = score
			best = d
	return best

## Steer toward `want`, falling back to any survivable direction.
func _steer(p: InkPlayer, want: Vector2i) -> void:
	var side := Vector2i(-p.dir.y, p.dir.x)
	for d: Vector2i in [want, p.dir, side, -side]:
		if d == Vector2i.ZERO or d == -p.dir:
			continue
		if not _safe_cell(p, p.cx + d.x, p.cy + d.y):
			continue
		# Mid-trail, also look two cells ahead so arcs don't drift into walls.
		if p.is_out and not in_bounds(p.cx + d.x * 2, p.cy + d.y * 2):
			continue
		p.pending_dir = d
		return
	# Nothing is safe — keep going and hope.

func _safe_cell(p: InkPlayer, x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return trail_owner[idx(x, y)] != p.id   # own trail = certain death

## Nearest enemy trail cell within a scan window (for hunting).
func _find_enemy_trail(p: InkPlayer, radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 999
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x := p.cx + dx
			var y := p.cy + dy
			if not in_bounds(x, y):
				continue
			var to := trail_owner[idx(x, y)]
			if to != 0 and to != p.id:
				var d := absi(dx) + absi(dy)
				if d < bd:
					bd = d
					best = Vector2i(x, y)
	return best

## Step onto an adjacent enemy trail if there is one (a free kill).
func _try_cut(p: InkPlayer) -> bool:
	for d: Vector2i in [p.dir, Vector2i(-p.dir.y, p.dir.x), Vector2i(p.dir.y, -p.dir.x)]:
		var x := p.cx + d.x
		var y := p.cy + d.y
		if not in_bounds(x, y):
			continue
		var to := trail_owner[idx(x, y)]
		if to != 0 and to != p.id:
			p.pending_dir = d
			return true
	return false

## Manhattan distance from the nearest enemy head to us or our trail.
func _threat_dist(p: InkPlayer) -> float:
	var best := 9999
	for e in players:
		if e == p or not e.alive:
			continue
		var hd: int = absi(e.cx - p.cx) + absi(e.cy - p.cy)
		best = mini(best, hd)
		var stride := maxi(1, p.trail.size() / 30)
		var k := 0
		while k < p.trail.size():
			var c: Vector2i = p.trail[k]
			best = mini(best, absi(e.cx - c.x) + absi(e.cy - c.y))
			k += stride
	return float(best)

func _dir_home(p: InkPlayer) -> Vector2i:
	var target := p.home
	if grid[idx(target.x, target.y)] != p.id:
		target = _nearest_owned(p)
		if target == Vector2i(-1, -1):
			return p.dir            # no land left — doomed, keep running
		p.home = target
	return _axis_dir(p, target)

func _dir_toward(p: InkPlayer, target: Vector2i) -> Vector2i:
	return _axis_dir(p, target)

func _axis_dir(p: InkPlayer, target: Vector2i) -> Vector2i:
	var dx := target.x - p.cx
	var dy := target.y - p.cy
	if dx == 0 and dy == 0:
		return p.dir
	if absi(dx) >= absi(dy) and dx != 0:
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dy))

func _nearest_owned(p: InkPlayer) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999999
	for i in grid.size():
		if grid[i] == p.id:
			var x := i % W
			var y := i / W
			var d: int = absi(x - p.cx) + absi(y - p.cy)
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best

# -------------------------------------------------------------------- input --

func _read_human_input() -> void:
	if human == null or not human.alive:
		return
	var kb := Vector2i.ZERO
	if Input.is_action_pressed("ui_up") or Input.is_physical_key_pressed(KEY_W):
		kb.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_physical_key_pressed(KEY_S):
		kb.y += 1
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		kb.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		kb.x += 1
	if kb != Vector2i.ZERO:
		human.pending_dir = kb
		_human_has_target = false

func _input(event: InputEvent) -> void:
	if state != State.PLAYING and state != State.COUNTDOWN:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_start = event.position
	elif event is InputEventScreenDrag and human != null and human.alive:
		# Analog steering, paper.io-2 style: the drag vector from the touch
		# origin sets the heading directly — arcs, not 4 directions.
		var d: Vector2 = event.position - _swipe_start
		if d.length() > 14.0:
			_human_target = d.angle()
			_human_has_target = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match state:
			State.PLAYING:
				_set_paused(true)
			State.PAUSED:
				_set_paused(false)

# --------------------------------------------------------------- round flow --

func _human_died(cause: String, killer: InkPlayer) -> void:
	human.alive = false
	state = State.OVER
	Sfx.play("death")
	Sfx.haptic(140)
	_shake = 8.0
	_add_ring_fx(_cell_center(human.cx, human.cy), human.color)
	var killer_name := killer.display_name if killer != null else ""
	var subtitle := ""
	match cause:
		"self": subtitle = tr("T_RES_SELF")
		"wall": subtitle = tr("T_RES_WALL")
		_: subtitle = tr("T_RES_KILLED") % killer_name
	if not _revive_used and Ads.rewarded_ready():
		_show_continue_offer(subtitle)
	else:
		_show_results(subtitle, false)

func _round_won() -> void:
	state = State.OVER
	Sfx.play("coin")
	Sfx.haptic(80)
	_show_results(tr("T_RES_WIN"), true)

func _revive() -> void:
	_revive_used = true
	_continue_panel.visible = false
	_dim.visible = false
	human.alive = true
	# Respawn inside remaining land if any, else on a fresh neutral patch.
	var spot := _nearest_owned(human)
	if spot == Vector2i(-1, -1):
		spot = _find_free_spot()
		if spot == Vector2i(-1, -1):
			spot = human.home
		human.home = spot
		for y in range(spot.y - START_RADIUS, spot.y + START_RADIUS + 1):
			for x in range(spot.x - START_RADIUS, spot.x + START_RADIUS + 1):
				if in_bounds(x, y):
					grid[idx(x, y)] = human.id
	else:
		human.home = spot
	human.cx = spot.x
	human.cy = spot.y
	human.pos = _cell_center(spot.x, spot.y)
	human.heading = -PI * 0.5
	_human_has_target = false
	human.is_out = false
	human.trail.clear()
	human.pending_dir = Vector2i.ZERO
	if cam != null:
		cam.position = _cell_center(spot.x, spot.y)
	_count_t = 1.2
	_count_label.text = "1"
	_count_label.visible = true
	state = State.COUNTDOWN

func _set_paused(on: bool) -> void:
	if state != State.PLAYING and state != State.PAUSED:
		return
	Sfx.play("click")
	state = State.PAUSED if on else State.PLAYING
	_dim.visible = on
	_pause_panel.visible = on

func _go_home() -> void:
	Sfx.play("click")
	get_tree().change_scene_to_file("res://scenes/Home.tscn")

func _retry() -> void:
	Sfx.play("click")
	get_tree().reload_current_scene()

# ------------------------------------------------------------------ results --

func _you_pct() -> float:
	return _counts[1] * 100.0 / float(W * H) if _counts.size() > 1 else 0.0

func _show_continue_offer(subtitle: String) -> void:
	_dim.visible = true
	_continue_panel.visible = true
	_continue_panel.get_node("V/Sub").text = subtitle
	# Auto-fall-through to results if the player waits it out. Bound method
	# (not a lambda) so the callable dies with the scene on Retry/Home.
	get_tree().create_timer(6.0).timeout.connect(_continue_timed_out.bind(subtitle))

func _continue_timed_out(subtitle: String) -> void:
	if state == State.OVER and _continue_panel.visible:
		_continue_panel.visible = false
		_show_results(subtitle, false)

func _show_results(subtitle: String, won: bool) -> void:
	_final_pct = _you_pct()
	_max_pct = maxf(_max_pct, _final_pct)
	_earned = int(_max_pct) + human.kills * 5
	Game.add_coins(_earned)
	var is_best := Game.submit_round(_max_pct, human.kills)
	if _earned > 0:
		Sfx.play("coin")

	var v: VBoxContainer = _results_panel.get_node("V")
	(v.get_node("Title") as Label).text = tr("T_RES_WIN") if won else subtitle
	(v.get_node("Pct") as Label).text = "%.1f%%" % _final_pct
	(v.get_node("Best") as Label).visible = is_best
	var prev_country: String = Game.COUNTRIES[Game.country_idx].name
	var cbonus := Game.add_country_progress(_max_pct)
	var cd: Dictionary = Game.COUNTRIES[Game.country_idx]
	var cline := "%s  %d/%d%%" % [cd.name, int(Game.country_fill), int(cd.size)]
	if cbonus > 0:
		cline = (tr("T_CONQUERED") % prev_country) + "  +%d
%s" % [cbonus, cline]
	(v.get_node("Stats") as Label).text = "%s  %d      %s  %.1f%%
%s" % [
		tr("T_KILLS"), human.kills, tr("T_BEST"), Game.best_pct, cline]
	(v.get_node("CoinsRow") as HBoxContainer).visible = _earned > 0
	(v.get_node("CoinsRow/Amount") as Label).text = "+%d" % _earned
	var dbl: Button = v.get_node("Double")
	dbl.visible = Ads.rewarded_ready() and _earned > 0
	dbl.disabled = false
	_dim.visible = true
	_results_panel.visible = true

func _double_coins() -> void:
	if _doubled:
		return
	var dbl: Button = _results_panel.get_node("V/Double")
	dbl.disabled = true
	Ads.show_rewarded(func() -> void:
		_doubled = true
		Game.add_coins(_earned)
		(_results_panel.get_node("V/CoinsRow/Amount") as Label).text = "+%d" % (_earned * 2)
		dbl.visible = false
		Sfx.play("coin"))

# ------------------------------------------------------------------- camera --

func _update_camera(delta: float) -> void:
	if cam == null or human == null:
		return
	var target := _head_visual(human)
	var t := clampf(CAM_LERP * delta, 0.0, 1.0)
	cam.position = cam.position.lerp(target, t)
	if _shake > 0.1:
		_shake *= exp(-7.0 * delta)
		cam.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	else:
		cam.offset = Vector2.ZERO

## Head position on screen — continuous since the smooth-steering rewrite.
func _head_visual(p: InkPlayer) -> Vector2:
	return p.pos

func _on_screen(world_pos: Vector2) -> bool:
	return cam != null and world_pos.distance_to(cam.position) < 420.0

# ---------------------------------------------------------------------- fx ---

func _add_text_fx(pos: Vector2, text: String, color: Color) -> void:
	_fx.append({"kind": "text", "pos": pos, "text": text, "color": color, "t": 0.9})

func _add_ring_fx(pos: Vector2, color: Color) -> void:
	_fx.append({"kind": "ring", "pos": pos, "color": color, "t": 0.5})

func _age_fx(delta: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		_fx[i].t -= delta
		if _fx[i].t <= 0.0:
			_fx.remove_at(i)
	var dead: Array = []
	for k in _flash:
		_flash[k] -= delta
		if _flash[k] <= 0.0:
			dead.append(k)
	for k in dead:
		_flash.erase(k)

# --------------------------------------------------------------------- HUD ---

func _update_info() -> void:
	for i in _counts.size():
		_counts[i] = 0
	for i in grid.size():
		_counts[grid[i]] += 1
	var total := float(W * H)
	var you := _counts[1] * 100.0 / total
	_max_pct = maxf(_max_pct, you)
	if _pct_label != null:
		_pct_label.text = "%.1f%%" % you
	if _bar_fill != null:
		_bar_fill.size = Vector2(206.0 * clampf(you / 100.0, 0.0, 1.0), 14.0)
	# Leaderboard: top 3 by territory.
	var order: Array = []
	for p in players:
		order.append([_counts[p.id], p])
	order.sort_custom(func(a, b): return a[0] > b[0])
	# Live rank next to your % — the paper.io "am I winning?" pulse.
	for r2 in order.size():
		if order[r2][1] == human:
			_pct_label.text = "%.1f%%   #%d" % [you, r2 + 1]
			break
	for r in 3:
		if r >= _lb_labels.size():
			break
		var cnt: int = order[r][0]
		var p: InkPlayer = order[r][1]
		_lb_labels[r].text = "%s %.1f%%" % [p.display_name, cnt * 100.0 / total]
		var sb: StyleBoxFlat = _lb_dots[r].get_theme_stylebox("panel")
		sb.bg_color = p.color
	# Live "new best" moment the instant the old record falls mid-run.
	if not _best_flashed and state == State.PLAYING \
			and Game.best_pct > 1.0 and you > Game.best_pct:
		_best_flashed = true
		_add_text_fx(_head_visual(human) - Vector2(0, CELL * 2.4),
			tr("T_NEW_BEST"), Ui.GOLD.darkened(0.1))
		Sfx.play("coin")
		Sfx.haptic(40)
	if state == State.PLAYING and you >= 99.95:
		_round_won()

func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	# Pause button, top-left.
	var pause_btn := IconButton.make("pause", Color(0.13, 0.16, 0.24, 0.55), 68.0)
	pause_btn.position = Vector2(16, 16)
	pause_btn.pressed.connect(func() -> void: _set_paused(true))
	root.add_child(pause_btn)

	# Score pill, top-centre.
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", Ui.card(Color(1, 1, 1, 0.85), 18))
	pill.anchor_left = 0.5
	pill.anchor_right = 0.5
	pill.offset_left = -115
	pill.offset_right = 115
	pill.offset_top = 14
	root.add_child(pill)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	pill.add_child(pv)
	_pct_label = Ui.label("0.0%", 30, Ui.INK)
	pv.add_child(_pct_label)
	var track := Panel.new()
	var track_sb := StyleBoxFlat.new()
	track_sb.bg_color = Ui.PAPER_DIM
	track_sb.set_corner_radius_all(7)
	track.add_theme_stylebox_override("panel", track_sb)
	track.custom_minimum_size = Vector2(206, 14)
	pv.add_child(track)
	_bar_fill = Panel.new()
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = Game.skin().color
	fill_sb.set_corner_radius_all(7)
	_bar_fill.add_theme_stylebox_override("panel", fill_sb)
	_bar_fill.size = Vector2(0, 14)
	track.add_child(_bar_fill)

	# Leaderboard, top-right.
	var lb := PanelContainer.new()
	lb.add_theme_stylebox_override("panel", Ui.card(Color(1, 1, 1, 0.85), 18))
	lb.anchor_left = 1.0
	lb.anchor_right = 1.0
	lb.offset_left = -226
	lb.offset_right = -14
	lb.offset_top = 118          # below the score pill (narrow 20:9 screens)
	root.add_child(lb)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lb.add_child(lv)
	for r in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := Panel.new()
		var dsb := StyleBoxFlat.new()
		dsb.bg_color = Ui.INK_SOFT
		dsb.set_corner_radius_all(7)
		dot.add_theme_stylebox_override("panel", dsb)
		dot.custom_minimum_size = Vector2(14, 14)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var lab := Ui.label("—", 17, Ui.INK)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(lab)
		lv.add_child(row)
		_lb_dots.append(dot)
		_lb_labels.append(lab)

	# Minimap — whole-arena overview, top right under the leaderboard.
	_minimap = MiniMap.new()
	_minimap.setup(self)
	_minimap.anchor_left = 1.0
	_minimap.anchor_right = 1.0
	_minimap.offset_left = -108
	_minimap.offset_right = -16
	_minimap.offset_top = 238
	_minimap.offset_bottom = 396
	root.add_child(_minimap)
	_minimap.refresh()

	# Countdown / GO, centred.
	_count_label = Ui.label("3", 130, Ui.INK)
	_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	_count_label.add_theme_constant_override("outline_size", 16)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_count_label)

	# Steering hint (shown until GO fades).
	_hint_label = Ui.label(tr("T_HINT_STEER"), 24, Ui.INK_SOFT)
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.anchor_right = 1.0
	_hint_label.offset_top = -140
	_hint_label.offset_bottom = -100
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint_label)

	# Modal dim + panels.
	_dim = Ui.dim()
	_dim.visible = false
	root.add_child(_dim)
	_pause_panel = _build_pause_panel()
	root.add_child(_pause_panel)
	_continue_panel = _build_continue_panel()
	root.add_child(_continue_panel)
	_results_panel = _build_results_panel()
	root.add_child(_results_panel)

func _center_panel(min_w: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.card(Ui.PAPER, 26))
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -min_w * 0.5
	p.offset_right = min_w * 0.5
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.visible = false
	return p

func _build_pause_panel() -> PanelContainer:
	var p := _center_panel(400)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	v.add_child(Ui.label(tr("T_PAUSED"), 40, Ui.INK))
	var resume := Button.new()
	resume.text = tr("T_RESUME")
	Ui.style_button(resume, Ui.ACCENT, 30)
	resume.pressed.connect(func() -> void: _set_paused(false))
	v.add_child(resume)
	var home := Button.new()
	home.text = tr("T_HOME")
	Ui.style_button(home, Ui.INK_SOFT, 26)
	home.pressed.connect(_go_home)
	v.add_child(home)
	return p

func _build_continue_panel() -> PanelContainer:
	var p := _center_panel(430)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var sub := Ui.label("", 22, Ui.INK_SOFT)
	sub.name = "Sub"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)
	var cont := Button.new()
	cont.text = tr("T_REVIVE") + "  (AD)"
	Ui.style_button(cont, Color(0.16, 0.72, 0.42), 30)
	cont.pressed.connect(func() -> void:
		Sfx.play("click")
		Ads.show_rewarded(_revive))
	v.add_child(cont)
	var skip := Button.new()
	skip.text = tr("T_BACK")
	Ui.style_button(skip, Ui.INK_SOFT, 24)
	skip.pressed.connect(func() -> void:
		Sfx.play("click")
		_continue_panel.visible = false
		_show_results((_continue_panel.get_node("V/Sub") as Label).text, false))
	v.add_child(skip)
	return p

func _build_results_panel() -> PanelContainer:
	var p := _center_panel(470)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)

	var title := Ui.label("", 30, Ui.INK)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)

	var pct := Ui.label("0.0%", 72, Ui.ACCENT)
	pct.name = "Pct"
	v.add_child(pct)

	var best := Ui.label(tr("T_NEW_BEST"), 26, Ui.GOLD.darkened(0.15))
	best.name = "Best"
	best.visible = false
	v.add_child(best)

	var stats := Ui.label("", 20, Ui.INK_SOFT)
	stats.name = "Stats"
	v.add_child(stats)

	var coins_row := HBoxContainer.new()
	coins_row.name = "CoinsRow"
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_theme_constant_override("separation", 10)
	coins_row.add_child(CoinIcon.make(34))
	var amount := Ui.label("+0", 30, Ui.INK)
	amount.name = "Amount"
	coins_row.add_child(amount)
	v.add_child(coins_row)

	var dbl := Button.new()
	dbl.name = "Double"
	dbl.text = tr("T_DOUBLE") + "  (AD)"
	Ui.style_button(dbl, Color(0.16, 0.72, 0.42), 26)
	dbl.pressed.connect(_double_coins)
	v.add_child(dbl)

	var retry := Button.new()
	retry.text = tr("T_RETRY")
	Ui.style_button(retry, Ui.ACCENT, 32)
	retry.pressed.connect(_retry)
	v.add_child(retry)

	var home := Button.new()
	home.text = tr("T_HOME")
	Ui.style_button(home, Ui.INK_SOFT, 24)
	home.pressed.connect(_go_home)
	v.add_child(home)
	return p

# ------------------------------------------------------------------- render --

func _draw() -> void:
	var board := Rect2(0, 0, W * CELL, H * CELL)
	draw_rect(Rect2(-CELL * 4, -CELL * 4, board.size.x + CELL * 8, board.size.y + CELL * 8), VOID)
	_draw_vgradient(board, BG_TOP, BG_BOT)

	# Territory fills (flat) plus a darker outline on each region's exposed
	# edges — gives a clean, modern silhouette.
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


	# Capture flash: freshly claimed cells blink white and fade.
	for k in _flash:
		var a: float = _flash[k] / 0.45
		var fx: int = k % W
		var fy: int = k / W
		draw_rect(Rect2(fx * CELL, fy * CELL, CELL, CELL), Color(1, 1, 1, 0.55 * a))

	# Active trails: one continuous rounded ribbon per player, glued to the
	# interpolated head so the line flows instead of stepping.
	for p in players:
		if p.trail.is_empty():
			continue
		var col: Color = p.color.lightened(0.15)
		var w := CELL * 0.66
		var pts := PackedVector2Array()
		for c in p.trail:
			pts.append(_cell_center(c.x, c.y))
		if p.alive and p.is_out:
			pts.append(_head_visual(p))
		for pt in pts:
			draw_circle(pt, w * 0.5, col)
		if pts.size() >= 2:
			draw_polyline(pts, col, w)

	# Heads — interpolated blobs with faces, then name tags.
	for p in players:
		if p.alive:
			var c := _head_visual(p)
			SkinArt.draw_blob(self, c, CELL * 0.62, p.color, p.face,
				Vector2.from_angle(p.heading))
	var font := ThemeDB.fallback_font
	for p in players:
		if p.alive:
			var c := _head_visual(p) + Vector2(-60, -CELL * 1.15)
			draw_string_outline(font, c, p.display_name, HORIZONTAL_ALIGNMENT_CENTER,
				120, 11, 4, Color(1, 1, 1, 0.9))
			draw_string(font, c, p.display_name, HORIZONTAL_ALIGNMENT_CENTER,
				120, 11, Ui.INK)

	# Floating fx.
	for f in _fx:
		if f.kind == "text":
			var a := clampf(f.t / 0.9, 0.0, 1.0)
			var pos: Vector2 = f.pos - Vector2(60, (1.0 - a) * 26.0)
			var col: Color = f.color
			col.a = a
			draw_string_outline(font, pos, f.text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, 4,
				Color(1, 1, 1, a * 0.9))
			draw_string(font, pos, f.text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, col)
		else:
			var a2 := clampf(f.t / 0.5, 0.0, 1.0)
			var col2: Color = f.color
			col2.a = a2
			draw_arc(f.pos, (1.0 - a2) * CELL * 3.2 + CELL * 0.5, 0, TAU, 24, col2, 3.0)

# --- drawing helpers ---------------------------------------------------------

func _draw_vgradient(rect: Rect2, top: Color, bot: Color) -> void:
	var bands := 24
	var bh := rect.size.y / bands
	for b in range(bands):
		var ct := top.lerp(bot, float(b) / float(bands - 1))
		draw_rect(Rect2(rect.position.x, rect.position.y + b * bh, rect.size.x, bh + 1.0), ct)

func _owned(x: int, y: int, owner: int) -> bool:
	return in_bounds(x, y) and grid[idx(x, y)] == owner

## Darker border line along every edge where an owned cell meets a different
## owner — crisp region outlines on the cheap.
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
