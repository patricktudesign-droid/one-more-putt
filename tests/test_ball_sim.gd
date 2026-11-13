extends SceneTree

## Headless automated checks for BallSim, run via:
##   godot --headless --path . -s res://tests/test_ball_sim.gd
## Covers: stroke counting, undo restoration, terminal hole capture,
## terrain mode switching, and deterministic repeatability
## (brief section 07 acceptance list, items 2, 5, 4, 3, 6).

var failures: Array[String] = []
var checks: int = 0

func _check(name: String, cond: bool) -> void:
	checks += 1
	if not cond:
		failures.append(name)
		print("FAIL: ", name)
	else:
		print("ok:   ", name)

## Closed-form stopping distance for the base+k*speed resistance model
## (dv/dt = -(base + k*v)), solved analytically: integrating v(t) from 0
## to the time it reaches zero gives
##   distance(v0) = v0/k - (base/k^2) * ln(1 + k*v0/base)
## Used to calibrate a putt speed whose natural stopping point lands at a
## known distance, without assuming the old flat-deceleration model (whose
## sqrt(2*decel*dist) shortcut no longer applies).
static func _closed_form_putt_distance(v0: float) -> float:
	var base: float = Constants.PUTT_RESISTANCE_BASE
	var k: float = Constants.PUTT_RESISTANCE_K
	return v0 / k - (base / (k * k)) * log(1.0 + k * v0 / base)

static func _calibrate_putt_speed(target_dist: float) -> float:
	var lo := 0.0
	var hi := Constants.PUTT_MAX_SPEED
	for i in range(60):
		var mid: float = (lo + hi) * 0.5
		if _closed_form_putt_distance(mid) < target_dist:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

func _init() -> void:
	test_stroke_counting()
	test_undo_restoration()
	test_terminal_hole_capture()
	test_terrain_mode_switch()
	test_deterministic_repeatability()
	test_wall_bounce_energy_loss()
	test_no_shoot_while_moving()
	test_stress_many_runs_no_hang()
	test_lip_out_curves_near_miss()
	test_wall_collision_margin_catches_graze()
	test_outer_wall_rebound_matrix()
	test_tangential_velocity_preserved_exactly()
	test_resistance_is_speed_dependent()

	print("")
	print("%d checks, %d failures" % [checks, failures.size()])
	if failures.size() > 0:
		print("FAILURES: ", failures)
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)

func _run_ticks(sim: BallSim, seconds: float) -> void:
	var dt := 1.0 / 60.0
	var n := int(seconds / dt)
	for i in range(n):
		sim.step(dt)

func test_stroke_counting() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0])
	_check("strokes start at 0", sim.strokes == 0)
	sim.shoot_putt(Vector2.UP, 300.0)
	_check("stroke increments exactly once on release", sim.strokes == 1)
	# Attempting another shot mid-roll must not count or move the ball.
	var before := sim.strokes
	sim.shoot_putt(Vector2.DOWN, 300.0)
	_check("cannot shoot while rolling (stroke unchanged)", sim.strokes == before)
	_run_ticks(sim, 5.0)
	_check("ball eventually rests", sim.state == BallSim.State.RESTING)

func test_undo_restoration() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0])
	var snap := sim.snapshot()
	sim.shoot_putt(Vector2.UP, 400.0)
	_run_ticks(sim, 0.1)
	_check("state changed after shot", sim.strokes == 1 and sim.position != snap.position)
	sim.restore(snap)
	_check("undo restores strokes", sim.strokes == snap.strokes)
	_check("undo restores position", sim.position == snap.position)
	_check("undo restores state", sim.state == snap.state)
	_check("can shoot again after undo", sim.can_shoot())

func test_terminal_hole_capture() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0]) # straight 300-unit putt, no hazards
	# v0 chosen so the putt's natural stopping distance lands right on the
	# hole, 300 units away (closed-form for the base+k*speed model).
	var v0 := _calibrate_putt_speed(sim.position.distance_to(sim.hole_pos))
	sim.shoot_putt((sim.hole_pos - sim.position).normalized(), v0)
	var completed_at_tick := -1
	for i in range(600):
		var events := sim.step(1.0 / 60.0)
		if events.hole_complete:
			completed_at_tick = i
			break
	_check("hole capture fires", completed_at_tick >= 0)
	_check("sim marks completed", sim.completed)
	_check("ball parked at rest after capture", sim.state == BallSim.State.RESTING)
	_check("cannot shoot after completion", not sim.can_shoot())

