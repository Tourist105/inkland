extends Control
## Home screen — title, animated mascot, Play / Skins / Settings / Help,
## coins + best score. Banner ads live ONLY here and in the shop (never in
## the arena) per the portfolio monetisation rule.

var _t := 0.0
var _coins_label: Label
var _overlay: Control = null

func _ready() -> void:
	_build()
	Ads.show_banner()
	Game.coins_changed.connect(func(total: int) -> void:
		if _coins_label != null:
			_coins_label.text = str(total))
	if not Game.seen_help:
		Game.seen_help = true
		Game.save_state()
		_open_help()

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	Ui.draw_bg(self, size)
	# Decorative rival blobs bobbing in the corners (drawn, not textures).
	var blobs := [
		[Vector2(0.14, 0.20), 30.0, Color(1.00, 0.42, 0.42), 1, 0.0],
		[Vector2(0.87, 0.16), 24.0, Color(0.30, 0.82, 0.55), 2, 1.4],
		[Vector2(0.10, 0.66), 22.0, Color(1.00, 0.72, 0.20), 5, 2.6],
		[Vector2(0.89, 0.62), 27.0, Color(0.62, 0.44, 0.98), 4, 3.9],
	]
	for b in blobs:
		var pos: Vector2 = Vector2(b[0].x * size.x, b[0].y * size.y)
		pos.y += sin(_t * 1.7 + b[4]) * 6.0
		SkinArt.draw_blob(self, pos, b[1], b[2], b[3], Vector2.UP)

func _build() -> void:
	# Corner buttons.
	var help_btn := IconButton.make("help", Color(0.13, 0.16, 0.24, 0.5), 68.0)
	help_btn.position = Vector2(18, 18)
	help_btn.pressed.connect(func() -> void:
		Sfx.play("click")
		_open_help())
	add_child(help_btn)

	var gear := IconButton.make("gear", Color(0.13, 0.16, 0.24, 0.5), 68.0)
	gear.anchor_left = 1.0
	gear.anchor_right = 1.0
	gear.offset_left = -86
	gear.offset_right = -18
	gear.offset_top = 18
	gear.offset_bottom = 86
	gear.pressed.connect(func() -> void:
		Sfx.play("click")
		_open_settings())
	add_child(gear)

	# Central column.
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 90
	col.offset_bottom = -(40 + Ads.banner_height())
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	add_child(col)

	var title := Ui.label("INKLAND", 84, Ui.INK)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.14))
	title.add_theme_constant_override("shadow_offset_y", 5)
	col.add_child(title)
	col.add_child(Ui.label(tr("T_TAGLINE"), 25, Ui.INK_SOFT))

	var mascot := SkinPreview.make(Game.selected_skin, 210.0, true)
	mascot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(mascot)

	if Game.best_pct > 0.0:
		col.add_child(Ui.label("%s  %.1f%%" % [tr("T_BEST"), Game.best_pct], 24, Ui.INK_SOFT))
	var cd: Dictionary = Game.COUNTRIES[Game.country_idx]
	col.add_child(Ui.label("%s  %d/%d%%" % [cd.name, int(Game.country_fill),
		int(cd.size)], 22, Color(0.72, 0.52, 0.05)))

	var play := Button.new()
	play.text = tr("T_PLAY")
	Ui.style_button(play, Ui.ACCENT, 40, Color.WHITE, 40)
	play.custom_minimum_size = Vector2(360, 96)
	play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(func() -> void:
		Sfx.play("click")
		Ads.hide_banner()
		get_tree().change_scene_to_file("res://scenes/Main.tscn"))
	col.add_child(play)

	if Ads.rewarded_ready():
		var boost := Button.new()
		boost.text = tr("T_START_BIG") + "  (AD)"
		Ui.style_button(boost, Color(0.16, 0.72, 0.42), 24)
		boost.custom_minimum_size = Vector2(360, 68)
		boost.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		boost.pressed.connect(func() -> void:
			Sfx.play("click")
			Ads.show_rewarded(func() -> void:
				Game.start_boost = true
				Game.save_state()
				Ads.hide_banner()
				get_tree().change_scene_to_file("res://scenes/Main.tscn")))
		col.add_child(boost)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)

	var shop := Button.new()
	shop.text = tr("T_SHOP")
	Ui.style_button(shop, Color(0.62, 0.44, 0.98), 28)
	shop.custom_minimum_size = Vector2(200, 72)
	shop.pressed.connect(func() -> void:
		Sfx.play("click")
		get_tree().change_scene_to_file("res://scenes/Shop.tscn"))
	row.add_child(shop)

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Ui.card(Color(1, 1, 1, 0.9), 36))
	row.add_child(chip)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	chip.add_child(chip_row)
	var coin := CoinIcon.make(30)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(coin)
	_coins_label = Ui.label(str(Game.coins), 26, Ui.INK)
	chip_row.add_child(_coins_label)

	var daily := Game.claim_daily()
	if daily > 0:
		col.add_child(Ui.label("%s  +%d" % [tr("T_DAILY"), daily], 22,
			Color(0.72, 0.52, 0.05)))

	# Test ad banner (menu only) — marks the real-AdMob slot for M4.
	var banner := TestBanner.make()
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 1.0
	banner.anchor_bottom = 1.0
	banner.offset_left = -160
	banner.offset_right = 160
	banner.offset_top = -60
	banner.offset_bottom = -8
	add_child(banner)

