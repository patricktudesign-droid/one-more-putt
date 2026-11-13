extends Node2D

## Draws one hole's course, ball and aim preview. All shapes are drawn
## procedurally (no external image assets) so they stay fully editable,
## per brief section 05/12.
##
## Art direction for the frame/turf/ball/cup (2026-11-13) follows the
## supplied HTML reference prototype (preview.html): a layered "raised
## edge" course frame with a soft shadow, a subtle grain texture on turf
## and sand, a two-tone-plus-highlight wall, and cheap sphere shading on
## the ball with dimples gated to its near hemisphere as it spins. Godot's
## immediate-mode 2D drawing has no native linear/radial gradient fill, so
## gradients are approximated with banded rects (turf) or a small stack of
## off-centre circles (ball) rather than a true per-pixel gradient. Corner
## rounding from the reference is skipped — our existing frame, walls and
## sand are already sharp-cornered, and rounding wasn't itself called out
## as part of the ask ("raised edges and soft shadows").

const COL_FRAME_SHADOW := Color("102A22")
const COL_FRAME_MID := Color("2E5B46")
const COL_FRAME_LIGHT := Color("4A7A55")
const COL_TURF_TOP := Color("B8D681")
const COL_TURF_BOTTOM := Color("87B75D")
const COL_GRAIN := Color(0.25, 0.38, 0.23, 0.08)

const COL_WALL_BASE := Color("386048")
const COL_WALL_TOP := Color("55794D")
const COL_WALL_HIGHLIGHT := Color("AAC377")
const COL_SAND := Color("EDD7AB")
const COL_SAND_SHADOW := Color("AE905D")
const COL_SAND_SPECKLE := Color(0.42, 0.34, 0.2, 0.22)

const COL_HOLE := Color("153C31")
const COL_HOLE_RIM := Color("C5DE88")   # catches light, like the reference's outer ring
const COL_HOLE_DEEP := Color("0A1D17")  # inner shadow, suggests depth
const COL_FLAG_POLE := Color("FFF4DC")
const COL_FLAG := Color("EF846C")

const COL_BALL_EDGE := Color("B7BDA5")
const COL_BALL_MID := Color("F4F0DC")
const COL_BALL_HILITE := Color("FFFDF3")
const COL_BALL_DIMPLE := Color("7C8870", 0.5)

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

# Precomputed once (not regenerated per draw, or the texture would look
# like flickering static) — same cheap hash-based point set the reference
# uses for its turf grain and sand speckle, scaled to our course.
var _grain: PackedVector2Array = []

func _ready() -> void:
	_grain.resize(400)
	for i in range(_grain.size()):
		var x: float = fmod(float(i * 7919 + i * i * 17), 10007.0) / 10007.0
		var y: float = fmod(float(i * 3329 + i * i * 31), 10009.0) / 10009.0
		_grain[i] = Vector2(x, y)

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

## A rect inset by `margin` on every side of the full course canvas.
func _inset_rect(margin: float) -> Rect2:
	return Rect2(Vector2(margin, margin), Constants.COURSE_SIZE - Vector2(margin, margin) * 2.0)

func _draw_course() -> void:
	# Layered "raised edge" frame: each successive layer is inset a bit
	# more than the last, so a thin band of the darker layer beneath shows
	# around every edge — a simple, symmetric stand-in for the reference's
	# soft-shadow/raised-lip look. PLAY_BOUNDS itself (the actual play
	# area, fixed by the physics) is untouched.
	draw_rect(_inset_rect(4.0), COL_FRAME_SHADOW, true)
	draw_rect(_inset_rect(8.0), COL_FRAME_MID, true)
	draw_rect(_inset_rect(13.0), COL_FRAME_LIGHT, true)
	_draw_turf_gradient(Constants.PLAY_BOUNDS)
	_draw_grain(Constants.PLAY_BOUNDS, 0, 260)

func _draw_turf_gradient(rect: Rect2) -> void:
	var bands := 14
	var band_h: float = rect.size.y / float(bands)
	for i in range(bands):
		var t: float = float(i) / float(bands - 1)
		var col: Color = COL_TURF_TOP.lerp(COL_TURF_BOTTOM, t)
		draw_rect(Rect2(rect.position.x, rect.position.y + i * band_h, rect.size.x, band_h + 1.0), col, true)