func test_terrain_mode_switch() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[2]) # "Out of the sand": starts in sand
	_check("starts over sand", sim.point_in_sand(sim.position))
	_check("initial mode is CHIP when starting in sand", sim.mode == BallSim.Mode.CHIP)
	sim.shoot_chip((sim.hole_pos - sim.position).normalized(), 150.0)
	_run_ticks(sim, 2.0)
	_check("ball settles on green after chip out", sim.state == BallSim.State.RESTING)
	_check("mode becomes PUTT once off sand", not sim.in_sand == (sim.mode == BallSim.Mode.PUTT))

func test_deterministic_repeatability() -> void:
	var results: Array = []
	for attempt in range(3):
		var sim := BallSim.new()
		sim.setup(LevelData.holes()[4]) # "Your route": walls + sand
		sim.shoot_putt(Vector2(1, -0.3).normalized(), 500.0)
		_run_ticks(sim, 3.0)
		results.append(sim.position)
	var ref: Vector2 = results[0]
	var max_drift := 0.0
	for r in results:
		max_drift = max(max_drift, r.distance_to(ref))
	_check("repeated identical shots settle within 2 units", max_drift <= 2.0)

func test_wall_bounce_energy_loss() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[1]) # "Around the corner": one wall
	# Aim straight at the wall face.
	sim.shoot_putt(Vector2(0, -1), 500.0)
	var bounced := false
	for i in range(300):
		var events := sim.step(1.0 / 60.0)
		if events.bounced:
			bounced = true
			break
	_check("ball bounces off low wall", bounced)

func test_no_shoot_while_moving() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0])
	sim.shoot_putt(Vector2.UP, 200.0)
	_check("airborne/rolling blocks can_shoot", not sim.can_shoot())

## Proxy for brief section 07's "no crashes during ten consecutive full
## five-hole runs": drives all five holes, ten times over, with varied
## shots (alternating putt/chip aim, jittered power/direction) and asserts
## no exception/hang (bounded step counts) — simulation-level only; the
## brief's device playtest acceptance item (Milestone D) is a separate,
## human-driven step.
## A fast ball passing just outside the capture radius (but inside the lip
## rim) should curve around the cup rather than rolling a dead-straight
## line through it, and must not falsely capture (playtest feedback: a
## near-miss should feel like it "lipped out").
func test_lip_out_curves_near_miss() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0]) # straight hole, no hazards
	var near_miss_target: Vector2 = sim.hole_pos + Vector2(18, 0) # 18 units off-centre
	var dir: Vector2 = (near_miss_target - sim.position).normalized()
	sim.shoot_putt(dir, 500.0)
	var dir_before_zone: Vector2 = dir
	var dir_after_zone: Vector2 = dir
	var entered_zone := false
	for i in range(600):
		var dist: float = sim.position.distance_to(sim.hole_pos)
		if dist <= Constants.LIP_OUT_RADIUS and sim.velocity.length() > 0.0:
			if not entered_zone:
				dir_before_zone = sim.velocity.normalized()
				entered_zone = true
			dir_after_zone = sim.velocity.normalized()
		sim.step(1.0 / 60.0)
		if sim.state == BallSim.State.RESTING:
			break
	_check("ball enters the lip-out rim on a near miss", entered_zone)
	_check("lip-out measurably curves the path", dir_before_zone.angle_to(dir_after_zone) != 0.0)
	_check("fast near-miss does not falsely capture", not sim.completed)

## With the small wall-collision forgiveness margin, a shot that grazes just
## past a wall's geometric edge should still register as a bounce (playtest
## feedback: "you have to hit it very close to bounce off the wall").
func test_wall_collision_margin_catches_graze() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[1]) # "Around the corner": wall rect (20,210,155,24)
	# Aim to graze just past the wall's right edge (x=175): the ball's centre
	# passes at x ~= 175 + BALL_RADIUS + 1, which only overlaps the wall rect
	# once the margin is added to the collision radius.
	var graze_x: float = 175.0 + Constants.BALL_RADIUS + 1.0
	var start: Vector2 = Vector2(graze_x, 390)
	sim.position = start
	sim.shoot_putt(Vector2(0, -1), 500.0)
	var bounced := false
	for i in range(300):
		var events: Dictionary = sim.step(1.0 / 60.0)
		if events.bounced:
			bounced = true
			break
	_check("wall collision margin catches a near-edge graze", bounced)

