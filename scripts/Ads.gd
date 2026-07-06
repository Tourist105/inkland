extends Node
## Ad seam. Autoload "Ads". Banner (full-width, menus), ONE rewarded video
## (2x coins / continue), and interstitials at natural breaks (after a run).
##
## Production backend lands at M4: install the AdMob Android editor plugin,
## then add res://scripts/AdsBackend.gd (Node) implementing:
##   func init(app_id: String) -> void
##   func show_banner(unit_id: String) -> void
##   func hide_banner() -> void
##   func load_rewarded(unit_id: String) -> void
##   func is_rewarded_ready() -> bool
##   func show_rewarded(on_earned: Callable) -> void
##   func show_interstitial(on_done: Callable) -> void
## This autoload picks it up automatically at boot. Until then the banner is a
## visible on-screen TEST placeholder and the interstitial is a TEST overlay,
## so the whole flow is testable today and no real ad ships by accident.
##
## Google TEST ids on purpose — real ids are wired only immediately before the
## production release (from the AdMob console once the app entry exists).

const APP_ID := "ca-app-pub-3940256099942544~3347511713"
const BANNER_ID := "ca-app-pub-3940256099942544/6300978111"
const REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
const INTERSTITIAL_ID := "ca-app-pub-3940256099942544/1033173712"

## Show an interstitial once every N runs (tune for revenue vs. retention).
const INTERSTITIAL_EVERY := 2

var _backend: Node = null
var _runs_since_ad := 0

func _ready() -> void:
	var backend_path := "res://scripts/AdsBackend.gd"
	if ResourceLoader.exists(backend_path):
		var script: GDScript = load(backend_path)
		_backend = script.new()
		add_child(_backend)
		_backend.init(APP_ID)
		_backend.load_rewarded(REWARDED_ID)

## Height (px) menus should reserve at the bottom for the banner.
func banner_height() -> int:
	return 140 if _backend != null else 0

func show_banner() -> void:
	if _backend != null:
		_backend.show_banner(BANNER_ID)

func hide_banner() -> void:
	if _backend != null:
		_backend.hide_banner()

func rewarded_ready() -> bool:
	if _backend != null:
		return _backend.is_rewarded_ready()
	return OS.has_feature("editor")   # editor-only simulation for UX testing

func show_rewarded(on_earned: Callable) -> void:
	if _backend != null:
		_backend.show_rewarded(on_earned)
		_backend.load_rewarded(REWARDED_ID)
	elif OS.has_feature("editor"):
		await get_tree().create_timer(0.6).timeout
		if on_earned.is_valid():   # scene may have been swapped meanwhile
			on_earned.call()

## Call at the end of a run. Shows an interstitial every INTERSTITIAL_EVERY
## runs, then invokes on_done (proceed to results/menu). Always eventually
## calls on_done so game flow never stalls.
func maybe_interstitial(on_done: Callable) -> void:
	_runs_since_ad += 1
	if _runs_since_ad < INTERSTITIAL_EVERY:
		on_done.call()
		return
	_runs_since_ad = 0
	if _backend != null and _backend.has_method("show_interstitial"):
		_backend.show_interstitial(on_done)
	else:
		_show_test_interstitial(on_done)

## Full-screen TEST interstitial placeholder with a 3s countdown + close.
func _show_test_interstitial(on_done: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.17, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var font := ThemeDB.fallback_font
	var lbl := Label.new()
	lbl.text = "Test interstitial ad"
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.75, 0.12))
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.offset_left = -300
	lbl.offset_right = 300
	lbl.offset_top = -40
	layer.add_child(lbl)
	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.offset_left = -300
	sub.offset_right = 300
	sub.offset_top = 16
	layer.add_child(sub)
	var done := false
	var finish := func() -> void:
		if done:
			return
		done = true
		layer.queue_free()
		if on_done.is_valid():
			on_done.call()
	for i in range(3, 0, -1):
		sub.text = "closes in %d…" % i
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(layer):
			return
	finish.call()
