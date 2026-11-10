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
const COL_HOLE_RIM := Color("2E5B46")   # worn-turf lip around the cup
const COL_HOLE_DEEP := Color("0A1D17")  # inner shadow, suggests depth
const COL_FLAG_POLE := Color("FFF4DC")
const COL_FLAG := Color("EF846C")
const COL_BALL := Color("FFF8E8")
const COL_BALL_SHADE := Color("D8CFB8") # darker edge, cheap sphere shading
const COL_BALL_HIGHLIGHT := Color("FFFFFF", 0.8)
const COL_BALL_DIMPLE := Color("C9BFA6")
const COL_AIM_LIGHT := Color("F6C6BD") # light red/pink: soft power
const COL_AIM_DARK := Color("7A1810")  # dark red: full power
const COL_TRAJECTORY := Color("7A1810", 0.45)
const COL_INVALID := Color("C0392B")

var level: Dictionary = {}
var sim: BallSim
var preview: Dictionary = {"active": false}

# 1.0 = normal size, 0.0 = fully sunk. Animated by play_sink_animation().
var sink_t: float = 1.0
var _sink_tween: Tween

func set_level(l: Dictionary) -> void:
	level = l
	sink_t = 1.0
	queue_redraw()

func set_sim(s: BallSim) -> void:
	sim = s

func set_preview(p: Dictionary) -> void:
	preview = p

## Shrinks the ball into the cup over a short tween, for the completion
## sequence. Call reset_sink() first if replaying the same hole in place.
func play_sink_animation(duration: float = 0.4) -> void:
	sink_t = 1.0
	if _sink_tween:
		_sink_tween.kill()
	_sink_tween = create_tween()
	_sink_tween.tween_property(self, "sink_t", 0.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func reset_sink() -> void:
	if _sink_tween:
		_sink_tween.kill()
	sink_t = 1.0

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
	# Recessed cup: a worn-turf rim, a dark bowl, and an inner shadow crescent
	# offset toward the bottom-right (away from an implied top-left light),
	# so it reads as a hole sunk into the green rather than a flat disc.
	draw_circle(h, Constants.HOLE_CAPTURE_RADIUS + 2.5, COL_HOLE_RIM)
	draw_circle(h, Constants.HOLE_CAPTURE_RADIUS, COL_HOLE)
	draw_circle(h + Vector2(1.2, 1.2), Constants.HOLE_CAPTURE_RADIUS * 0.68, COL_HOLE_DEEP)
	var pole_top: Vector2 = h + Vector2(0, -38)
	draw_line(h, pole_top, COL_FLAG_POLE, 3.0, true)
	var flag_pts := PackedVector2Array([
		pole_top, pole_top + Vector2(27, 10), pole_top + Vector2(0, 20),
	])
	draw_colored_polygon(flag_pts, COL_FLAG)

func _draw_ball() -> void:
	if sink_t <= 0.001:
		return # fully sunk — nothing left to draw
	var p: Vector2 = sim.position
	var h: float = sim.height
	var radius: float = Constants.BALL_RADIUS * sink_t

	# Ground shadow: stays on the ground regardless of height, shrinks and
	# fades the higher the ball is (a chip's own "how high am I" readout).
	var height_t: float = clamp(h / Constants.CHIP_PEAK_HEIGHT, 0.0, 1.0)
	var shadow_scale: float = lerp(1.0, 0.45, height_t) * sink_t
	var shadow_alpha: float = lerp(0.28, 0.1, height_t)
	draw_set_transform(p, 0.0, Vector2(shadow_scale, shadow_scale * 0.45))
	draw_circle(Vector2.ZERO, Constants.BALL_RADIUS, Color(0, 0, 0, shadow_alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var visual_pos: Vector2 = p - Vector2(0, h * 0.6)

	# Cheap sphere shading: base fill, a soft darker edge toward the
	# bottom-right, a crisp rim line, and a small fixed highlight toward the
	# top-left (a stable implied light, independent of the ball's own spin).
	draw_circle(visual_pos, radius, COL_BALL)
	draw_circle(visual_pos + Vector2(radius, radius) * 0.22, radius * 0.88, COL_BALL_SHADE.lerp(COL_BALL, 0.6))
	draw_arc(visual_pos, radius, 0, TAU, 20, COL_BALL_SHADE, 1.2, true)
	draw_circle(visual_pos - Vector2(radius, radius) * 0.32, radius * 0.3, COL_BALL_HIGHLIGHT)

	# Travel-driven rolling texture: a couple of dimples that spin with
	# sim.rotation (arc length / radius), so a rolling ball visibly rolls
	# instead of sliding — unlike the highlight above, these rotate.
	if radius > 1.0:
		draw_set_transform(visual_pos, sim.rotation, Vector2.ONE)
		draw_circle(Vector2(radius * 0.4, 0), radius * 0.16, COL_BALL_DIMPLE)
		draw_circle(Vector2(-radius * 0.2, radius * 0.45), radius * 0.13, COL_BALL_DIMPLE)
		draw_circle(Vector2(-radius * 0.2, -radius * 0.45), radius * 0.13, COL_BALL_DIMPLE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