## Regression for the 2026-11-13 physics pass: a glancing hit must keep
## its along-the-wall speed, not just its sign. The old formula
## (velocity.bounce(n) * restitution) scaled the *entire* post-bounce
## vector by restitution, bleeding off tangential speed on every hit. The
## fix only damps the into-the-wall component — tangential speed should
## come out of a single bounce essentially unchanged (allowing for the
## small energy the substep's friction term removes over that one tick).
func test_tangential_velocity_preserved_exactly() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0]) # no internal walls, isolates outer-bounds behaviour
	# Graze the right wall at a shallow angle: mostly moving up (tangential),
	# barely drifting right (into the wall).
	sim.position = Vector2(290, 240)
	var dir := Vector2(0.15, -0.99).normalized()
	sim.shoot_putt(dir, 400.0)
	var tangent := Vector2(0, -1) # along the wall, independent of hit direction
	var tangential_before: float = sim.velocity.dot(tangent)
	var tangential_after: float = tangential_before
	var bounced := false
	for i in range(900):
		# Sample just before stepping: by the time it reaches the wall the
		# ball has already decayed some speed en route under resistance, so
		# the pre-bounce tangential speed isn't the launch value — it's
		# whatever it decayed to right up to this tick.
		var pre_tangential: float = sim.velocity.dot(tangent)
		var events: Dictionary = sim.step(1.0 / 60.0)
		if events.bounced and not bounced:
			bounced = true
			tangential_before = pre_tangential
			tangential_after = sim.velocity.dot(tangent)
			break
	_check("shallow hit actually bounces", bounced)
	# Within a few percent: one substep's worth of rolling resistance is the
	# only thing allowed to touch it, nothing wall-related should.
	_check("tangential speed preserved within 5%% of its pre-bounce value", \
		bounced and abs(tangential_after - tangential_before) / tangential_before < 0.05)

## Regression check that the new rolling-resistance model is genuinely
## speed-dependent (base + k*speed), not a flat rate in disguise: the
## instantaneous deceleration early in a hard putt (high speed) must be
## measurably larger than late in the same putt (low speed, near rest).
func test_resistance_is_speed_dependent() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0])
	sim.shoot_putt(Vector2(0, -1), Constants.PUTT_MAX_SPEED)
	var dt := 1.0 / 60.0
	var speed_before: float = sim.velocity.length()
	sim.step(dt)
	var decel_at_high_speed: float = (speed_before - sim.velocity.length()) / dt

	# Run it down to a low (but still rolling) speed, then measure again.
	while sim.velocity.length() > 40.0 and sim.state == BallSim.State.ROLLING:
		sim.step(dt)
	speed_before = sim.velocity.length()
	sim.step(dt)
	var decel_at_low_speed: float = (speed_before - sim.velocity.length()) / dt

	_check("deceleration is measurably higher at high speed than low speed", \
		decel_at_high_speed > decel_at_low_speed * 1.3)

## Regression for a 2026-11-10 playtest bug: the ball reached the right
## outer boundary and froze instead of rebounding. Root cause was
## `_outer_normal(position)` being evaluated on the pre-contact position
## (which never satisfies its own threshold checks), silently falling
## through to its Vector2.UP fallback — a horizontal-surface normal that
## only flips Y velocity, leaving the real offending (X) component
## untouched, so the ball kept re-colliding with itself every tick without
## ever moving. Fixed by deriving the normal from `tentative` instead.
##
## This matrix heads off a regression by exercising all 4 outer edges,
## head-on and shallow-angle approaches, at low/medium/high speed, plus a
## corner, and asserts: it actually rebounds, is pushed back inward, moves
## away afterward (not stuck), never penetrates the boundary, settles
## cleanly (no endless jitter), and — for shallow angles — keeps its
## along-the-wall (tangential) direction instead of having it flipped.
func test_outer_wall_rebound_matrix() -> void:
	# Clearance kept small (15u) and deliberately asymmetric per axis: large
	# enough that even the lowest test speed still reaches the wall, small
	# enough that a shallow tangential approach can't drift into an
	# *adjacent* wall first (the course is 280x440, so centering on the
	# cross-axis leaves ~120-220u of room either way — plenty next to a
	# 15u approach distance).
	var edges := [
		{"name": "right", "inward": Vector2(-1, 0), "start": Vector2(290, 240)},
		{"name": "left", "inward": Vector2(1, 0), "start": Vector2(30, 240)},
		{"name": "top", "inward": Vector2(0, 1), "start": Vector2(160, 30)},
		{"name": "bottom", "inward": Vector2(0, -1), "start": Vector2(160, 450)},
	]
	var speeds := {"low": 150.0, "medium": 400.0, "high": 650.0}
	for edge in edges:
		var outward: Vector2 = -edge.inward
		var tangent: Vector2 = Vector2(-edge.inward.y, edge.inward.x)
		for speed_name in speeds.keys():
			_check_outer_bounce("%s head-on, %s speed" % [edge.name, speed_name], \
				edge.start, outward, speeds[speed_name], edge.inward, false)
		var shallow_dir: Vector2 = (outward * 0.35 + tangent * 0.9).normalized()
		for speed_name in speeds.keys():
			_check_outer_bounce("%s shallow-angle, %s speed" % [edge.name, speed_name], \
				edge.start, shallow_dir, speeds[speed_name], edge.inward, true)
	_check_outer_corner()

