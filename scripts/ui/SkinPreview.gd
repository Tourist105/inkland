class_name SkinPreview
extends Control
## Draws one skin's blob mascot — used on shop cards and the home screen.

var skin_idx := 0
var bob := false          # gentle idle animation (home-screen mascot)
var _t := 0.0

static func make(idx: int, px := 120.0, animate := false) -> SkinPreview:
	var p := SkinPreview.new()
	p.skin_idx = idx
	p.bob = animate
	p.custom_minimum_size = Vector2(px, px)
	return p

func _process(delta: float) -> void:
	if bob:
		_t += delta
		queue_redraw()

func _draw() -> void:
	var s: Dictionary = Game.SKINS[clampi(skin_idx, 0, Game.SKINS.size() - 1)]
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.36
	if bob:
		c.y += sin(_t * 2.2) * r * 0.08
		r *= 1.0 + sin(_t * 4.4) * 0.015
	SkinArt.draw_blob(self, c, r, s.color, s.face, Vector2.UP, true, int(s.get("pattern", 0)))
