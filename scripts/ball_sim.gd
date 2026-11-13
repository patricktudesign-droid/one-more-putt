class_name BallSim
extends RefCounted

## Deterministic ball/rules simulation shared by every hole. Pure GDScript
## (no scene-tree dependency) so it can be driven headlessly in tests and by
## the live game at a fixed 60Hz physics step.
##
## Known interpretation calls on ambiguous brief wording are flagged inline
## with "ASSUMPTION:" and summarised again in VALIDATION_LOG.md.

enum Mode { PUTT, CHIP }
enum State { RESTING, ROLLING, FLYING }

# --- Level geometry (set by setup) ---
var start_pos: Vector2
var hole_pos: Vector2
var walls: Array = []       # Array[Rect2], low internal walls (height Constants.LOW_WALL_HEIGHT)
var sand: Array = []        # Array[Rect2]
var bounds: Rect2 = Constants.PLAY_BOUNDS

# --- Live state ---
var position: Vector2
var velocity: Vector2 = Vector2.ZERO
var height: float = 0.0
var state: int = State.RESTING
var mode: int = Mode.PUTT
var in_sand: bool = false
var rest_timer: float = 0.0
var strokes: int = 0
var completed: bool = false

# Purely cosmetic: a 2D spin angle driven by ground distance travelled
# (arc length / radius, as if rolling without slipping), so the view layer
# can draw a visibly rotating ball instead of a sliding disc.
var rotation: float = 0.0

# Chip flight bookkeeping
var flight_t: float = 0.0
var flight_start: Vector2
var flight_target: Vector2
var flight_power: float = 0.0  # "equivalent putt speed" derived from chip input, used for landing roll

# One-shot event flags, consumed by the caller each step() via the returned dict.
func setup(level: Dictionary) -> void:
	start_pos = level.ball
	hole_pos = level.hole
	walls = level.walls.duplicate()
	sand = level.sand.duplicate()
	reset()

func reset() -> void:
	position = start_pos
	velocity = Vector2.ZERO
	height = 0.0
	state = State.RESTING
	in_sand = point_in_sand(position)
	mode = Mode.CHIP if in_sand else Mode.PUTT
	rest_timer = Constants.REST_TIME_REQUIRED
	strokes = 0
	completed = false
	flight_t = 0.0
	rotation = 0.0

func can_shoot() -> bool:
	return state == State.RESTING and not completed

func point_in_sand(p: Vector2) -> bool:
	for r in sand:
		if r.has_point(p):
			return true
	return false

static func circle_rect_overlap(center: Vector2, radius: float, rect: Rect2) -> bool:
	var cx: float = clamp(center.x, rect.position.x, rect.position.x + rect.size.x)
	var cy: float = clamp(center.y, rect.position.y, rect.position.y + rect.size.y)
	return center.distance_squared_to(Vector2(cx, cy)) <= radius * radius

static func circle_rect_normal(center: Vector2, rect: Rect2) -> Vector2:
	# Normal pointing from the rect surface toward the ball centre, used for bounce().
	var cx: float = clamp(center.x, rect.position.x, rect.position.x + rect.size.x)
	var cy: float = clamp(center.y, rect.position.y, rect.position.y + rect.size.y)
	var closest := Vector2(cx, cy)
	var delta: Vector2 = center - closest
	if delta.length_squared() > 0.0001:
		return delta.normalized()
	# Centre is inside the rect: push out along the axis of least penetration.
	var left: float = center.x - rect.position.x
	var right: float = (rect.position.x + rect.size.x) - center.x
	var top: float = center.y - rect.position.y
	var bottom: float = (rect.position.y + rect.size.y) - center.y
	var m: float = min(min(left, right), min(top, bottom))
	if m == left:
		return Vector2.LEFT
	elif m == right:
		return Vector2.RIGHT
	elif m == top:
		return Vector2.UP
	else:
		return Vector2.DOWN

func _outer_blocked(center: Vector2) -> bool:
	# Outer walls are always impassable, at any height. Approximate the solid
	# boundary as "ball circle must stay within the inset play bounds".
	return center.x - Constants.BALL_RADIUS < bounds.position.x \
		or center.y - Constants.BALL_RADIUS < bounds.position.y \
		or center.x + Constants.BALL_RADIUS > bounds.position.x + bounds.size.x \
		or center.y + Constants.BALL_RADIUS > bounds.position.y + bounds.size.y

func _outer_normal(center: Vector2) -> Vector2:
	var n := Vector2.ZERO
	if center.x - Constants.BALL_RADIUS < bounds.position.x:
		n.x = 1
	elif center.x + Constants.BALL_RADIUS > bounds.position.x + bounds.size.x:
		n.x = -1
	if center.y - Constants.BALL_RADIUS < bounds.position.y:
		n.y = 1
	elif center.y + Constants.BALL_RADIUS > bounds.position.y + bounds.size.y:
		n.y = -1
	if n == Vector2.ZERO:
		return Vector2.UP
	return n.normalized()

