class_name TestBanner
extends Control
## Full-width placeholder ad banner drawn in code. Shows on-device exactly
## where the AdMob banner will sit, clearly marked as a test ad so no real ad
## ever ships by accident. Real AdMob banner replaces this in M4 via the
## AdsBackend plugin (see Ads.gd). Menus only — never over gameplay.
## Anchor it full-width at the bottom: offset_left = 0, offset_right = 0.

const H := 58.0

static func make() -> TestBanner:
	var b := TestBanner.new()
	b.custom_minimum_size = Vector2(0, H)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(1, 1, 1, 0.97))
	draw_rect(Rect2(0, 0, size.x, 2), Color(0.13, 0.16, 0.24, 0.18))
	var font := ThemeDB.fallback_font
	var cy := size.y * 0.5
	# "Ad" chip.
	draw_rect(Rect2(12, cy - 16, 40, 32), Color(0.98, 0.75, 0.12))
	draw_string(font, Vector2(20, cy + 7), "Ad", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.13, 0.16, 0.24))
	draw_string(font, Vector2(66, cy - 3), "Test ad", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.13, 0.16, 0.24))
	draw_string(font, Vector2(66, cy + 17), "Full-width banner — real ad in production",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.35, 0.40, 0.50))
