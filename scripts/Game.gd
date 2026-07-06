extends Node
## Global game state — coins, records, skins, settings. Autoload "Game".
## Persists to user://inkland.cfg (ConfigFile; no cloud, no accounts).

const SAVE_PATH := "user://inkland.cfg"
const VERSION := "1.0.0"
const PRIVACY_URL := "https://tourist105.github.io/privacy/"

signal coins_changed(total: int)

## Skin catalog — original palette, faces drawn procedurally in SkinArt.gd.
## face ids: 0 classic, 1 happy, 2 wink, 3 heart, 4 angry, 5 sleepy, 6 shades, 7 star
## Skin names are proper nouns (deliberately untranslated, like character names).
const SKINS := [
	{"name": "Azure",  "price": 0,   "color": Color(0.23, 0.55, 1.00), "face": 0},
	{"name": "Sunset", "price": 100, "color": Color(1.00, 0.54, 0.24), "face": 1},
	{"name": "Minty",  "price": 150, "color": Color(0.22, 0.82, 0.54), "face": 2},
	{"name": "Bubble", "price": 200, "color": Color(1.00, 0.42, 0.71), "face": 3},
	{"name": "Lava",   "price": 250, "color": Color(1.00, 0.30, 0.23), "face": 4},
	{"name": "Ocean",  "price": 300, "color": Color(0.10, 0.75, 0.81), "face": 5},
	{"name": "Violet", "price": 350, "color": Color(0.62, 0.42, 1.00), "face": 0},
	{"name": "Noir",   "price": 400, "color": Color(0.17, 0.19, 0.25), "face": 6},
	{"name": "Sunny",  "price": 500, "color": Color(1.00, 0.82, 0.25), "face": 7},
]

## Locales shipped in assets/translations/strings.csv. v1 = scripts Godot's
## bundled font renders cleanly; CJK/Arabic/Thai/Devanagari need bundled font
## packs and land with the store-listing pass (M4).
const LOCALES: Array[String] = ["en", "de", "fr", "it", "es", "pt", "nl", "pl",
	"tr", "cs", "sk", "sv", "da", "nb", "fi", "hu", "ro", "ru", "uk", "el", "id", "vi"]
const LOCALE_NAMES := {
	"en": "English", "de": "Deutsch", "fr": "Français", "it": "Italiano",
	"es": "Español", "pt": "Português", "nl": "Nederlands", "pl": "Polski",
	"tr": "Türkçe", "cs": "Čeština", "sk": "Slovenčina", "sv": "Svenska",
	"da": "Dansk", "nb": "Norsk", "fi": "Suomi", "hu": "Magyar",
	"ro": "Română", "ru": "Русский", "uk": "Українська", "el": "Ελληνικά",
	"id": "Indonesia", "vi": "Tiếng Việt",
}

var coins: int = 0
var best_pct: float = 0.0
var games_played: int = 0
var selected_skin: int = 0
var unlocked: Array = [0]
var sound_on := true
var haptics_on := true
var locale := ""            # "" = follow system
var last_bonus_day := ""
var seen_help := false
var country_idx := 0
var country_fill := 0.0

## Country-conquest meta (paper.io-2 style): every round's best territory %
## fills the current country; complete it for a bonus and the next country.
const COUNTRIES := [
	{"name": "Switzerland", "size": 100}, {"name": "Austria", "size": 130},
	{"name": "Netherlands", "size": 150}, {"name": "Portugal", "size": 170},
	{"name": "Greece", "size": 190}, {"name": "Italy", "size": 220},
	{"name": "Germany", "size": 250}, {"name": "France", "size": 280},
	{"name": "Spain", "size": 300}, {"name": "Poland", "size": 320},
	{"name": "United Kingdom", "size": 350}, {"name": "Turkey", "size": 380},
	{"name": "Japan", "size": 420}, {"name": "Brazil", "size": 470},
	{"name": "USA", "size": 520}, {"name": "World", "size": 999},
]
const COUNTRY_TINTS := [Color(1, 1, 1), Color(1.0, 0.97, 0.90),
	Color(0.92, 0.97, 1.0), Color(0.94, 1.0, 0.94), Color(1.0, 0.94, 0.96)]

