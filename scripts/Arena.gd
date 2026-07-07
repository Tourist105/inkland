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

const W := 112
const H := 192
const CELL := 10.0
const TRAIL_W := 20.0        # chunky ribbon, roughly head-wide like the genre
const HEAD_R := 12.0
const TICK := 0.10          # bot-brain cadence (movement itself is continuous)
const SPEED := 200.0        # px/s — one cell per TICK, like the grid era
const TURN_RATE := 4.8      # rad/s, human (paper.io-2-style arc turns)
const BOT_TURN := 4.0
const RESPAWN := 2.0
const START_RADIUS := 4
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
var _land_loops: Array = []        # smoothed country outline: {pts, spts, hole}
var _terr_loops: Array = []        # per player: Array of {pts, spts, hole}
var _dirty_owners := {}            # player ids whose outline needs a retrace
var _terr_root: Node2D             # cached Polygon2D layers live under here
var _pnodes: Array[Node2D] = []    # per player: container of its polygons
var _land_child_count := 0
var _bb_lo: Array[Vector2i] = []   # per player: territory bounding box (cells)
var _bb_hi: Array[Vector2i] = []
var _map_acc := 0.0
var _map_dirty := true

# Incremental retracer state (RT_ROWS rows per frame — no commit spikes).
const RT_ROWS := 48
var _rt_oid := 0                   # owner currently being traced (0 = idle)
var _rt_segs := {}
var _rt_y := 0
var _rt_y1 := 0
var _rt_x0 := 0
var _rt_x1 := 0
var _rt_t0 := Vector2i.ZERO        # tight bbox observed during the scan
var _rt_t1 := Vector2i.ZERO
var _paper := Color(0.955, 0.985, 0.965)
var _country_poly := PackedVector2Array()   # normalized source silhouette
var _land := PackedByteArray()     # 1 = playable land (country silhouette)
var _coast_seeds := PackedInt32Array()   # land cells on the coast/edge (static)
var _water_visited := PackedByteArray()  # water pre-marked as flood walls
var _land_bb_lo := Vector2i.ZERO         # land bounding box (cells) — camera cage
var _land_bb_hi := Vector2i.ZERO
var _land_total := 1

const WATER := Color(0.76, 0.87, 0.90)   # pale lagoon, keeps the board light
const EXTRUDE := 7.0        # jelly side height (px) under every colour slab
const ROUND_CUT := 0.45     # corner rounding: fraction of the shorter edge
const ROUND_MAX := 30.0     # px cap so long edges keep ruler-straight runs