func _draw_grain(rect: Rect2, start_idx: int, count: int) -> void:
	for i in range(count):
		var pt: Vector2 = _grain[(start_idx + i) % _grain.size()]
		var x: float = rect.position.x + pt.x * rect.size.x
		var y: float = rect.position.y + pt.y * rect.size.y
		draw_rect(Rect2(x, y, 1.3, 1.1), COL_GRAIN, true)

func _draw_sand() -> void:
	for r in level.sand:
		draw_rect(Rect2(r.position + Vector2(0, 2), r.size), COL_SAND_SHADOW, true)
		draw_rect(r, COL_SAND, true)
		for i in range(60):
			var pt: Vector2 = _grain[i]
			var x: float = r.position.x + 6.0 + pt.x * max(1.0, r.size.x - 12.0)
			var y: float = r.position.y + 5.0 + pt.y * max(1.0, r.size.y - 10.0)
			draw_rect(Rect2(x, y, 1.3, 1.0), COL_SAND_SPECKLE, true)

func _draw_walls() -> void:
	for r in level.walls:
		var base: Rect2 = Rect2(r.position + Vector2(0, 4), r.size)
		draw_rect(base, COL_WALL_BASE, true)
		draw_rect(r, COL_WALL_TOP, true)
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(max(0.0, r.size.x - 2.0), 2.0)), COL_WALL_HIGHLIGHT, true)

func _draw_hole_and_flag() -> void:
	var h: Vector2 = level.hole
	# Recessed cup: a light catch-light rim, a dark bowl, and an inner
	# shadow offset upward (light implied from above, like the reference's
	# top-to-bottom gradient) so it reads as sunk into the green.
	draw_circle(h, Constants.HOLE_CAPTURE_RADIUS + 2.5, COL_HOLE_RIM)
	draw_circle(h, Constants.HOLE_CAPTURE_RADIUS, COL_HOLE)
	draw_circle(h + Vector2(0, 1.5), Constants.HOLE_CAPTURE_RADIUS * 0.7, COL_HOLE_DEEP)
	var pole_top: Vector2 = h + Vector2(0, -38)
	draw_line(h, pole_top, COL_FLAG_POLE, 3.0, true)
	var flag_pts := PackedVector2Array([
		pole_top, pole_top + Vector2(27, 10), pole_top + Vector2(0, 20),
	])
	draw_colored_polygon(flag_pts, COL_FLAG)

func _draw_ball() -> void:
	if sink_t <= 0.001:
		return # fully sunk — nothing left to draw
	# While sinking, drift toward the cup centre and settle slightly deeper
	# (not just shrink in place) — matches the reference's sink sequence,
	# which interpolates position toward the hole and adds a small extra
	# downward offset as it disappears.
	var sink_progress: float = 1.0 - sink_t
	var p: Vector2 = sim.position.lerp(level.hole, sink_progress) + Vector2(0, sink_progress * 3.0)
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

	# Cheap sphere shading approximating a radial gradient (Godot's
	# immediate-mode drawing has no native gradient fill): an edge-tone
	# base circle sets the true silhouette, then two smaller circles
	# centred toward an implied top-left light brighten that corner.
	var light_center: Vector2 = visual_pos + Vector2(-0.3, -0.37) * radius
	draw_circle(visual_pos, radius, COL_BALL_EDGE)
	draw_circle(light_center, radius * 0.82, COL_BALL_MID)
	draw_circle(light_center, radius * 0.32, COL_BALL_HILITE)
	draw_arc(visual_pos, radius, 0, TAU, 20, COL_BALL_EDGE, 1.0, true)

	# Travel-driven rolling texture: dimples laid out along the direction
	# of travel (heading) and swept by the spin phase (rotation), gated to
	# the near hemisphere via a cosine visibility check — the same trick
	# the reference uses so dimples fade in/out as the ball actually spins,
	# rather than just being fixed marks that rotate in place.
	if radius > 1.0:
		draw_set_transform(visual_pos, sim.heading, Vector2.ONE)
		for i in range(7):
			var phase: float = sim.rotation + i * 0.91
			if cos(phase) > 0.0:
				var dx: float = sin(phase) * radius * 0.62
				var dy: float = (float(i % 3) - 1.0) * radius * 0.32
				draw_circle(Vector2(dx, dy), radius * 0.13, COL_BALL_DIMPLE)
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
