extends Control

## Draws a row of 3 stars as vector polygons (filled coral for earned,
## outlined pale for unearned). Replaces the old Unicode "★"/"☆" Label,
## whose glyphs didn't render on some platforms/fonts (web export included).

const COL_FILLED := Color("EF846C")
const COL_EMPTY_FILL := Color("FAF5E9")
const COL_EMPTY_OUTLINE := Color("D9C9B8")

const STAR_COUNT := 3
const STAR_SIZE := 22.0
const GAP := 14.0

var stars_earned: int = 0

func set_stars(n: int) -> void:
	stars_earned = clamp(n, 0, STAR_COUNT)
	custom_minimum_size = Vector2(STAR_COUNT * STAR_SIZE + (STAR_COUNT - 1) * GAP, STAR_SIZE)
	queue_redraw()

static func star_points(center: Vector2, outer_r: float, inner_r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(10):
		var r: float = outer_r if i % 2 == 0 else inner_r
		var a: float = -PI / 2.0 + i * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts

func _draw() -> void:
	var total_w: float = STAR_COUNT * STAR_SIZE + (STAR_COUNT - 1) * GAP
	var start_x: float = (size.x - total_w) * 0.5
	var outer_r: float = STAR_SIZE * 0.5
	var inner_r: float = outer_r * 0.42
	for i in range(STAR_COUNT):
		var cx: float = start_x + outer_r + i * (STAR_SIZE + GAP)
		var center := Vector2(cx, size.y * 0.5)
		var pts: PackedVector2Array = star_points(center, outer_r, inner_r)
		if i < stars_earned:
			draw_colored_polygon(pts, COL_FILLED)
		else:
			draw_colored_polygon(pts, COL_EMPTY_FILL)
			var closed: PackedVector2Array = pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, COL_EMPTY_OUTLINE, 2.0, true)