## Rough, recognisable country silhouettes (normalized 0..1, y down = south).
## Countries without a shape get a seeded island blob.
const COUNTRY_SHAPES := {
	"Switzerland": [Vector2(0.08, 0.45), Vector2(0.25, 0.30), Vector2(0.50, 0.24),
		Vector2(0.72, 0.30), Vector2(0.92, 0.42), Vector2(0.88, 0.62),
		Vector2(0.68, 0.72), Vector2(0.45, 0.76), Vector2(0.22, 0.68), Vector2(0.10, 0.58)],
	"Austria": [Vector2(0.05, 0.52), Vector2(0.22, 0.42), Vector2(0.42, 0.40),
		Vector2(0.62, 0.36), Vector2(0.92, 0.34), Vector2(0.95, 0.50),
		Vector2(0.74, 0.58), Vector2(0.50, 0.60), Vector2(0.28, 0.66), Vector2(0.10, 0.64)],
	"Netherlands": [Vector2(0.30, 0.14), Vector2(0.62, 0.10), Vector2(0.76, 0.26),
		Vector2(0.70, 0.50), Vector2(0.80, 0.74), Vector2(0.55, 0.86),
		Vector2(0.34, 0.80), Vector2(0.24, 0.60), Vector2(0.36, 0.40), Vector2(0.20, 0.28)],
	"Portugal": [Vector2(0.35, 0.08), Vector2(0.62, 0.10), Vector2(0.66, 0.30),
		Vector2(0.60, 0.50), Vector2(0.68, 0.70), Vector2(0.60, 0.90),
		Vector2(0.34, 0.92), Vector2(0.30, 0.70), Vector2(0.38, 0.50), Vector2(0.30, 0.28)],
	"Greece": [Vector2(0.20, 0.10), Vector2(0.55, 0.08), Vector2(0.75, 0.20),
		Vector2(0.90, 0.18), Vector2(0.85, 0.35), Vector2(0.62, 0.40),
		Vector2(0.72, 0.55), Vector2(0.55, 0.60), Vector2(0.64, 0.76),
		Vector2(0.42, 0.90), Vector2(0.30, 0.72), Vector2(0.45, 0.55),
		Vector2(0.30, 0.45), Vector2(0.14, 0.30)],
	"Italy": [Vector2(0.25, 0.06), Vector2(0.55, 0.05), Vector2(0.70, 0.12),
		Vector2(0.62, 0.25), Vector2(0.50, 0.40), Vector2(0.55, 0.55),
		Vector2(0.76, 0.70), Vector2(0.92, 0.78), Vector2(0.86, 0.90),
		Vector2(0.64, 0.88), Vector2(0.48, 0.74), Vector2(0.40, 0.55),
		Vector2(0.34, 0.35), Vector2(0.20, 0.20)],
}
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
	_build_land_mask()
	_spawn_players()
	_build_territory_layers()
	_refresh_territory()
	if cam != null:
		cam.zoom = Vector2(CAM_ZOOM, CAM_ZOOM)
		cam.position = _cell_center(human.cx, human.cy)
		# Cage the camera to the country: you never stare at open water or
		# anything "outside the level".
		var vp := get_viewport_rect().size / CAM_ZOOM
		var lo := Vector2(_land_bb_lo) * CELL - Vector2(CELL * 4, CELL * 4)
		var hi := Vector2(_land_bb_hi + Vector2i.ONE) * CELL + Vector2(CELL * 4, CELL * 4)
		var pad_x := maxf(0.0, (vp.x - (hi.x - lo.x)) * 0.5)
		var pad_y := maxf(0.0, (vp.y - (hi.y - lo.y)) * 0.5)
		cam.limit_left = int(lo.x - pad_x)
		cam.limit_top = int(lo.y - pad_y)
		cam.limit_right = int(hi.x + pad_x)
		cam.limit_bottom = int(hi.y + pad_y)
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
	me.home = _any_land_spot()
	players.append(me)
	human = me

	var colors := _bot_palette(skin.color)
	var names := BOT_NAMES.duplicate()
	names.shuffle()

	# Difficulty scales with the player's proven skill (best %): rookies get
	# timid bots, record-chasers get hunters. Keeps rounds tense but fair.
	var skill := clampf(Game.best_pct / 60.0, 0.0, 1.0)
	for i in BOT_COUNT:
		var b := InkPlayer.new()
		b.id = i + 2
		b.color = colors[i]
		b.face = randi() % 6
		b.display_name = names[i]
		b.home = _any_land_spot()
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
		if spot == Vector2i(-1, -1):
			# Map is packed — never paint over someone's land. Try again later;
			# late-game this lets the arena actually fill up to a 100% win.
			p.respawn_in = RESPAWN
			return
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
	p.ribbon.clear()
	p.ribbon_stale = false
	var rad := START_RADIUS
	if p.is_human and Game.start_boost:
		rad = 10                       # rewarded "start big" (~5x area)
		Game.start_boost = false
		Game.save_state()
	# Round starting blob (like the original), clipped to land.
	var rr := rad * rad + rad
	for y in range(p.home.y - rad, p.home.y + rad + 1):
		for x in range(p.home.x - rad, p.home.x + rad + 1):
			var dx := x - p.home.x
			var dy := y - p.home.y
			if in_bounds(x, y) and dx * dx + dy * dy <= rr \
					and _land[idx(x, y)] == 1:
				grid[idx(x, y)] = p.id
	_bb_mark(p.id, p.home.x - rad, p.home.y - rad, p.home.x + rad, p.home.y + rad)
	_dirty_owners[p.id] = true

func _any_land_spot() -> Vector2i:
	var spot := _find_free_spot()
	if spot != Vector2i(-1, -1):
		return spot
	for i in W * H:
		if _land[i] == 1:
			return Vector2i(i % W, i / W)
	return Vector2i(W / 2, H / 2)

