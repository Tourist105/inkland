class_name IconButton
extends Button
## Round button with a vector icon drawn in code (no glyph/emoji dependency).
## kinds: "pause", "close", "gear", "back", "help"

var kind := "close"
var icon_color := Color.WHITE

static func make(kind_: String, bg: Color, size := 72.0, icon_col := Color.WHITE) -> IconButton:
	var b := IconButton.new()
	b.kind = kind_
	b.icon_color = icon_col
	b.custom_minimum_size = Vector2(size, size)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(int(size / 2.0))
	b.add_theme_stylebox_override("normal", s)
	var sp := s.duplicate()
	sp.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var w := maxf(r * 0.14, 3.0)
	match kind:
		"pause":
			for s: float in [-1.0, 1.0]:
				var x := c.x + s * r * 0.22
				draw_line(Vector2(x, c.y - r * 0.32), Vector2(x, c.y + r * 0.32), icon_color, w)
		"close":
			var d := r * 0.30
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), icon_color, w)
			draw_line(c + Vector2(-d, d), c + Vector2(d, -d), icon_color, w)
		"back":
			var d2 := r * 0.28
			draw_line(c + Vector2(d2 * 0.6, -d2), c + Vector2(-d2 * 0.6, 0), icon_color, w)
			draw_line(c + Vector2(-d2 * 0.6, 0), c + Vector2(d2 * 0.6, d2), icon_color, w)
		"gear":
			draw_arc(c, r * 0.30, 0, TAU, 20, icon_color, w)
			for i in 8:
				var a := TAU * i / 8.0
				var v := Vector2(cos(a), sin(a))
				draw_line(c + v * r * 0.42, c + v * r * 0.58, icon_color, w)
		"help":
			draw_arc(c + Vector2(0, -r * 0.14), r * 0.20, PI * 0.9, PI * 2.35, 12, icon_color, w)
			draw_line(c + Vector2(r * 0.06, 0.0), c + Vector2(0, r * 0.14), icon_color, w)
			draw_circle(c + Vector2(0, r * 0.38), w * 0.62, icon_color)
