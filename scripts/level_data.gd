class_name LevelData
extends RefCounted

## Five holes transcribed verbatim from the brief's "Build coordinates" panels
## (section 04). Coordinates are local to the 320x480 playfield, origin top-left,
## matching Godot's 2D coordinate convention exactly, so no conversion is needed.

static func rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x, y, w, h)

static func holes() -> Array:
	return [
		{
			"name": "First putt",
			"target": 1,
			"ball": Vector2(160, 390),
			"hole": Vector2(160, 90),
			"walls": [],
			"sand": [],
		},
		{
			"name": "Around the corner",
			"target": 2,
			"ball": Vector2(80, 390),
			"hole": Vector2(80, 90),
			"walls": [rect(20, 210, 155, 24)],
			"sand": [],
		},
		{
			"name": "Out of the sand",
			"target": 2,
			"ball": Vector2(160, 360),
			"hole": Vector2(160, 100),
			"walls": [],
			"sand": [rect(115, 315, 90, 90)],
		},
		{
			"name": "The useful bunker",
			"target": 2,
			"ball": Vector2(90, 390),
			"hole": Vector2(90, 110),
			"walls": [rect(20, 210, 190, 22)],
			"sand": [rect(50, 260, 80, 65)],
		},
		{
			"name": "Your route",
			"target": 3,
			"ball": Vector2(75, 400),
			"hole": Vector2(245, 85),
			"walls": [rect(120, 180, 24, 150)],
			"sand": [rect(55, 335, 70, 50)],
		},
	]
