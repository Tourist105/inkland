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
	var neutral := Color(1, 1, 1, 0.92)
	var water := Color(0, 0, 0, 0)       # only the country silhouette shows
	for y in arena.H:
		for x in arena.W:
			var i: int = y * arena.W + x
			if arena._land[i] == 0:
				_img.set_pixel(x, y, water)
				continue
			var o: int = arena.grid[i]
			_img.set_pixel(x, y, neutral if o == 0 else arena.players[o - 1].color)
	_tex.update(_img)
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var sc := size / Vector2(arena.W * arena.CELL, arena.H * arena.CELL)
	# Country outline — the original-style navy silhouette ring.
	for lp in arena._land_loops:
		var pts: PackedVector2Array = lp.pts
		var ring := PackedVector2Array()
		for q in pts:
			ring.append(q * sc)
		if ring.size() >= 3:
			ring.append(ring[0])
			draw_polyline(ring, Color(0.16, 0.22, 0.42, 0.85), 1.8)
	for p in arena.players:
		if p.alive:
			var pt: Vector2 = p.pos * sc
			draw_circle(pt, 3.5 if p.is_human else 2.5, p.color)
			if p.is_human:
				draw_circle(pt, 3.5, Color.WHITE, false, 1.5)
