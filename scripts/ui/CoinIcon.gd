class_name CoinIcon
extends Control
## Small gold coin drawn in code — used wherever a coin amount is shown.

static func make(d := 34.0) -> CoinIcon:
	var c := CoinIcon.new()
	c.custom_minimum_size = Vector2(d, d)
	return c

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c + Vector2(0, r * 0.08), r, Color(0.72, 0.52, 0.05, 0.55))
	draw_circle(c, r * 0.96, Ui.GOLD)
	draw_arc(c, r * 0.66, 0, TAU, 24, Color(0.86, 0.60, 0.05), maxf(r * 0.14, 2.0))
	draw_circle(c + Vector2(-r * 0.30, -r * 0.34), r * 0.16, Color(1, 1, 1, 0.75))