## A random mostly-neutral 5x5 LAND patch, or (-1,-1) if none found.
func _find_free_spot() -> Vector2i:
	for _try in 40:
		var x := randi_range(START_RADIUS + 2, W - START_RADIUS - 3)
		var y := randi_range(START_RADIUS + 2, H - START_RADIUS - 3)
		var ok := true
		for dy in range(-START_RADIUS, START_RADIUS + 1):
			for dx in range(-START_RADIUS, START_RADIUS + 1):
				var i := idx(x + dx, y + dy)
				if grid[i] != 0 or trail_owner[i] != 0 or _land[i] == 0:
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
				_retrace_step()           # ≤1 owner per frame — no commit spikes
				_info_acc += delta
				if _info_acc >= 0.25:     # counts/leaderboard at 4 Hz is plenty
					_info_acc = 0.0
					_update_info()
				_map_acc += delta
				if _map_dirty and _map_acc >= 0.4:
					_map_acc = 0.0
					_map_dirty = false
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
		var old_pos := p.pos
		var diff := angle_difference(p.heading, target)
		var rate := (TURN_RATE if p.is_human else BOT_TURN) * dt
		p.heading += clampf(diff, -rate, rate)
		p.pos += Vector2.from_angle(p.heading) * SPEED * dt
		p.dir = _cardinal(p.heading)          # bots' brain works in cardinals

		# Board edge and coastline are WALLS, never death (original rules):
		# you slide along them — riding the border to seal off a corner is a
		# legitimate, satisfying capture strategy.
		var m := CELL * 0.5
		p.pos = Vector2(clampf(p.pos.x, m, W * CELL - m),
			clampf(p.pos.y, m, H * CELL - m))
		if not land(int(p.pos.x / CELL), int(p.pos.y / CELL)):
			# Slide along the coast: take the LARGEST axis sub-step that stays
			# on land — much smoother than full-step-or-freeze.
			var best := old_pos
			var best_d := 0.0
			for f: float in [1.0, 0.66, 0.33]:
				var cx2 := Vector2(old_pos.x + (p.pos.x - old_pos.x) * f, old_pos.y)
				var cy2 := Vector2(old_pos.x, old_pos.y + (p.pos.y - old_pos.y) * f)
				if absf(cx2.x - old_pos.x) > best_d \
						and land(int(cx2.x / CELL), int(cx2.y / CELL)):
					best = cx2
					best_d = absf(cx2.x - old_pos.x)
				if absf(cy2.y - old_pos.y) > best_d \
						and land(int(cy2.x / CELL), int(cy2.y / CELL)):
					best = cy2
					best_d = absf(cy2.y - old_pos.y)
			p.pos = best
		# Cell-entry events (one axis at a time — no corner skipping).
		var nx := int(p.pos.x / CELL)
		var ny := int(p.pos.y / CELL)
		while (p.cx != nx or p.cy != ny) and p.alive and state == State.PLAYING:
			if p.cx != nx:
				_enter_cell(p, p.cx + signi(nx - p.cx), p.cy)
			else:
				_enter_cell(p, p.cx, p.cy + signi(ny - p.cy))
		# Render ribbon: sample the head's true continuous path while drawing —
		# the line on screen is pure arcs, never grid stairs.
		if p.alive and p.is_out:
			if p.ribbon_stale:
				p.ribbon.clear()
				p.ribbon_stale = false
			var rn := p.ribbon.size()
			if rn == 0 or p.ribbon[rn - 1].distance_squared_to(p.pos) > 25.0:
				p.ribbon.append(p.pos)

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
			# Touching the tail right behind the head is just jitter — ignore.
			var t_pos := p.trail.rfind(Vector2i(nx, ny))
			if t_pos >= 0 and p.trail.size() - t_pos <= 4:
				p.cx = nx
				p.cy = ny
				return
			# A REAL crossing of your own trail closes the loop and claims it.
			p.cx = nx
			p.cy = ny
			_commit(p)
			p.is_out = false
			p.going_home = false
			p.plan.clear()
			return
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
	p.ribbon.clear()
	p.ribbon_stale = false
	p.is_out = false
	if p.is_human:
		_human_died(cause, killer)      # land stays put (revive keeps it)
		return
	p.alive = false
	p.respawn_in = RESPAWN
	# Original rule: the victim's WHOLE empire falls to the killer.
	var heir := 0
	if killer != null and killer.alive and killer != p:
		heir = killer.id
	var got := 0
	for i in grid.size():
		if grid[i] == p.id:
			grid[i] = heir
			got += 1
	if heir != 0:
		if _bb_lo.size() >= p.id and _bb_hi[p.id - 1].x >= _bb_lo[p.id - 1].x:
			_bb_mark(heir, _bb_lo[p.id - 1].x, _bb_lo[p.id - 1].y,
				_bb_hi[p.id - 1].x, _bb_hi[p.id - 1].y)
		_dirty_owners[heir] = true
		if killer.is_human and got > 0:
			_add_text_fx(_cell_center(p.cx, p.cy) - Vector2(0, CELL * 1.4),
				"+%.1f%%" % (got * 100.0 / float(_land_total)),
				killer.color.darkened(0.2))
	if _bb_lo.size() >= p.id:
		_bb_lo[p.id - 1] = Vector2i(W, H)
		_bb_hi[p.id - 1] = Vector2i(-1, -1)
	_dirty_owners[p.id] = true
	_add_ring_fx(_cell_center(p.cx, p.cy), p.color)
	if _on_screen(_cell_center(p.cx, p.cy)):
		_shake = maxf(_shake, 5.0)

# ------------------------------------------------------------- claim / fill --

func _commit(p: InkPlayer) -> void:
	# 1. The trail itself becomes owned land.
	var tx0 := W
	var ty0 := H
	var tx1 := -1
	var ty1 := -1
	for c in p.trail:
		var i := idx(c.x, c.y)
		var prev := grid[i]
		if prev != 0 and prev != p.id:
			_dirty_owners[prev] = true      # stolen from — retrace them too
		grid[i] = p.id
		trail_owner[i] = 0
		tx0 = mini(tx0, c.x)
		ty0 = mini(ty0, c.y)
		tx1 = maxi(tx1, c.x)
		ty1 = maxi(ty1, c.y)
	if tx1 >= tx0:
		_bb_mark(p.id, tx0, ty0, tx1, ty1)
	p.trail.clear()
	p.ribbon_stale = true      # keep the ribbon until the polygon lands
	_dirty_owners[p.id] = true

	# 2. Flood the "outside" from the border through every non-owned cell.
	#    Whatever the flood can't reach is enclosed -> it becomes ours.
	#    Water is pre-marked visited (native copy) so it stays a hard wall,
	#    and the static coast list replaces the old full-grid seed pass.
	var visited := _water_visited.duplicate()
	var stack: Array[int] = []
	for ci in _coast_seeds:
		_seed(ci, p.id, visited, stack)

	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % W
		@warning_ignore("integer_division")
		var y := i / W
		if y > 0:
			var ai := i - W
			if visited[ai] == 0 and grid[ai] != p.id:
				visited[ai] = 1
				stack.append(ai)
		if y < H - 1:
			var ai2 := i + W
			if visited[ai2] == 0 and grid[ai2] != p.id:
				visited[ai2] = 1
				stack.append(ai2)
		if x > 0:
			var ai3 := i - 1
			if visited[ai3] == 0 and grid[ai3] != p.id:
				visited[ai3] = 1
				stack.append(ai3)
		if x < W - 1:
			var ai4 := i + 1
			if visited[ai4] == 0 and grid[ai4] != p.id:
				visited[ai4] = 1
				stack.append(ai4)

	var gained := 0
	var gx0 := W
	var gy0 := H
	var gx1 := -1
	var gy1 := -1
	for i in range(W * H):
		if visited[i] == 0 and grid[i] != p.id:
			if grid[i] != 0:
				_dirty_owners[grid[i]] = true
			grid[i] = p.id
			gained += 1
			var cx := i % W
			@warning_ignore("integer_division")
			var cy := i / W
			gx0 = mini(gx0, cx)
			gy0 = mini(gy0, cy)
			gx1 = maxi(gx1, cx)
			gy1 = maxi(gy1, cy)
	if gx1 >= gx0:
		_bb_mark(p.id, gx0, gy0, gx1, gy1)
	if gained > 0 and p.is_human:
		Sfx.play("capture", 0.9 + randf() * 0.2)
		Sfx.haptic(25)
		var pct := gained * 100.0 / float(_land_total)
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
		# Finish the planned sweep unless the trail gets dangerously long or a
		# rival is closing in — then curl back to the nearest owned cell.
		var hard_cap := 40 + int(p.greed * 40.0)
		if p.trail.size() >= hard_cap or p.plan.is_empty():
			p.going_home = true
		if not p.going_home and _threat_dist(p) < 2.5 + p.caution * 3.5:
			p.going_home = true
		if p.going_home:
			_steer(p, _dir_home(p))
		else:
			_follow_plan(p)
	else:
		p.going_home = false
		if p.plan.is_empty():
			_make_plan(p)              # always carving — no idle straight lines
		_follow_plan(p)

