extends Node2D

## Draws one hole's course, ball and aim preview. All shapes are drawn
## procedurally (no external image assets) so they stay fully editable,
## per brief section 05/12.

const COL_OUTER := Color("173D32")
const COL_GREEN := Color("A5CC6C")
const COL_WALL_BASE := Color("386048")
const COL_WALL_TOP := Color("55794D")
const COL_SAND := Color("EDD7AB")
const COL_SAND_EDGE := Color("C6AD79")
const COL_HOLE := Color("153C31")
const COL_FLAG_POLE := Color("FFF4DC")
const COL_FLAG := Color("EF846C")
const COL_BALL := Color("FFF8E8")
const COL_BALL_SHADOW := Color("67814D")
const COL_AIM_LIGHT := Color("F6C6BD") # light red/pink: soft power
const COL_AIM_DARK := Color("7A1810")  # dark red: full power
const COL_TRAJECTORY := Color("7A1810", 0.45)
const COL_INVALID := Color("C0392B")

var level: Dictionary = {}
var sim: BallSim
var preview: Dictionary = {"active": false}

func set_level(l: Dictionary) -> void:
	level = l
	queue_redraw()

func set_sim(s: BallSim) -> void:
	sim = s

func set_preview(p: Dictionary) -> void:
	preview = p

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if level.is_empty():
		return
	_draw_course()
	_draw_sand()
	_draw_walls()
	_draw_hole_and_flag()
	if preview.get("active", false):
		_draw_preview()
	if sim:
		_draw_ball()

func _draw_course() -> void:
	draw_rect(Rect2(Vector2.ZERO, Constants.COURSE_SIZE), COL_OUTER, true)
	draw_rect(Constants.PLAY_BOUNDS, COL_GREEN, true)

func _draw_sand() -> void:
	for r in level.sand:
		draw_rect(r, COL_SAND, true)
		draw_rect(r, COL_SAND_EDGE, false, 2.0)

func _draw_walls() -> void:
	for r in level.walls:
		var base: Rect2 = Rect2(r.position + Vector2(0, 4), r.size)
		draw_rect(base, COL_WALL_BASE, true)
		draw_rect(r, COL_WALL_TOP, true)

func _draw_hole_and_flag() -> void:
	var h: Vector2 = level.hole
	draw_circle(h, Constants.HOLE_CAPTURE_RADIUS, COL_HOLE)
	var pole_top: Vector2 = h + Vector2(0, -38)
	draw_line(h, pole_top, COL_FLAG_POLE, 3.0, true)
	var flag_pts := PackedVector2Array([
		pole_top, pole_top + Vector2(27, 10), pole_top + Vector2(0, 20),
	])
	draw_colored_polygon(flag_pts, COL_FLAG)

func _draw_ball() -> void:
	var p: Vector2 = sim.position
	var h: float = sim.height
	# Shadow stays on the ground; shrinks slightly with height.
	var shadow_scale: float = clamp(1.0 - (h / Constants.CHIP_PEAK_HEIGHT) * 0.5, 0.5, 1.0)
	draw_set_transform(p, 0.0, Vector2(shadow_scale, shadow_scale * 0.45))
	draw_circle(Vector2.ZERO, Constants.BALL_RADIUS, Color(0, 0, 0, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var visual_pos: Vector2 = p - Vector2(0, h * 0.6)
	draw_circle(visual_pos, Constants.BALL_RADIUS, COL_BALL)
	draw_arc(visual_pos, Constants.BALL_RADIUS, 0, TAU, 20, COL_BALL_SHADOW, 1.5, true)

func _draw_preview() -> void:
	var mode: int = preview.mode
	var ball_pos: Vector2 = preview.ball_pos
	var direction: Vector2 = preview.direction
	var power_t: float = preview.power_t
	var col: Color = COL_AIM_LIGHT.lerp(COL_AIM_DARK, power_t)

	if mode == BallSim.Mode.PUTT:
		var length: float = lerp(24.0, 150.0, power_t)
		draw_line(ball_pos, ball_pos + direction * length, col, lerp(2.0, 6.0, power_t), true)
		draw_circle(ball_pos + direction * length, 4.0, col)
		var traj: PackedVector2Array = preview.get("trajectory", PackedVector2Array())
		for p in traj:
			draw_circle(p, 2.2, COL_TRAJECTORY)
	else:
		var target: Vector2 = preview.target
		var valid: bool = preview.valid
		var n := 14
		for i in range(n + 1):
			if i % 2 == 0:
				continue
			var t: float = float(i) / float(n)
			var ground: Vector2 = ball_pos.lerp(target, t)
			var arc_h: float = 4.0 * Constants.CHIP_PEAK_HEIGHT * t * (1.0 - t)
			draw_circle(ground - Vector2(0, arc_h * 0.6), 2.0, col)
		if valid:
			draw_arc(target, 6.0, 0, TAU, 16, col, 2.0, true)
		else:
			var s := 6.0
			draw_line(target + Vector2(-s, -s), target + Vector2(s, s), COL_INVALID, 3.0, true)
			draw_line(target + Vector2(-s, s), target + Vector2(s, -s), COL_INVALID, 3.0, true)