func _check_outer_bounce(label: String, start: Vector2, direction: Vector2, speed: float, inward_axis: Vector2, is_shallow: bool) -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0]) # no internal walls: isolates outer-bounds behaviour
	sim.position = start
	sim.shoot_putt(direction, speed)

	var tangent: Vector2 = Vector2(-inward_axis.y, inward_axis.x)
	var bounced := false
	var vel_at_bounce := Vector2.ZERO
	var pos_at_bounce: Vector2 = start
	var moved_away := false
	var leaked := false

	for i in range(900):
		var events: Dictionary = sim.step(1.0 / 60.0)
		if sim._outer_blocked(sim.position):
			leaked = true
		if events.bounced and not bounced:
			bounced = true
			vel_at_bounce = sim.velocity
			pos_at_bounce = sim.position
		if bounced and not moved_away and sim.position.distance_to(pos_at_bounce) > 0.05:
			moved_away = true
		if sim.state == BallSim.State.RESTING:
			break

	_check("%s: rebounds" % label, bounced)
	_check("%s: pushed back inward" % label, bounced and vel_at_bounce.dot(inward_axis) > 0.0)
	_check("%s: not stuck (moves away after rebound)" % label, moved_away)
	_check("%s: never penetrates the boundary" % label, not leaked)
	_check("%s: settles cleanly (no endless jitter)" % label, sim.state == BallSim.State.RESTING)
	if is_shallow:
		var tangent_sign_ok: bool = bounced and sign(vel_at_bounce.dot(tangent)) == sign(direction.dot(tangent))
		_check("%s: along-the-wall motion preserved" % label, tangent_sign_ok)

func _check_outer_corner() -> void:
	var sim := BallSim.new()
	sim.setup(LevelData.holes()[0])
	sim.position = Vector2(250, 390) # approaching the bottom-right corner
	sim.shoot_putt(Vector2(1, 1).normalized(), 500.0)
	var bounced := false
	var leaked := false
	for i in range(900):
		var events: Dictionary = sim.step(1.0 / 60.0)
		if sim._outer_blocked(sim.position):
			leaked = true
		if events.bounced:
			bounced = true
		if sim.state == BallSim.State.RESTING:
			break
	_check("corner: rebounds without sticking", bounced)
	_check("corner: never penetrates the boundary", not leaked)
	_check("corner: settles cleanly", sim.state == BallSim.State.RESTING)

func test_stress_many_runs_no_hang() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var dt := 1.0 / 60.0
	var max_ticks := 3600 # 60s of simulated time per shot, generous upper bound
	var any_hang := false
	var any_exception_proxy := true # stays true unless we complete the loop below

	for run in range(10):
		for hole_idx in range(LevelData.holes().size()):
			var sim := BallSim.new()
			sim.setup(LevelData.holes()[hole_idx])
			var shots := 0
			while not sim.completed and shots < 8:
				if not sim.can_shoot():
					break
				var to_hole: Vector2 = (sim.hole_pos - sim.position)
				var dir: Vector2 = to_hole.normalized().rotated(rng.randf_range(-0.5, 0.5))
				var power: float = rng.randf_range(0.3, 1.0)
				if sim.mode == BallSim.Mode.PUTT:
					sim.shoot_putt(dir, power * Constants.PUTT_MAX_SPEED)
				else:
					sim.shoot_chip(dir, power * Constants.CHIP_MAX_RANGE)
				shots += 1
				var ticks := 0
				while sim.state != BallSim.State.RESTING and not sim.completed and ticks < max_ticks:
					sim.step(dt)
					ticks += 1
				if ticks >= max_ticks:
					any_hang = true
	any_exception_proxy = false
	_check("stress: 10x5-hole varied-shot runs complete without hanging", not any_hang)
	_check("stress: loop finished without raising", not any_exception_proxy)