# --- Shot commands --------------------------------------------------------

func shoot_putt(direction: Vector2, speed: float) -> void:
	if not can_shoot():
		return
	strokes += 1
	velocity = direction.normalized() * clamp(speed, 0.0, Constants.PUTT_MAX_SPEED)
	state = State.ROLLING
	rest_timer = 0.0

func shoot_chip(direction: Vector2, distance: float) -> void:
	if not can_shoot():
		return
	strokes += 1
	var d: float = clamp(distance, 0.0, Constants.CHIP_MAX_RANGE)
	flight_start = position
	flight_target = position + direction.normalized() * d
	flight_power = (d / Constants.CHIP_MAX_RANGE) * Constants.PUTT_MAX_SPEED
	flight_t = 0.0
	state = State.FLYING
	rest_timer = 0.0

# Preview-only validity check, mirrors _resolve_landing's overlap test without
# mutating state. Used by the aim UI to show the crossed "invalid" marker.
func is_chip_target_valid(target: Vector2) -> bool:
	if _outer_blocked(target):
		return false
	for w in walls:
		if circle_rect_overlap(target, Constants.BALL_RADIUS, w):
			return false
	return true

# --- Stepping ---------------------------------------------------------

## Advances the simulation by one fixed tick. Returns a dict of one-shot events
## for the caller to react to (sound/UI), e.g. {hole_complete, blocked_landing,
## entered_sand, bounced, settled}.
func step(delta: float) -> Dictionary:
	var events := {
		"hole_complete": false,
		"blocked_landing": false,
		"bounced": false,
		"settled": false,
		"entered_sand": false,
	}
	if completed:
		return events

	var was_in_sand: bool = in_sand
	match state:
		State.FLYING:
			_step_flight(delta, events)
		State.ROLLING:
			_step_rolling(delta, events)
		State.RESTING:
			pass

	if state != State.FLYING:
		in_sand = point_in_sand(position)
	if in_sand and not was_in_sand:
		events.entered_sand = true

	# Hole capture: only while grounded (never airborne), ball centre within
	# capture radius and slow enough; a faster ball can pass over the cup.
	if state != State.FLYING and not completed:
		var dist_to_hole: float = position.distance_to(hole_pos)
		if dist_to_hole <= Constants.HOLE_CAPTURE_RADIUS \
				and velocity.length() <= Constants.HOLE_CAPTURE_MAX_SPEED:
			completed = true
			velocity = Vector2.ZERO
			state = State.RESTING
			events.hole_complete = true
		elif state == State.ROLLING and dist_to_hole <= Constants.LIP_OUT_RADIUS and velocity.length() > 0.0:
			_apply_lip_out(dist_to_hole, delta)

	# Rest detection: sustained low speed for REST_TIME_REQUIRED, then snap to zero.
	if state == State.ROLLING:
		if velocity.length() < Constants.REST_SPEED_THRESHOLD:
			rest_timer += delta
			if rest_timer >= Constants.REST_TIME_REQUIRED:
				velocity = Vector2.ZERO
				state = State.RESTING
				mode = Mode.CHIP if in_sand else Mode.PUTT
				events.settled = true
		else:
			rest_timer = 0.0

	return events

## A ball passing near the cup too fast to drop gets gently curved around the
## rim rather than rolling straight past it — a "lip out". Bends velocity
## direction toward the tangent of the cup, strongest right at the rim and
## fading out toward LIP_OUT_RADIUS, without changing speed.
func _apply_lip_out(dist_to_hole: float, delta: float) -> void:
	var outward: Vector2 = (position - hole_pos).normalized()
	var tangent: Vector2 = Vector2(-outward.y, outward.x)
	if tangent.dot(velocity) < 0.0:
		tangent = -tangent
	var span: float = Constants.LIP_OUT_RADIUS - Constants.HOLE_CAPTURE_RADIUS
	var proximity: float = clamp(1.0 - (dist_to_hole - Constants.HOLE_CAPTURE_RADIUS) / span, 0.0, 1.0)
	var pull: float = clamp(proximity * Constants.LIP_OUT_STRENGTH * delta, 0.0, 1.0)
	var speed: float = velocity.length()
	velocity = velocity.normalized().lerp(tangent, pull).normalized() * speed

