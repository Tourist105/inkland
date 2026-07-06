extends Node
## Dev-only screenshot helper (autoload). Inert unless the INKLAND_SHOT env
## var is set, so it costs one getenv call in production and does nothing.
## Also used to produce Play-listing screenshots.
##
##   INKLAND_SHOT=C:/path/out.png [INKLAND_SHOT_FRAME=240] godot --path . [scene]

func _ready() -> void:
	var target := OS.get_environment("INKLAND_SHOT")
	if target.is_empty():
		return
	var frame_s := OS.get_environment("INKLAND_SHOT_FRAME")
	_capture(target, int(frame_s) if frame_s.is_valid_int() else 240)

func _capture(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("DevShot saved: ", path)
	get_tree().quit()
