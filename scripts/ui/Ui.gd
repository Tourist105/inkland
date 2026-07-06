class_name Ui
## Shared UI factory helpers — one visual language for every screen.
## Paper-light surfaces, deep-ink text, candy-coloured pill buttons.

const INK := Color(0.13, 0.16, 0.24)          # primary text / dark elements
const INK_SOFT := Color(0.35, 0.40, 0.50)     # secondary text
const PAPER := Color(0.965, 0.972, 0.99)      # light surface
const PAPER_DIM := Color(0.905, 0.925, 0.965)
const ACCENT := Color(0.23, 0.55, 1.00)       # azure (default brand accent)
const GOLD := Color(0.98, 0.75, 0.12)

static func pill(bg: Color, radius := 28, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 12
	s.content_margin_bottom = 14
	if border.a > 0.0:
		s.set_border_width_all(4)
		s.border_color = border
	return s

static func style_button(b: Button, bg: Color, font_size := 30, fg := Color.WHITE, radius := 28) -> void:
	b.add_theme_stylebox_override("normal", pill(bg, radius))
	b.add_theme_stylebox_override("hover", pill(bg.lightened(0.08), radius))
	b.add_theme_stylebox_override("pressed", pill(bg.darkened(0.14), radius))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)

static func label(text: String, size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

static func card(bg := PAPER, radius := 24) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.13)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 22
	s.content_margin_bottom = 22
	return s

## Shared menu background: soft vertical gradient + faint paper grid.
static func draw_bg(ci: CanvasItem, size: Vector2) -> void:
	var bands := 20
	var top := Color(0.965, 0.975, 0.995)
	var bot := Color(0.895, 0.92, 0.965)
	var bh := size.y / bands
	for b in range(bands):
		ci.draw_rect(Rect2(0, b * bh, size.x, bh + 1.0),
			top.lerp(bot, float(b) / float(bands - 1)))
	var line := Color(0, 0, 0, 0.03)
	var step := 48.0
	var x := step
	while x < size.x:
		ci.draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
		x += step
	var y := step
	while y < size.y:
		ci.draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += step

## Full-screen dim behind modal panels.
static func dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.06, 0.08, 0.12, 0.55)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	return d