func _step_rolling(delta: float, events: Dictionary) -> void:
	var speed: float = velocity.length()
	if speed <= 0.0:
		state = State.RESTING
		mode = Mode.CHIP if in_sand else Mode.PUTT
		return
	var dir: Vector2 = velocity.normalized()

	var remaining: float = speed * delta
	var steps: int = max(1, int(ceil(remaining / Constants.MAX_SUBSTEP_DISTANCE)))
	var sub_dt: float = delta / float(steps)

	for i in range(steps):
		var cur_speed: float = velocity.length()
		if cur_speed <= 0.0:
			break
		dir = velocity.normalized()
		var step_dist: float = cur_speed * sub_dt
		var tentative: Vector2 = position + dir * step_dist

		var hit_normal: Vector2 = Vector2.ZERO
		if _outer_blocked(tentative):
			hit_normal = _outer_normal(tentative)
		else:
			for w in walls:
				if circle_rect_overlap(tentative, Constants.BALL_RADIUS + Constants.WALL_COLLISION_MARGIN, w):
					hit_normal = circle_rect_normal(position, w)
					break

		if hit_normal != Vector2.ZERO:
			# Partial-restitution impulse along the normal only: damps the
			# into-the-wall component by (1+e), leaves the along-the-wall
			# (tangential) component untouched. velocity.bounce(n)*e (the
			# previous approach) scales the *entire* vector by e, which
			# bleeds off tangential speed on every bounce — wrong for a
			# glancing hit, which should keep sliding along the wall.
			var impact_speed: float = velocity.dot(hit_normal)
			if impact_speed < 0.0:
				velocity -= (1.0 + Constants.WALL_RESTITUTION) * impact_speed * hit_normal
			events.bounced = true
		else:
			rotation += step_dist / Constants.BALL_RADIUS
			position = tentative

		# Rolling resistance: base + k*speed on green (real friction and
		# rolling resistance combine this way — gentler at low speed,
		# stronger at high speed, versus a flat per-tick deceleration),
		# flat on sand. Recomputed every substep since it depends on the
		# ball's current speed, which changes across substeps.
		var decel: float = Constants.SAND_PUTT_RESISTANCE if in_sand \
			else Constants.PUTT_RESISTANCE_BASE + Constants.PUTT_RESISTANCE_K * velocity.length()
		var new_speed: float = max(0.0, velocity.length() - decel * sub_dt)
		if velocity.length() > 0.0:
			velocity = velocity.normalized() * new_speed
		if new_speed <= 0.0:
			velocity = Vector2.ZERO
			break

func _step_flight(delta: float, events: Dictionary) -> void:
	var tentative_t: float = flight_t + delta / Constants.CHIP_FLIGHT_TIME
	var clamped_t: float = clamp(tentative_t, 0.0, 1.0)
	var tentative_ground: Vector2 = flight_start.lerp(flight_target, clamped_t)
	var tentative_height: float = 4.0 * Constants.CHIP_PEAK_HEIGHT * clamped_t * (1.0 - clamped_t)

	# Reference clears a low wall once height exceeds the wall's own height,
	# no extra radius padding (ball.z<17 is its whole clearance check).
	var clearance_ok: bool = tentative_height > Constants.LOW_WALL_HEIGHT
	var obstructed: bool = _outer_blocked(tentative_ground)
	if not obstructed and not clearance_ok:
		for w in walls:
			if circle_rect_overlap(tentative_ground, Constants.BALL_RADIUS, w):
				obstructed = true
				break

	if obstructed:
		# "Collide and fall on the incoming side": land at the last clear spot.
		_resolve_landing(position, events)
		return

	if tentative_t >= 1.0:
		_resolve_landing(flight_target, events)
		return

	rotation += position.distance_to(tentative_ground) / Constants.BALL_RADIUS
	flight_t = tentative_t
	position = tentative_ground
	height = tentative_height

func _resolve_landing(land_pos: Vector2, events: Dictionary) -> void:
	height = 0.0
	var invalid := _outer_blocked(land_pos)
	if not invalid:
		for w in walls:
			if circle_rect_overlap(land_pos, Constants.BALL_RADIUS, w):
				invalid = true
				break

	if invalid:
		events.blocked_landing = true
		state = State.RESTING
		# Caller (Hole) is expected to restore the pre-shot snapshot for a
		# true "Blocked landing" per the brief; the sim just parks here.
		velocity = Vector2.ZERO
		return

	position = land_pos
	in_sand = point_in_sand(position)
	if in_sand:
		# "A chip landing in sand stays there."
		velocity = Vector2.ZERO
		state = State.RESTING
		mode = Mode.CHIP
		rest_timer = Constants.REST_TIME_REQUIRED
	else:
		var dir: Vector2 = (flight_target - flight_start)
		if dir.length_squared() < 0.0001:
			dir = Vector2.UP
		dir = dir.normalized()
		var roll_speed: float = Constants.LANDING_ROLL_FRACTION * flight_power
		if roll_speed > 0.0:
			velocity = dir * roll_speed
			state = State.ROLLING
		else:
			velocity = Vector2.ZERO
			state = State.RESTING
			mode = Mode.PUTT
			rest_timer = Constants.REST_TIME_REQUIRED

# --- Undo / restart -----------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"height": height,
		"state": state,
		"mode": mode,
		"in_sand": in_sand,
		"rest_timer": rest_timer,
		"strokes": strokes,
		"completed": completed,
	}

func restore(snap: Dictionary) -> void:
	position = snap.position
	velocity = snap.velocity
	height = snap.height
	state = snap.state
	mode = snap.mode
	in_sand = snap.in_sand
	rest_timer = snap.rest_timer
	strokes = snap.strokes
	completed = snap.completed