## Plan a WIDE border sweep: push out from our frontier, run a long way
## parallel to it (claiming a broad strip), then cut back in. This carves big
## organic rectangles along the territory edge instead of thin straight lines.
func _make_plan(p: InkPlayer) -> void:
	var out_dir := _open_dir(p)
	var along := Vector2i(-out_dir.y, out_dir.x)
	if randf() < 0.5:
		along = -along
	var depth := 5 + int(randf() * (6.0 + p.greed * 12.0))    # how far out
	var width := 10 + int(randf() * (12.0 + p.greed * 28.0))  # long sweep leg
	# Optional dog-leg so shapes vary (L-sweep) rather than a plain rectangle.
	if randf() < 0.5:
		var w2 := int(width * randf_range(0.3, 0.6))
		p.plan = [
			{"dir": out_dir, "steps": depth},
			{"dir": along, "steps": w2},
			{"dir": out_dir, "steps": int(depth * 0.6) + 1},
			{"dir": along, "steps": width - w2},
			{"dir": -out_dir, "steps": depth + int(depth * 0.6) + 2},
		]
	else:
		p.plan = [
			{"dir": out_dir, "steps": depth},
			{"dir": along, "steps": width},
			{"dir": -out_dir, "steps": depth + 2},
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
			if not in_bounds(x, y) or _land[idx(x, y)] == 0:
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
		if not land(p.cx + d.x, p.cy + d.y):
			continue
		# Mid-trail, also look two cells ahead so arcs don't drift into walls.
		if p.is_out and not land(p.cx + d.x * 2, p.cy + d.y * 2):
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
	var target := _nearest_owned(p)
	if target == Vector2i(-1, -1):
		return p.dir                # no land left — doomed, keep running
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
	# All owned cells live inside the tracked bounding box — scan only that.
	if _bb_lo.size() < p.id or _bb_hi[p.id - 1].x < _bb_lo[p.id - 1].x:
		return best
	var x0 := maxi(_bb_lo[p.id - 1].x, 0)
	var y0 := maxi(_bb_lo[p.id - 1].y, 0)
	var x1 := mini(_bb_hi[p.id - 1].x, W - 1)
	var y1 := mini(_bb_hi[p.id - 1].y, H - 1)
	for y in range(y0, y1 + 1):
		var row := y * W
		for x in range(x0, x1 + 1):
			if grid[row + x] == p.id:
				var d: int = absi(x - p.cx) + absi(y - p.cy)
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best

# -------------------------------------------------------------------- input --

func _read_human_input() -> void:
	if human == null or not human.alive:
		return
	# DEMO mode (store screenshots): drive the human with the bot brain so the
	# arena fills with real captured territory. Inert in normal play.
	if OS.get_environment("DEMO") != "":
		human.greed = 0.9
		human.aggro = 0.3
		_bot_think(human)
		if human.pending_dir != Vector2i.ZERO:
			_human_target = Vector2(human.pending_dir).angle()
			_human_has_target = true
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
	if OS.get_environment("DEMO") != "":
		human.is_out = false      # DEMO/store: invincible, keep painting
		return
	human.alive = false
	_refresh_territory()          # board under the panel shows the true state
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
		Ads.maybe_interstitial(func() -> void: _show_results(subtitle, false))

func _round_won() -> void:
	_refresh_territory()          # final claim must be fully painted
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
		var rvr := START_RADIUS * START_RADIUS + START_RADIUS
		for y in range(spot.y - START_RADIUS, spot.y + START_RADIUS + 1):
			for x in range(spot.x - START_RADIUS, spot.x + START_RADIUS + 1):
				var dx := x - spot.x
				var dy := y - spot.y
				if in_bounds(x, y) and dx * dx + dy * dy <= rvr \
						and _land[idx(x, y)] == 1:
					var pv := grid[idx(x, y)]
					if pv != 0 and pv != human.id:
						_dirty_owners[pv] = true
					grid[idx(x, y)] = human.id
		_bb_mark(human.id, spot.x - START_RADIUS, spot.y - START_RADIUS,
			spot.x + START_RADIUS, spot.y + START_RADIUS)
		_dirty_owners[human.id] = true
		_refresh_territory()          # revived land must be visible instantly
	else:
		human.home = spot
	human.cx = spot.x
	human.cy = spot.y
	human.pos = _cell_center(spot.x, spot.y)
	human.heading = -PI * 0.5
	_human_has_target = false
	human.is_out = false
	human.trail.clear()
	human.ribbon.clear()
	human.ribbon_stale = false
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
	return _counts[1] * 100.0 / float(_land_total) if _counts.size() > 1 else 0.0

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
	var cline := ""
	# Original rules: every run banks its % into the country; a single-run
	# WIN conquers instantly. Either way the campaign rolls onward.
	var conquered := won
	if not won:
		conquered = Game.record_country_pct(_max_pct)
	if conquered:
		var cbonus := Game.conquer_country()
		cline = (tr("T_CONQUERED") % prev_country) + "  +%d
→ %s" % [cbonus, Game.COUNTRIES[Game.country_idx].name]
	else:
		cline = "%s  ·  %d%%" % [prev_country, Game.country_progress()]
	(v.get_node("Retry") as Button).text = \
		tr("T_NEXT_COUNTRY") if conquered else tr("T_RETRY")
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
	# Gentle zoom-out as the empire grows (original behaviour) — you see more
	# of what you own without ever losing the close-chase feel.
	var zt := CAM_ZOOM * lerpf(1.0, 0.74, clampf(_you_pct() / 60.0, 0.0, 1.0))
	var z := lerpf(cam.zoom.x, zt, clampf(1.5 * delta, 0.0, 1.0))
	cam.zoom = Vector2(z, z)
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
	for p in players:
		_counts[p.id] = grid.count(p.id)   # native pass — no GDScript loop
	var total := float(_land_total)
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
	if state == State.PLAYING and you >= 99.5:
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
	retry.name = "Retry"
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

## Drain the whole retrace queue at once (initial build / round-end paths).
func _refresh_territory() -> void:
	while _rt_oid != 0 or not _dirty_owners.is_empty():
		_retrace_step()


## --- Vector territory rendering (the real paper.io-2 look) ------------------
## Region borders are traced from the grid as closed polygons, collinear runs
## are merged (straight stays straight), corners get generous rounded cuts and
## a Chaikin pass silkens the result. _draw fills each loop as a jelly slab:
## dark extruded side below, bright colour on top. No textures, no blur —
## mathematically smooth curves at any zoom.

func _build_territory_layers() -> void:
	# Flat pale water backdrop behind everything — clean, never busy.
	var bg := ColorRect.new()
	bg.color = WATER
	bg.position = Vector2(-CELL * 20, -CELL * 20)
	bg.size = Vector2((W + 40) * CELL, (H + 40) * CELL)
	bg.z_index = -2
	add_child(bg)
	var bt := Game.country_tint()
	_paper = Color(0.955 * bt.r, 0.985 * bt.g, 0.965 * bt.b)
	# All territory polygons live in cached Polygon2D nodes (triangulated once
	# per retrace, NOT every frame — that per-frame earcut was the jank).
	_terr_root = Node2D.new()
	_terr_root.z_index = -1
	add_child(_terr_root)
	_retrace_land()
	for lp in _land_loops:
		if not lp.hole:
			var lsh := Polygon2D.new()
			lsh.polygon = lp.spts
			lsh.color = Color(0.14, 0.32, 0.38, 0.18)
			lsh.antialiased = true
			_terr_root.add_child(lsh)
	for lp in _land_loops:
		var lf := Polygon2D.new()
		lf.polygon = lp.pts
		lf.color = WATER if lp.hole else _paper
		lf.antialiased = true
		_terr_root.add_child(lf)
	_land_child_count = _terr_root.get_child_count()
	_terr_loops.clear()
	_pnodes.clear()
	for k in players.size():
		_terr_loops.append([])
		var nd := Node2D.new()
		_pnodes.append(nd)
		_terr_root.add_child(nd)
		_dirty_owners[k + 1] = true

## The coast is rendered from the SOURCE silhouette polygon, not from the
## rasterized cell mask — that keeps it silky at any zoom. The mask is only
## used for gameplay, so territory may overhang the drawn water by up to a
## cell: reads as the jelly slab bleeding over the edge, which is the look.
func _retrace_land() -> void:
	var mrg := 0.05
	var board := Vector2(W * CELL, H * CELL)
	var pts := PackedVector2Array()
	for p in _country_poly:
		pts.append((p - Vector2(mrg, mrg)) / (1.0 - 2.0 * mrg) * board)
	var n := pts.size()
	var rounded := PackedVector2Array()
	for i in n:
		var pv := pts[(i + n - 1) % n]
		var v := pts[i]
		var nx := pts[(i + 1) % n]
		var cut := minf(v.distance_to(pv), v.distance_to(nx)) * 0.28
		rounded.append(v + (pv - v).normalized() * cut)
		rounded.append(v + (nx - v).normalized() * cut)
	var smooth := _chaikin_closed(_chaikin_closed(rounded))
	var spts := PackedVector2Array()
	for q in smooth:
		spts.append(q + Vector2(0, EXTRUDE + 4.0))
	_land_loops = [{"pts": smooth, "spts": spts, "hole": false}]

## Advance the incremental retracer: start a queued owner if idle, then trace
## up to RT_ROWS grid rows. Finishing an owner swaps its cached polygons in
## and TIGHTENS its bounding box to what the scan actually saw (boxes only
## ever grow otherwise — that would decay into full-map scans late game).
## If the owner's cells change mid-scan it is re-queued, so we abort and
## restart fresh — never chain segments from two different grid states.
func _retrace_step() -> void:
	if _rt_oid != 0 and _dirty_owners.has(_rt_oid):
		_rt_oid = 0
	if _rt_oid == 0:
		if _dirty_owners.is_empty():
			return
		var oid: int = _dirty_owners.keys()[0]
		_dirty_owners.erase(oid)
		_rt_oid = oid
		_rt_segs = {}
		_rt_t0 = Vector2i(W, H)
		_rt_t1 = Vector2i(-1, -1)
		if _bb_lo.size() >= oid and _bb_hi[oid - 1].x >= _bb_lo[oid - 1].x:
			_rt_x0 = maxi(_bb_lo[oid - 1].x, 0)
			_rt_y = maxi(_bb_lo[oid - 1].y, 0)
			_rt_x1 = mini(_bb_hi[oid - 1].x, W - 1)
			_rt_y1 = mini(_bb_hi[oid - 1].y, H - 1)
		else:
			_rt_y = 1
			_rt_y1 = 0          # empty range — finishes immediately
	var stride := W + 1
	var rows := 0
	while _rt_y <= _rt_y1 and rows < RT_ROWS:
		var y := _rt_y
		var row := y * W
		for x in range(_rt_x0, _rt_x1 + 1):
			if grid[row + x] != _rt_oid:
				continue
			_rt_t0 = Vector2i(mini(_rt_t0.x, x), mini(_rt_t0.y, y))
			_rt_t1 = Vector2i(maxi(_rt_t1.x, x), maxi(_rt_t1.y, y))
			var tl := y * stride + x
			if y == 0 or grid[row + x - W] != _rt_oid:
				_seg_add(_rt_segs, tl, tl + 1)
			if x == W - 1 or grid[row + x + 1] != _rt_oid:
				_seg_add(_rt_segs, tl + 1, tl + stride + 1)
			if y == H - 1 or grid[row + x + W] != _rt_oid:
				_seg_add(_rt_segs, tl + stride + 1, tl + stride)
			if x == 0 or grid[row + x - 1] != _rt_oid:
				_seg_add(_rt_segs, tl + stride, tl)
		_rt_y += 1
		rows += 1
	if _rt_y > _rt_y1:
		_terr_loops[_rt_oid - 1] = _chain_loops(_rt_segs)
		_rebuild_owner_node(_rt_oid)
		if _bb_lo.size() >= _rt_oid:
			_bb_lo[_rt_oid - 1] = _rt_t0
			_bb_hi[_rt_oid - 1] = _rt_t1
		_rt_oid = 0
		_rt_segs = {}
		_map_dirty = true
		_reorder_nodes()

## Swap the cached polygons of one owner for its freshly traced loops.
func _rebuild_owner_node(oid: int) -> void:
	var node := _pnodes[oid - 1]
	for c in node.get_children():
		c.queue_free()
	var p := players[oid - 1]
	if p.ribbon_stale:
		p.ribbon.clear()          # the claimed polygon now covers the ribbon
		p.ribbon_stale = false
	var loops: Array = _terr_loops[oid - 1]
	for tp in loops:
		if not tp.hole:
			var sh := Polygon2D.new()
			sh.polygon = tp.spts
			sh.color = p.color.darkened(0.36)
			sh.antialiased = true
			node.add_child(sh)
	for tp in loops:
		var f := Polygon2D.new()
		f.polygon = tp.pts
		f.color = _paper if tp.hole else p.color
		f.antialiased = true
		node.add_child(f)

## Big empires draw first so a small blob inside a pocket stays visible.
func _reorder_nodes() -> void:
	var order: Array = range(players.size())
	order.sort_custom(func(a, b): return _counts[a + 1] > _counts[b + 1])
	for pos in order.size():
		_terr_root.move_child(_pnodes[order[pos]], pos + _land_child_count)

## Grow a player's territory bounding box to include the given cell rect.
func _bb_mark(oid: int, x0: int, y0: int, x1: int, y1: int) -> void:
	while _bb_lo.size() < oid:
		_bb_lo.append(Vector2i(W, H))
		_bb_hi.append(Vector2i(-1, -1))
	var i := oid - 1
	_bb_lo[i] = Vector2i(mini(_bb_lo[i].x, x0), mini(_bb_lo[i].y, y0))
	_bb_hi[i] = Vector2i(maxi(_bb_hi[i].x, x1), maxi(_bb_hi[i].y, y1))

static func _seg_add(d: Dictionary, a: int, b: int) -> void:
	if d.has(a):
		d[a].append(b)
	else:
		d[a] = [b]

## Chain directed edge segments into closed loops (region is traced clockwise,
## holes counter-clockwise — the winding tells them apart later).
func _chain_loops(segs: Dictionary) -> Array:
	var out := []
	var stride := W + 1
	while not segs.is_empty():
		var start: int = segs.keys()[0]
		var loop := PackedInt32Array()
		var cur := start
		var prev_dir := Vector2.ZERO
		var closed := false
		while true:
			loop.append(cur)
			var ends: Array = segs[cur]
			var nxt: int = ends[0]
			if ends.size() > 1:
				# Diagonal-touch corner: take the clockwise turn so blobs that
				# only meet at a point stay separate loops.
				var best := -2.0
				for e in ends:
					var dv := Vector2(_key_dir(cur, e, stride)).normalized()
					var s := Vector2(-prev_dir.y, prev_dir.x).dot(dv)
					if s > best:
						best = s
						nxt = e
				ends.erase(nxt)
			else:
				segs.erase(cur)
			prev_dir = Vector2(_key_dir(cur, nxt, stride)).normalized()
			cur = nxt
			if cur == start:
				closed = true
				break
			if not segs.has(cur):
				break     # broken chain — drop it, never draw garbage
		if closed and loop.size() >= 4:
			out.append(_finish_loop(loop, stride))
	return out

static func _key_dir(a: int, b: int, stride: int) -> Vector2i:
	return Vector2i((b % stride) - (a % stride), (b / stride) - (a / stride))

## Corner-key loop -> smooth world-space polygon + its extruded shadow copy.
func _finish_loop(keys: PackedInt32Array, stride: int) -> Dictionary:
	var raw := PackedVector2Array()
	for k in keys:
		raw.append(Vector2(float(k % stride), float(k / stride)) * CELL)
	var n := raw.size()
	# Winding separates solids from holes (tracing orientation is constant).
	var area := 0.0
	for i in n:
		var a := raw[i]
		var b := raw[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	# Merge collinear runs so long edges stay ruler-straight...
	var pts := PackedVector2Array()
	for i in n:
		var d1 := raw[i] - raw[(i + n - 1) % n]
		var d2 := raw[(i + 1) % n] - raw[i]
		if absf(d1.x * d2.y - d1.y * d2.x) > 0.01:
			pts.append(raw[i])
	if pts.size() < 3:
		pts = raw
	# ...collapse cell staircases into true diagonals (the last "Stufen")...
	var simplified := _rdp_closed(pts, 7.0)
	if simplified.size() >= 3:
		pts = simplified
	# ...then cut every corner generously and silken it with Chaikin.
	var m := pts.size()
	var rounded := PackedVector2Array()
	for i in m:
		var pv := pts[(i + m - 1) % m]
		var v := pts[i]
		var nx := pts[(i + 1) % m]
		var cut := minf(minf(v.distance_to(pv), v.distance_to(nx)) * ROUND_CUT, ROUND_MAX)
		rounded.append(v + (pv - v).normalized() * cut)
		rounded.append(v + (nx - v).normalized() * cut)
	var smooth := _chaikin_closed(rounded)
	if smooth.size() < 1400:
		smooth = _chaikin_closed(smooth)
	var spts := PackedVector2Array()
	for q in smooth:
		spts.append(q + Vector2(0, EXTRUDE))
	return {"pts": smooth, "spts": spts, "hole": area < 0.0}

## Ramer-Douglas-Peucker on a closed loop (first point doubles as anchor).
## eps just over half a cell melts 1-cell staircases into clean diagonals
## while keeping every feature bigger than a cell.
static func _rdp_closed(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := pts.size()
	if n < 5:
		return pts
	var work := pts.duplicate()
	work.append(pts[0])
	var keep := PackedByteArray()
	keep.resize(n + 1)
	keep[0] = 1
	keep[n] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n)]
	while not stack.is_empty():
		var seg: Vector2i = stack.pop_back()
		var a := work[seg.x]
		var b := work[seg.y]
		var ab := b - a
		var len2 := ab.length_squared()
		var far := -1.0
		var fidx := -1
		for i in range(seg.x + 1, seg.y):
			var d: float
			if len2 < 0.0001:
				d = work[i].distance_to(a)
			else:
				var t := clampf((work[i] - a).dot(ab) / len2, 0.0, 1.0)
				d = work[i].distance_to(a + ab * t)
			if d > far:
				far = d
				fidx = i
		if far > eps and fidx > 0:
			keep[fidx] = 1
			stack.append(Vector2i(seg.x, fidx))
			stack.append(Vector2i(fidx, seg.y))
	var out := PackedVector2Array()
	for i in n:
		if keep[i] == 1:
			out.append(work[i])
	return out

static func _chaikin_closed(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out

## Rasterize the current country's silhouette into the land mask — the arena
## IS the country (paper.io-2 style). Unknown countries get a seeded island.
func _build_land_mask() -> void:
	_land.resize(W * H)
	var cname: String = Game.COUNTRIES[Game.country_idx].name
	var poly := PackedVector2Array()
	if COUNTRY_SHAPES.has(cname):
		for v in COUNTRY_SHAPES[cname]:
			poly.append(v)
	else:
		var seed_f := float(Game.country_idx)
		for k in 14:
			var ang := TAU * k / 14.0
			var rad := 0.34 + 0.10 * sin(k * 2.7 + seed_f) + 0.06 * sin(k * 4.3 + seed_f * 2.0)
			poly.append(Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang) * 0.9) * rad)
	_country_poly = poly
	# Fit with a small margin; grid is portrait so shapes sit centred.
	var m := 0.05
	_land_total = 0
	_land_bb_lo = Vector2i(W, H)
	_land_bb_hi = Vector2i(0, 0)
	for y in H:
		for x in W:
			var pnt := Vector2(m + (1.0 - 2.0 * m) * (x + 0.5) / W,
				m + (1.0 - 2.0 * m) * (y + 0.5) / H)
			var inside := Geometry2D.is_point_in_polygon(pnt, poly)
			_land[idx(x, y)] = 1 if inside else 0
			if inside:
				_land_total += 1
				_land_bb_lo = Vector2i(mini(_land_bb_lo.x, x), mini(_land_bb_lo.y, y))
				_land_bb_hi = Vector2i(maxi(_land_bb_hi.x, x), maxi(_land_bb_hi.y, y))
	_land_total = maxi(_land_total, 1)
	# Static flood helpers: water-as-wall mask + coastal seed cells.
	_water_visited.resize(W * H)
	_coast_seeds.clear()
	for y in H:
		for x in W:
			var i := idx(x, y)
			if _land[i] == 0:
				_water_visited[i] = 1
				continue
			_water_visited[i] = 0
			if x == 0 or y == 0 or x == W - 1 or y == H - 1 \
					or _land[idx(x - 1, y)] == 0 or _land[idx(x + 1, y)] == 0 \
					or _land[idx(x, y - 1)] == 0 or _land[idx(x, y + 1)] == 0:
				_coast_seeds.append(i)

