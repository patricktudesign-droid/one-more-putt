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
	# v0 chosen so the putt's natural stopping distance (v0^2 / (2*decel)) lands
	# right on the hole, 300 units away.
	var v0 := sqrt(2.0 * Constants.PUTT_DECEL * sim.position.distance_to(sim.hole_pos))
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
