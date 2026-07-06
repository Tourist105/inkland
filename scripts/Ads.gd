extends Node
## Ad seam. Autoload "Ads". Portfolio rules: banner in MENUS only, ONE optional
## rewarded video (2x coins / continue-after-death). NEVER interstitials.
##
## Production backend lands at M4: install the AdMob Android editor plugin,
## then add res://scripts/AdsBackend.gd (Node) implementing:
##   func init(app_id: String) -> void
##   func show_banner(unit_id: String) -> void
##   func hide_banner() -> void
##   func load_rewarded(unit_id: String) -> void
##   func is_rewarded_ready() -> bool
##   func show_rewarded(on_earned: Callable) -> void
## This autoload picks it up automatically at boot. Until then, everything
## no-ops on devices, and the rewarded flow is SIMULATED in the editor only,
## so the whole UX is testable today and no fake ads can ever ship.
##
## Google TEST ids on purpose — portfolio rule: real ids are wired only
## immediately before the production release (they come from the AdMob console
## once the Inkland app entry exists).

const APP_ID := "ca-app-pub-3940256099942544~3347511713"
const BANNER_ID := "ca-app-pub-3940256099942544/6300978111"
const REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"

var _backend: Node = null

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
