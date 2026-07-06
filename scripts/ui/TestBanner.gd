class_name TestBanner
extends Control
## Visible placeholder ad banner (320x50-style) drawn in code. Shows on-device
## exactly where the AdMob banner will sit, clearly marked as a test ad so no
## real ad ever ships by accident. Real AdMob banner replaces this in M4 via
## the AdsBackend plugin (see Ads.gd). Menus only — never over gameplay.

static func make() -> TestBanner:
	var b := TestBanner.new()
	b.custom_minimum_size = Vector2(320, 52)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sb := StyleBoxFlat.new()
	draw_rect(r, Color(1, 1, 1, 0.95))
	draw_rect(r, Color(0.13, 0.16, 0.24, 0.25), false, 1.5)
	var font := ThemeDB.fallback_font
	# "Ad" chip.
	draw_rect(Rect2(6, 6, 34, size.y - 12), Color(0.98, 0.75, 0.12))
	draw_string(font, Vector2(12, size.y * 0.5 + 6), "Ad",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.13, 0.16, 0.24))
	draw_string(font, Vector2(52, size.y * 0.5 - 2), "Test ad",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.13, 0.16, 0.24))
	draw_string(font, Vector2(52, size.y * 0.5 + 16), "This is a 320x50 test banner",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.40, 0.50))
