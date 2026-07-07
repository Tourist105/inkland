class_name SkinArt
## Procedural mascot drawing — one blob body + 8 original face styles.
## Used by the arena renderer, the home-screen mascot and the shop previews,
## so every surface renders skins identically. All art is code; zero textures.

## face ids: 0 classic, 1 happy, 2 wink, 3 heart, 4 angry, 5 sleepy, 6 shades, 7 star
static func draw_blob(ci: CanvasItem, c: Vector2, r: float, col: Color, face: int,
		dir: Vector2 = Vector2.UP, with_shadow := true, pattern := 0) -> void:
	if with_shadow:
		ci.draw_circle(c + Vector2(0, r * 0.16), r, Color(0, 0, 0, 0.16))
	ci.draw_circle(c, r, col)
	if pattern > 0:
		draw_pattern(ci, c, r, pattern, col)
	ci.draw_circle(c, r, col.lightened(0.35), false, maxf(r * 0.07, 1.5))
	draw_face(ci, c, r, face, dir)

## Ink PATTERN inside the blob — special heroes read as more than a colour.
## 1 stripes · 2 dots · 3 rings · 4 bolt. Kept within ~0.9r (no clipping).
static func draw_pattern(ci: CanvasItem, c: Vector2, r: float, pattern: int, col: Color) -> void:
	var ink := col.darkened(0.28)
	match pattern:
		1:   # diagonal stripes (chords, shortened to stay inside the disc)
			for k in range(-2, 3):
				var off := k * r * 0.42
				var d := sqrt(maxf(0.0, r * r - off * off)) * 0.92
				var n := Vector2(0.7071, -0.7071)
				var t := Vector2(0.7071, 0.7071)
				ci.draw_line(c + n * off - t * d, c + n * off + t * d, ink, maxf(r * 0.13, 2.0))
		2:   # polka dots
			for p in [Vector2(-0.42, -0.3), Vector2(0.42, -0.3), Vector2(0.0, 0.12),
					Vector2(-0.42, 0.5), Vector2(0.42, 0.5)]:
				ci.draw_circle(c + p * r, r * 0.15, ink)
		3:   # concentric rings
			ci.draw_arc(c, r * 0.66, 0, TAU, 28, ink, maxf(r * 0.10, 1.5))
			ci.draw_arc(c, r * 0.38, 0, TAU, 20, ink, maxf(r * 0.10, 1.5))
		4:   # lightning bolt
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.10, -0.62) * r, c + Vector2(-0.34, 0.06) * r,
				c + Vector2(-0.02, 0.06) * r, c + Vector2(-0.10, 0.62) * r,
				c + Vector2(0.34, -0.06) * r, c + Vector2(0.02, -0.06) * r]), ink)

static func draw_face(ci: CanvasItem, c: Vector2, r: float, face: int, dir: Vector2) -> void:
	var look := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	var perp := Vector2(-look.y, look.x)
	var eye_off := perp * r * 0.42
	var fwd := look * r * 0.16
	var eye_r := r * 0.30
	var ink := Color(0.09, 0.11, 0.17)
	var l := c + eye_off + fwd     # left eye centre
	var rr := c - eye_off + fwd    # right eye centre

	match face:
		1:   # happy — round eyes + smile
			_eyes(ci, l, rr, eye_r, look, ink)
			ci.draw_arc(c + look * r * 0.55, r * 0.30, 0.0, PI, 14, ink, maxf(r * 0.07, 1.5))
		2:   # wink — one open eye, one closed line
			_eye(ci, l, eye_r, look, ink)
			ci.draw_line(rr - perp * eye_r * 0.8, rr + perp * eye_r * 0.8, ink, maxf(r * 0.08, 1.5))
		3:   # heart pupils
			for e in [l, rr]:
				ci.draw_circle(e, eye_r, Color.WHITE)
				_heart(ci, e, eye_r * 0.62, Color(1.0, 0.25, 0.45))
		4:   # angry — brows over pupils
			_eyes(ci, l, rr, eye_r, look, ink)
			for s: float in [1.0, -1.0]:
				var e := c + eye_off * s + fwd
				var a := e - look * eye_r * 1.25 - perp * eye_r * s
				var b := e - look * eye_r * 0.55 + perp * eye_r * 0.55 * s
				ci.draw_line(a, b, ink, maxf(r * 0.09, 1.8))
		5:   # sleepy — half lids, low pupils
			for e in [l, rr]:
				ci.draw_circle(e, eye_r, Color.WHITE)
				ci.draw_circle(e + look * eye_r * 0.05, eye_r * 0.45, ink)
				ci.draw_arc(e, eye_r * 0.95, PI + 0.4, TAU - 0.4, 12, ink, maxf(r * 0.07, 1.5))
		6:   # shades — dark band with glint
			var band_h := eye_r * 1.5
			var band_w := (eye_off.length() + eye_r) * 2.2
			ci.draw_set_transform(c + fwd, perp.angle(), Vector2.ONE)
			ci.draw_rect(Rect2(-band_w * 0.5, -band_h * 0.5, band_w, band_h), Color(0.07, 0.08, 0.12))
			ci.draw_rect(Rect2(-band_w * 0.32, -band_h * 0.28, band_w * 0.18, band_h * 0.2),
				Color(1, 1, 1, 0.5))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		7:   # star pupils
			for e in [l, rr]:
				ci.draw_circle(e, eye_r, Color.WHITE)
				_star(ci, e, eye_r * 0.72, Color(1.0, 0.62, 0.05))
		_:   # 0 classic — round eyes, pupils toward travel
			_eyes(ci, l, rr, eye_r, look, ink)

static func _eyes(ci: CanvasItem, a: Vector2, b: Vector2, eye_r: float, look: Vector2, ink: Color) -> void:
	_eye(ci, a, eye_r, look, ink)
	_eye(ci, b, eye_r, look, ink)

static func _eye(ci: CanvasItem, e: Vector2, eye_r: float, look: Vector2, ink: Color) -> void:
	ci.draw_circle(e, eye_r, Color.WHITE)
	ci.draw_circle(e + look * eye_r * 0.45, eye_r * 0.5, ink)

static func _heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-s * 0.35, -s * 0.25), s * 0.42, col)
	ci.draw_circle(c + Vector2(s * 0.35, -s * 0.25), s * 0.42, col)
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 0.72, -s * 0.05),
		c + Vector2(s * 0.72, -s * 0.05),
		c + Vector2(0, s * 0.85),
	]), col)

static func _star(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + TAU * i / 10.0
		var rad := s if i % 2 == 0 else s * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	ci.draw_colored_polygon(pts, col)
