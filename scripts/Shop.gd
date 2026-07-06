extends Control
## Skin shop — 3-column grid of procedurally drawn skin cards.
## Tap an owned skin to select it; tap a locked one to buy it with coins.

var _coins_label: Label
var _cards: Array[Button] = []
var _toast: Label = null

func _ready() -> void:
	_build()
	Ads.show_banner()
	Game.coins_changed.connect(func(total: int) -> void:
		if _coins_label != null:
			_coins_label.text = str(total))

func _draw() -> void:
	Ui.draw_bg(self, size)

func _build() -> void:
	# Top bar.
	var back := IconButton.make("back", Color(0.13, 0.16, 0.24, 0.5), 68.0)
	back.position = Vector2(18, 18)
	back.pressed.connect(_go_back)
	add_child(back)

	var title := Ui.label(tr("T_SHOP"), 40, Ui.INK)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 26
	add_child(title)

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Ui.card(Color(1, 1, 1, 0.9), 30))
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.offset_left = -160
	chip.offset_right = -18
	chip.offset_top = 18
	add_child(chip)
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_theme_constant_override("separation", 8)
	chip.add_child(chip_row)
	var coin := CoinIcon.make(28)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_row.add_child(coin)
	_coins_label = Ui.label(str(Game.coins), 24, Ui.INK)
	chip_row.add_child(_coins_label)

	# Scrollable card grid.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 110
	scroll.offset_left = 16
	scroll.offset_right = -16
	scroll.offset_bottom = -(16 + Ads.banner_height())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for i in Game.SKINS.size():
		grid.add_child(_make_card(i))
	_refresh()

	_toast = Ui.label("", 22, Color.WHITE)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.13, 0.16, 0.24, 0.92)
	tsb.set_corner_radius_all(22)
	tsb.content_margin_left = 24
	tsb.content_margin_right = 24
	tsb.content_margin_top = 10
	tsb.content_margin_bottom = 12
	_toast.add_theme_stylebox_override("normal", tsb)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -(120 + Ads.banner_height())
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.visible = false
	add_child(_toast)

func _make_card(i: int) -> Button:
	var s: Dictionary = Game.SKINS[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(160, 206)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: _tap(i))
	var v := VBoxContainer.new()
	v.name = "V"
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var prev := SkinPreview.make(i, 104.0)
	prev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(prev)
	var name_l := Ui.label(s.name, 19, Ui.INK)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var price_row := HBoxContainer.new()
	price_row.name = "PriceRow"
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 6)
	price_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := CoinIcon.make(20)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(pc)
	var price_l := Ui.label(str(s.price), 18, Ui.INK_SOFT)
	price_l.name = "Price"
	price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_row.add_child(price_l)
	v.add_child(price_row)
	_cards.append(b)
	return b

func _refresh() -> void:
	for i in _cards.size():
		var b := _cards[i]
		var s: Dictionary = Game.SKINS[i]
		var owned := Game.is_unlocked(i)
		var selected := Game.selected_skin == i
		var border: Color = s.color if selected else Color.TRANSPARENT
		if s.color.v < 0.35 and selected:
			border = Ui.ACCENT
		var sb := Ui.card(Color(1, 1, 1, 0.92), 22)
		if border.a > 0.0:
			sb.set_border_width_all(5)
			sb.border_color = border
		b.add_theme_stylebox_override("normal", sb)
		var sbp := sb.duplicate()
		sbp.bg_color = Color(0.93, 0.95, 0.98)
		b.add_theme_stylebox_override("pressed", sbp)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var row: HBoxContainer = b.get_node("V/PriceRow")
		row.visible = not owned
		if not owned:
			(row.get_node("Price") as Label).text = str(s.price)

func _tap(i: int) -> void:
	if Game.is_unlocked(i):
		Game.select_skin(i)
		Sfx.play("click")
	else:
		var price: int = Game.SKINS[i].price
		if Game.try_spend(price):
			Game.unlock_skin(i)
			Game.select_skin(i)
			Sfx.play("coin")
			Sfx.haptic(30)
		else:
			Sfx.play("click", 0.6)
			_show_toast(tr("T_NOT_ENOUGH"))
	_refresh()

func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void: _toast.visible = false)

func _go_back() -> void:
	Sfx.play("click")
	get_tree().change_scene_to_file("res://scenes/Home.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
