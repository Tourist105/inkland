class_name MiniMap
extends Control
## Live overview of the whole arena — territory as a smooth scaled texture
## (linear filtering, so no visible tiles) plus head dots.

var arena
var _img: Image
var _tex: ImageTexture

func setup(arena_) -> void:
	arena = arena_
	_img = Image.create(arena.W, arena.H, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	custom_minimum_size = Vector2(92, 158)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh() -> void:
	var neutral := Color(1, 1, 1, 0.45)
	for y in arena.H:
		for x in arena.W:
			var o: int = arena.grid[y * arena.W + x]
			_img.set_pixel(x, y, neutral if o == 0 else arena.players[o - 1].color)
	_tex.update(_img)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size).grow(3.0), Color(0.13, 0.16, 0.24, 0.4))
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var sc := size / Vector2(arena.W * arena.CELL, arena.H * arena.CELL)
	for p in arena.players:
		if p.alive:
			var pt: Vector2 = p.pos * sc
			draw_circle(pt, 3.5 if p.is_human else 2.5, p.color)
			if p.is_human:
				draw_circle(pt, 3.5, Color.WHITE, false, 1.5)
