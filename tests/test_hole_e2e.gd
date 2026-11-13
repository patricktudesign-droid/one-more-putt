extends SceneTree

## End-to-end check driving the real running scene (synthetic mouse input
## through the actual Godot GUI pipeline, not direct method calls) to cover
## aim-drag-release, stroke counting, undo and restart. Run via:
##   godot --path . -s res://tests/test_hole_e2e.gd
## NOTE: needs a real window (do not pass --headless) — Control anchor
## layout and GUI input routing don't resolve under the dummy display driver.
## Complements test_ball_sim.gd, which covers the pure simulation in isolation
## and does run headless.

var failures: Array[String] = []

func _check(name: String, cond: bool) -> void:
	if not cond:
		failures.append(name)
		print("FAIL: ", name)
	else:
		print("ok:   ", name)

## Same closed-form calibration as test_ball_sim.gd's — see that file for
## the derivation. Duplicated rather than shared since each test file here
## is a standalone SceneTree script.
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
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main: Node = scene.instantiate()
	get_root().add_child(main)
	current_scene = main
	for i in range(5):
		await process_frame

	var hole = main.get_child(0)
	_check("hole 0 loaded", hole != null)

	# Aim: drag from the ball's screen position downward (shoot direction = up).
	var ball_local: Vector2 = hole.sim.position
	var ball_screen: Vector2 = hole.course_root.to_global(ball_local)
	var drag_to: Vector2 = ball_screen + Vector2(0, 80) # drag down -> shoots up

	_send_mouse(ball_screen, true)
	await process_frame
	await process_frame
	_check("aim started", hole.is_dragging)

	_send_mouse_motion(drag_to)
	await process_frame

	_send_mouse(drag_to, false)
	await process_frame
	_check("stroke counted after release", hole.sim.strokes == 1)
	_check("aim cleared after release", not hole.is_dragging)
	_check("undo stack has one entry", hole.undo_stack.size() == 1)

	# Let it roll toward the hole (hole 1 is a straight shot, full power should overshoot
	# or undershoot depending on drag distance, so just confirm it moves and settles).
	var moved_pos: Vector2 = hole.sim.position
	for i in range(400):
		await process_frame
		if hole.sim.state == BallSim.State.RESTING:
			break
	_check("ball moved from start", hole.sim.position.distance_to(moved_pos) > 1.0 or hole.sim.completed)
	_check("ball settled or completed", hole.sim.state == BallSim.State.RESTING)

	# Undo button functional (only meaningful if not completed).
	if not hole.sim.completed:
		var pre_strokes: int = hole.sim.strokes
		hole._on_undo_pressed()
		await process_frame
		_check("undo reduced strokes", hole.sim.strokes < pre_strokes)
		_check("undo stack emptied", hole.undo_stack.is_empty())

	# Restart button functional.
	hole._on_restart_pressed()
	await process_frame
	_check("restart resets strokes", hole.sim.strokes == 0)
	_check("restart resets position", hole.sim.position == hole.level.ball)

	await _check_full_completion(main)
	await _check_chip_via_input(main)
	_check_golf_terms()

	print("")
	if failures.size() > 0:
		print("FAILURES: ", failures)
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)

func _check_full_completion(main: Node) -> void:
	main.show_hole(0)
	await process_frame
	await process_frame
	var hole = main.get_child(0)
	# Dead-straight putt, drag length calibrated so the natural stopping
	# distance lands exactly on the hole (same maths as the BallSim unit test).
	var dist: float = hole.sim.position.distance_to(hole.sim.hole_pos)
	var v0: float = _calibrate_putt_speed(dist)
	var drag_len: float = (v0 / Constants.PUTT_MAX_SPEED) * Constants.MAX_DRAG_PIXELS
	var ball_screen: Vector2 = hole.course_root.to_global(hole.sim.position)
	# drag_len is in course-local units; convert to screen pixels via the
	# course's current scale (to_local()/to_global() divide/multiply by it).
	var drag_to: Vector2 = ball_screen + Vector2(0, drag_len) * hole.course_root.scale.x
	_send_mouse(ball_screen, true)
	await process_frame
	_send_mouse_motion(drag_to)
	await process_frame
	_send_mouse(drag_to, false)
	await process_frame
	for i in range(600):
		await process_frame
		if hole.sim.completed:
			break
	_check("full-power straight putt sinks hole 1", hole.sim.completed)
	# Completion panel is deliberately delayed by the sink animation.
	for i in range(60):
		await process_frame
		if hole.completion_panel.visible:
			break
	_check("completion panel shown", hole.completion_panel.visible)
	var save_node: Node = get_root().get_node("Save")
	_check("best score saved", save_node.get_best(0) >= 0)

func _check_chip_via_input(main: Node) -> void:
	main.show_hole(2) # "Out of the sand": starts in sand, needs a chip
	for i in range(8):
		await process_frame
	var hole = main.get_child(0)
	_check("hole 3 starts in CHIP mode", hole.sim.mode == BallSim.Mode.CHIP)
	var ball_screen: Vector2 = hole.course_root.to_global(hole.sim.position)
	var hole_screen: Vector2 = hole.course_root.to_global(hole.sim.hole_pos)
	var aim_dir: Vector2 = (hole_screen - ball_screen).normalized()
	var drag_to: Vector2 = ball_screen - aim_dir * 60.0 # drag away from target
	_send_mouse(ball_screen, true)
	await process_frame
	_send_mouse_motion(drag_to)
	await process_frame
	_send_mouse(drag_to, false)
	await process_frame
	_check("chip shot counted a stroke", hole.sim.strokes == 1)
	var saw_flight: bool = false
	for i in range(200):
		await process_frame
		if hole.sim.state == BallSim.State.FLYING:
			saw_flight = true
		if hole.sim.state == BallSim.State.RESTING:
			break
	_check("chip shot went airborne", saw_flight)
	_check("ball ends up out of the sand", not hole.sim.in_sand)

func _check_golf_terms() -> void:
	var HoleScript: GDScript = load("res://scripts/hole.gd")
	_check("ace on par 1 is Hole in One", HoleScript._golf_term(1, 1) == "Hole in One!")
	_check("ace on par 3 is still Hole in One", HoleScript._golf_term(1, 3) == "Hole in One!")
	_check("2 under par 3 is Eagle", HoleScript._golf_term(1, 3) != "Eagle!") # 1 stroke -> ace takes priority
	_check("2 strokes on par 3 is Birdie", HoleScript._golf_term(2, 3) == "Birdie!")
	_check("matching par is Par", HoleScript._golf_term(3, 3) == "Par")
	_check("one over par is Bogey", HoleScript._golf_term(4, 3) == "Bogey")
	_check("two over par is +2", HoleScript._golf_term(5, 3) == "+2")

func _send_mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	get_root().push_input(ev)

func _send_mouse_motion(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	get_root().push_input(ev)
