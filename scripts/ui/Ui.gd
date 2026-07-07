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

## Shared menu background: flat pale mint + big flat pastel blobs + confetti.
## Deliberately crisp — no gradients, no fake blur (both read as banding/mush).
static func draw_bg(ci: CanvasItem, size: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.929, 0.965, 0.945))
	for g in [[0.10, 0.06, 0.34, Color(0.30, 0.78, 0.62)],
			[0.96, 0.28, 0.44, Color(0.45, 0.55, 0.98)],
			[0.14, 0.90, 0.40, Color(0.98, 0.62, 0.35)],
			[0.86, 0.98, 0.34, Color(0.95, 0.45, 0.70)]]:
		var cc: Color = g[3]
		cc.a = 0.10
		ci.draw_circle(Vector2(g[0], g[1]) * size, g[2] * size.x, cc)
	# Sparse confetti dots — playful, still calm.
	var palette := [Color(0.98, 0.62, 0.35), Color(0.45, 0.55, 0.98),
		Color(0.30, 0.78, 0.62), Color(0.95, 0.45, 0.70)]
	for k in 26:
		var px := fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0)
		var py := fposmod(sin(float(k) * 78.2330) * 12543.8500, 1.0)
		var cd: Color = palette[k % 4]
		cd.a = 0.20
		ci.draw_circle(Vector2(px, py) * size, 3.0 + float(k % 3) * 1.6, cd)

## Full-screen dim behind modal panels.
static func dim() -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.06, 0.08, 0.12, 0.55)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	return d