# ----------------------------------------------------------------- overlays --

func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null

func _overlay_base(min_w: float) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var dim := Ui.dim()
	_overlay.add_child(dim)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed:
			Sfx.play("click")
			_close_overlay())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Ui.card(Ui.PAPER, 26))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -min_w * 0.5
	panel.offset_right = min_w * 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_overlay.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	return v

func _open_help() -> void:
	var v := _overlay_base(500)
	v.add_child(Ui.label(tr("T_HELP"), 36, Ui.INK))
	var texts := ["T_HELP_1", "T_HELP_2", "T_HELP_3", "T_HELP_4"]
	var dots := [Ui.ACCENT, Color(1.00, 0.42, 0.42), Color(0.30, 0.82, 0.55), Ui.GOLD]
	for i in texts.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var dot := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = dots[i]
		sb.set_corner_radius_all(9)
		dot.add_theme_stylebox_override("panel", sb)
		dot.custom_minimum_size = Vector2(18, 18)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var lab := Ui.label(tr(texts[i]), 20, Ui.INK)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		v.add_child(row)
	var ok := Button.new()
	ok.text = tr("T_OK")
	Ui.style_button(ok, Ui.ACCENT, 28)
	ok.pressed.connect(func() -> void:
		Sfx.play("click")
		_close_overlay())
	v.add_child(ok)

func _open_settings() -> void:
	var v := _overlay_base(460)
	v.add_child(Ui.label(tr("T_SETTINGS"), 36, Ui.INK))

	var snd := CheckButton.new()
	snd.text = tr("T_SOUND")
	snd.button_pressed = Game.sound_on
	_style_check(snd)
	snd.toggled.connect(func(on: bool) -> void:
		Game.sound_on = on
		Game.save_state()
		Sfx.play("click"))
	v.add_child(snd)

	var hap := CheckButton.new()
	hap.text = tr("T_HAPTICS")
	hap.button_pressed = Game.haptics_on
	_style_check(hap)
	hap.toggled.connect(func(on: bool) -> void:
		Game.haptics_on = on
		Game.save_state()
		Sfx.play("click")
		if on:
			Sfx.haptic(30))
	v.add_child(hap)

	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 12)
	var lang_lab := Ui.label(tr("T_LANGUAGE"), 24, Ui.INK)
	lang_row.add_child(lang_lab)
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 22)
	opt.add_item(tr("T_SYS_LANG"))
	for code in Game.LOCALES:
		opt.add_item(Game.LOCALE_NAMES[code])
	var sel := 0
	if Game.locale != "":
		sel = Game.LOCALES.find(Game.locale) + 1
	opt.select(sel)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.item_selected.connect(func(i: int) -> void:
		Game.set_app_locale("" if i == 0 else Game.LOCALES[i - 1])
		get_tree().reload_current_scene())
	lang_row.add_child(opt)
	v.add_child(lang_row)

	var privacy := Button.new()
	privacy.text = tr("T_PRIVACY")
	Ui.style_button(privacy, Ui.PAPER_DIM, 22, Ui.INK_SOFT)
	privacy.pressed.connect(func() -> void:
		Sfx.play("click")
		OS.shell_open(Game.PRIVACY_URL))
	v.add_child(privacy)

	v.add_child(Ui.label("%s %s" % [tr("T_VERSION"), Game.VERSION], 16, Ui.INK_SOFT))

	var ok := Button.new()
	ok.text = tr("T_OK")
	Ui.style_button(ok, Ui.ACCENT, 28)
	ok.pressed.connect(func() -> void:
		Sfx.play("click")
		_close_overlay())
	v.add_child(ok)

func _style_check(c: CheckButton) -> void:
	c.add_theme_font_size_override("font_size", 24)
	c.add_theme_color_override("font_color", Ui.INK)
	c.add_theme_color_override("font_pressed_color", Ui.INK)
	c.add_theme_color_override("font_hover_color", Ui.INK)
	c.add_theme_color_override("font_focus_color", Ui.INK)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _overlay != null:
			_close_overlay()
		else:
			get_tree().quit()