func land(x: int, y: int) -> bool:
	return in_bounds(x, y) and _land[idx(x, y)] == 1

func _visible_cells() -> Rect2i:
	var vp := get_viewport_rect().size / CAM_ZOOM
	var c := cam.position if cam != null else _cell_center(W / 2, H / 2)
	var x0 := clampi(int((c.x - vp.x * 0.5) / CELL) - 1, 0, W - 1)
	var x1 := clampi(int((c.x + vp.x * 0.5) / CELL) + 1, 0, W - 1)
	var y0 := clampi(int((c.y - vp.y * 0.5) / CELL) - 1, 0, H - 1)
	var y1 := clampi(int((c.y + vp.y * 0.5) / CELL) + 1, 0, H - 1)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)

func _draw() -> void:
	# Water/land/territory live in cached Polygon2D layers below (z -1/-2) —
	# triangulated once per retrace, not every frame.
	# Active trails: the head's true continuous path, ending exactly AT the
	# head — pure fluid arcs, no grid-derived geometry at all.
	for p in players:
		var pts := p.ribbon.duplicate()
		if p.alive and p.is_out:
			pts.append(_head_visual(p))
		if pts.is_empty():
			continue
		var main_c: Color = p.color.lightened(0.30)
		var rim_c: Color = p.color.darkened(0.16)
		var w := TRAIL_W
		if pts.size() >= 2:
			var lo := PackedVector2Array()
			for q in pts:
				lo.append(q + Vector2(0, 5))     # extruded jelly side
			draw_circle(lo[0], w * 0.5, rim_c)
			draw_circle(lo[lo.size() - 1], w * 0.5, rim_c)
			draw_polyline(lo, rim_c, w, true)
			draw_circle(pts[0], w * 0.5, main_c)
			draw_circle(pts[pts.size() - 1], w * 0.5, main_c)
			draw_polyline(pts, main_c, w, true)
		elif pts.size() == 1:
			draw_circle(pts[0], w * 0.5, main_c)

	# Heads — interpolated blobs with faces, then name tags.
	# Crown on the current territory king — the original's "who leads?" cue.
	var king := 0
	var kc := 0
	for p in players:
		if p.alive and _counts.size() > p.id and _counts[p.id] > kc:
			kc = _counts[p.id]
			king = p.id
	for p in players:
		if p.alive:
			var c := _head_visual(p)
			draw_circle(c + Vector2(0, 6), HEAD_R * 0.95, Color(0.10, 0.16, 0.22, 0.18))
			var glow := p.color
			glow.a = 0.30
			draw_circle(c, HEAD_R * 1.55, glow)
			SkinArt.draw_blob(self, c, HEAD_R, p.color, p.face,
				Vector2.from_angle(p.heading))
			if p.id == king:
				var b := c + Vector2(0, -HEAD_R - 9.0)
				draw_colored_polygon(PackedVector2Array([
					b + Vector2(-9, 3), b + Vector2(-9, -6), b + Vector2(-4.5, -1.5),
					b + Vector2(0, -8), b + Vector2(4.5, -1.5), b + Vector2(9, -6),
					b + Vector2(9, 3)]), Ui.GOLD)
	var font := ThemeDB.fallback_font
	for p in players:
		if p.alive and not p.is_human:
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

## One Chaikin corner-cutting pass (call twice for silky trails).
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array()
	out.append(pts[0])
	for i in range(pts.size() - 1):
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out

