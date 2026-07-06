extends Node
## Sound + haptics. Autoload "Sfx". All WAVs are original synthesized audio
## (see tools/gen_sfx.py). Respects the sound/vibration settings in Game.

const NAMES := ["click", "tick", "go", "capture", "coin", "kill", "death"]
const POOL_SIZE := 8

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func play(sfx_name: String, pitch := 1.0, vol_db := 0.0) -> void:
	if not Game.sound_on:
		return
	var s: AudioStream = _streams.get(sfx_name)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.pitch_scale = pitch
			p.volume_db = vol_db
			p.play()
			return

## Short device vibration (no-op on desktop / when disabled).
func haptic(ms: int) -> void:
	if Game.haptics_on:
		Input.vibrate_handheld(ms)