func _ready() -> void:
	load_state()
	apply_locale()

# ------------------------------------------------------------------ economy --

## +50 coins on the first launch of each day (D1 retention hook).
func claim_daily() -> int:
	var today := Time.get_date_string_from_system()
	if today == last_bonus_day:
		return 0
	last_bonus_day = today
	add_coins(50)
	return 50


## Add a round's % to the country; returns bonus coins if one was completed.
func add_country_progress(pct: float) -> int:
	country_fill += pct
	var bonus := 0
	while country_idx < COUNTRIES.size() - 1 			and country_fill >= float(COUNTRIES[country_idx].size):
		country_fill -= float(COUNTRIES[country_idx].size)
		country_idx += 1
		bonus += 150
	if bonus > 0:
		add_coins(bonus)
	else:
		save_state()
	return bonus

func country_tint() -> Color:
	return COUNTRY_TINTS[country_idx % COUNTRY_TINTS.size()]

func add_coins(n: int) -> void:
	coins += n
	coins_changed.emit(coins)
	save_state()

func try_spend(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins)
	save_state()
	return true

# -------------------------------------------------------------------- skins --

func is_unlocked(i: int) -> bool:
	return unlocked.has(i)

func unlock_skin(i: int) -> void:
	if not unlocked.has(i):
		unlocked.append(i)
	save_state()

func select_skin(i: int) -> void:
	selected_skin = clampi(i, 0, SKINS.size() - 1)
	save_state()

func skin() -> Dictionary:
	return SKINS[clampi(selected_skin, 0, SKINS.size() - 1)]

# ------------------------------------------------------------------- record --

## Returns true if pct is a new best.
func submit_round(pct: float, _kills: int) -> bool:
	games_played += 1
	var is_best := pct > best_pct
	if is_best:
		best_pct = pct
	save_state()
	return is_best

# ------------------------------------------------------------------- locale --

func apply_locale() -> void:
	if locale != "" and LOCALES.has(locale):
		TranslationServer.set_locale(locale)
	else:
		var sys := OS.get_locale_language()
		TranslationServer.set_locale(sys if LOCALES.has(sys) else "en")

func set_app_locale(code: String) -> void:
	locale = code
	apply_locale()
	save_state()

# --------------------------------------------------------------- save / load --

func save_state() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "coins", coins)
	cf.set_value("s", "best_pct", best_pct)
	cf.set_value("s", "games_played", games_played)
	cf.set_value("s", "selected_skin", selected_skin)
	cf.set_value("s", "unlocked", unlocked)
	cf.set_value("s", "sound_on", sound_on)
	cf.set_value("s", "haptics_on", haptics_on)
	cf.set_value("s", "locale", locale)
	cf.set_value("s", "last_bonus_day", last_bonus_day)
	cf.set_value("s", "seen_help", seen_help)
	cf.set_value("s", "country_idx", country_idx)
	cf.set_value("s", "country_fill", country_fill)
	cf.save(SAVE_PATH)

func load_state() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	coins = cf.get_value("s", "coins", 0)
	best_pct = cf.get_value("s", "best_pct", 0.0)
	games_played = cf.get_value("s", "games_played", 0)
	selected_skin = cf.get_value("s", "selected_skin", 0)
	unlocked = cf.get_value("s", "unlocked", [0])
	sound_on = cf.get_value("s", "sound_on", true)
	haptics_on = cf.get_value("s", "haptics_on", true)
	locale = cf.get_value("s", "locale", "")
	last_bonus_day = cf.get_value("s", "last_bonus_day", "")
	seen_help = cf.get_value("s", "seen_help", false)
	country_idx = cf.get_value("s", "country_idx", 0)
	country_fill = cf.get_value("s", "country_fill", 0.0)
	if not unlocked.has(0):
		unlocked.append(0)
