extends Control

## One playable hole: course view, aim input, stroke/undo/restart, HUD and
## the completion panel. Built entirely from code-created nodes (no .tscn)
## so levels stay purely data-driven per brief section 02/07.

signal back_pressed
signal next_hole_pressed(hole_index: int)
signal retry_pressed
signal hole_completed(hole_index: int, strokes: int)
signal choose_hole_pressed

const HEADER_HEIGHT := 64.0
const BOTTOM_HEIGHT := 92.0
const SIDE_PAD := 10.0

var hole_index: int = 0
var level: Dictionary = {}
var sim: BallSim

var course_root: Node2D
var course_view: Node2D

var header_hole_label: Label
var header_target_label: Label
var sound_button: Button
var undo_button: Button
var restart_button: Button
var stroke_label: Label
var shot_label: Label
var mode_banner: Label
var toast_label: Label
var toast_timer: Timer

var completion_panel: Control
var completion_title: Label
var completion_strokes: Label
var completion_term: Label
var completion_stars: Label

var undo_stack: Array = []
var is_dragging: bool = false
var drag_pointer_index: int = -1
var aim_start_local: Vector2
var aim_ball_pos: Vector2
var aim_mode: int = BallSim.Mode.PUTT

var _was_showing_banner: bool = false
var _banner_text: String = ""

func setup(index: int, lvl: Dictionary) -> void:
	hole_index = index
	level = lvl
	sim = BallSim.new()
	sim.setup(level)
	_build_ui()
	_layout_course()
	course_view.set_level(level)
	course_view.set_sim(sim)
	_refresh_hud()

func _ready() -> void:
	resized.connect(_layout_course)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_aim()

# --- UI construction -----------------------------------------------------

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = Color("FAF5E9")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Course
	course_root = Node2D.new()
	add_child(course_root)
	course_view = Node2D.new()
	course_view.set_script(load("res://scripts/course_view.gd"))
	course_root.add_child(course_view)

	# Header
	var header := Control.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	header.offset_bottom = HEADER_HEIGHT
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)

	var back_btn := Button.new()
	back_btn.text = "<"
	back_btn.custom_minimum_size = Vector2(Constants.MIN_TOUCH_TARGET, Constants.MIN_TOUCH_TARGET)
	back_btn.position = Vector2(8, (HEADER_HEIGHT - Constants.MIN_TOUCH_TARGET) * 0.5)
	back_btn.pressed.connect(func(): back_pressed.emit())
	header.add_child(back_btn)

	header_hole_label = Label.new()
	header_hole_label.add_theme_font_size_override("font_size", 18)
	header_hole_label.add_theme_color_override("font_color", Color("173D32"))
	header_hole_label.position = Vector2(62, 10)
	header.add_child(header_hole_label)

	header_target_label = Label.new()
	header_target_label.add_theme_font_size_override("font_size", 13)
	header_target_label.add_theme_color_override("font_color", Color("80634B"))
	header_target_label.position = Vector2(62, 34)
	header.add_child(header_target_label)

	sound_button = Button.new()
	sound_button.custom_minimum_size = Vector2(Constants.MIN_TOUCH_TARGET, Constants.MIN_TOUCH_TARGET)
	sound_button.position = Vector2(Constants.SCREEN_SIZE.x - Constants.MIN_TOUCH_TARGET - 8, (HEADER_HEIGHT - Constants.MIN_TOUCH_TARGET) * 0.5)
	sound_button.pressed.connect(_on_sound_pressed)
	header.add_child(sound_button)
	_refresh_sound_button()

	# Mode banner (over course, top)
	mode_banner = Label.new()
	mode_banner.add_theme_font_size_override("font_size", 14)
	mode_banner.add_theme_color_override("font_color", Color("173D32"))
	mode_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mode_banner.offset_top = HEADER_HEIGHT + 4
	mode_banner.offset_bottom = HEADER_HEIGHT + 24
	mode_banner.visible = false
	mode_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mode_banner)

	# Toast (blocked landing, etc.)
	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 14)
	toast_label.add_theme_color_override("font_color", Color("EF846C"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_top = HEADER_HEIGHT + 22
	toast_label.offset_bottom = HEADER_HEIGHT + 42
	toast_label.visible = false
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_label)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 1.6
	toast_timer.timeout.connect(func(): toast_label.visible = false)
	add_child(toast_timer)

	# Bottom bar
	var bottom := Control.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.custom_minimum_size = Vector2(0, BOTTOM_HEIGHT)
	bottom.offset_top = -BOTTOM_HEIGHT
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)

	shot_label = Label.new()
	shot_label.add_theme_font_size_override("font_size", 13)
	shot_label.add_theme_color_override("font_color", Color("80634B"))
	shot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shot_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shot_label.offset_bottom = 16
	bottom.add_child(shot_label)

	undo_button = Button.new()
	undo_button.text = "Undo"
	undo_button.custom_minimum_size = Vector2(88, Constants.MIN_TOUCH_TARGET)
	undo_button.position = Vector2(12, BOTTOM_HEIGHT - Constants.MIN_TOUCH_TARGET - 8)
	undo_button.pressed.connect(_on_undo_pressed)
	bottom.add_child(undo_button)

	stroke_label = Label.new()
	stroke_label.add_theme_font_size_override("font_size", 16)
	stroke_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stroke_label.size = Vector2(160, Constants.MIN_TOUCH_TARGET)
	stroke_label.position = Vector2((Constants.SCREEN_SIZE.x - 160) * 0.5, BOTTOM_HEIGHT - Constants.MIN_TOUCH_TARGET - 8)
	bottom.add_child(stroke_label)

	restart_button = Button.new()
	restart_button.text = "Restart"
	restart_button.custom_minimum_size = Vector2(88, Constants.MIN_TOUCH_TARGET)
	restart_button.position = Vector2(Constants.SCREEN_SIZE.x - 88 - 12, BOTTOM_HEIGHT - Constants.MIN_TOUCH_TARGET - 8)
	restart_button.pressed.connect(_on_restart_pressed)
	bottom.add_child(restart_button)

	_build_completion_panel()

func _build_completion_panel() -> void:
	completion_panel = ColorRect.new()
	completion_panel.color = Color(0.09, 0.24, 0.2, 0.92)
	completion_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	completion_panel.visible = false
	completion_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(completion_panel)

	var card := VBoxContainer.new()
	card.position = Vector2(Constants.SCREEN_SIZE.x * 0.5 - 140, Constants.SCREEN_SIZE.y * 0.5 - 150)
	card.custom_minimum_size = Vector2(280, 300)
	card.add_theme_constant_override("separation", 10)
	completion_panel.add_child(card)

	completion_title = Label.new()
	completion_title.add_theme_font_size_override("font_size", 26)
	completion_title.add_theme_color_override("font_color", Color("FAF5E9"))
	completion_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_title.custom_minimum_size = Vector2(280, 0)
	card.add_child(completion_title)

	completion_strokes = Label.new()
	completion_strokes.add_theme_font_size_override("font_size", 16)
	completion_strokes.add_theme_color_override("font_color", Color("FAF5E9"))
	completion_strokes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_strokes.custom_minimum_size = Vector2(280, 0)
	card.add_child(completion_strokes)

	completion_term = Label.new()
	completion_term.add_theme_font_size_override("font_size", 20)
	completion_term.add_theme_color_override("font_color", Color("EF846C"))
	completion_term.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_term.custom_minimum_size = Vector2(280, 0)
	card.add_child(completion_term)

	completion_stars = Label.new()
	completion_stars.add_theme_font_size_override("font_size", 30)
	completion_stars.add_theme_color_override("font_color", Color("EF846C"))
	completion_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	completion_stars.custom_minimum_size = Vector2(280, 0)
	card.add_child(completion_stars)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	card.add_child(spacer)

	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	retry_btn.custom_minimum_size = Vector2(280, Constants.MIN_TOUCH_TARGET)
	retry_btn.pressed.connect(func():
		completion_panel.visible = false
		retry_pressed.emit()
	)
	card.add_child(retry_btn)

	var next_btn := Button.new()
	next_btn.name = "NextButton"
	next_btn.text = "Next hole"
	next_btn.custom_minimum_size = Vector2(280, Constants.MIN_TOUCH_TARGET)
	next_btn.pressed.connect(func():
		completion_panel.visible = false
		next_hole_pressed.emit(hole_index)
	)
	card.add_child(next_btn)

	var choose_btn := Button.new()
	choose_btn.name = "ChooseButton"
	choose_btn.text = "Choose a hole"
	choose_btn.visible = false
	choose_btn.custom_minimum_size = Vector2(280, Constants.MIN_TOUCH_TARGET)
	choose_btn.pressed.connect(func():
		completion_panel.visible = false
		choose_hole_pressed.emit()
	)
	card.add_child(choose_btn)

func _layout_course() -> void:
	if course_root == null:
		return
	var avail_w: float = size.x - SIDE_PAD * 2.0
	var avail_h: float = size.y - HEADER_HEIGHT - BOTTOM_HEIGHT - SIDE_PAD * 2.0
	if avail_w <= 0 or avail_h <= 0:
		return
	var s: float = min(avail_w / Constants.COURSE_SIZE.x, avail_h / Constants.COURSE_SIZE.y)
	var course_px: Vector2 = Constants.COURSE_SIZE * s
	var off_x: float = (size.x - course_px.x) * 0.5
	var off_y: float = HEADER_HEIGHT + SIDE_PAD + (avail_h - course_px.y) * 0.5
	course_root.position = Vector2(off_x, off_y)
	course_root.scale = Vector2(s, s)

# --- HUD refresh -----------------------------------------------------------

func _refresh_hud() -> void:
	header_hole_label.text = "Hole %d — %s" % [hole_index + 1, level.name]
	header_target_label.text = "Target %d shot%s" % [level.target, "" if level.target == 1 else "s"]
	stroke_label.text = "Strokes: %d" % sim.strokes
	undo_button.disabled = undo_stack.is_empty() or sim.state != BallSim.State.RESTING or sim.completed
	restart_button.disabled = false
	if sim.state == BallSim.State.RESTING and not sim.completed and not is_dragging:
		shot_label.text = "" # shown only while actively aiming, per spec
	_update_mode_banner()

func _update_mode_banner() -> void:
	var showing: bool = sim.state == BallSim.State.RESTING and not sim.completed and sim.mode == BallSim.Mode.CHIP
	if showing and not _was_showing_banner:
		if not Save.chip_tutorial_shown:
			_banner_text = "CHIP — sand shots chip automatically onto the green"
			Save.mark_chip_tutorial_shown()
		else:
			_banner_text = "CHIP"
	_was_showing_banner = showing
	mode_banner.visible = showing
	if showing:
		mode_banner.text = _banner_text

func _refresh_sound_button() -> void:
	sound_button.text = "♪" if Save.sound_enabled else "✕"

func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_timer.start()

# --- Physics / sim stepping -------------------------------------------------

func _physics_process(delta: float) -> void:
	if not sim or sim.completed:
		_refresh_hud()
		return
	var events: Dictionary = sim.step(delta)
	if events.bounced:
		Sound.play_wall()
	if events.entered_sand:
		Sound.play_sand()
	if events.blocked_landing:
		_handle_blocked_landing()
	if events.hole_complete:
		_handle_hole_complete()
	_refresh_hud()

func _handle_blocked_landing() -> void:
	if not undo_stack.is_empty():
		var pre: Dictionary = undo_stack[undo_stack.size() - 1]
		var restored: Dictionary = pre.duplicate(true)
		restored.strokes = sim.strokes
		restored.completed = false
		sim.restore(restored)
	_show_toast("Blocked landing")
	Sound.play_wall()

func _handle_hole_complete() -> void:
	if sim.strokes == 1:
		Sound.play_hole_in_one()
	else:
		Sound.play_cup()
	Save.record_completion(hole_index, sim.strokes)
	var stars: int = _stars_for(sim.strokes, level.target)
	var is_last: bool = hole_index == LevelData.holes().size() - 1
	completion_title.text = "Prototype complete" if is_last else "Hole complete"
	completion_strokes.text = "%d stroke%s (par %d)" % [sim.strokes, "" if sim.strokes == 1 else "s", level.target]
	completion_term.text = _golf_term(sim.strokes, level.target)
	completion_stars.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	var next_btn: Button = completion_panel.find_child("NextButton", true, false)
	if next_btn:
		next_btn.visible = not is_last
	var choose_btn: Button = completion_panel.find_child("ChooseButton", true, false)
	if choose_btn:
		choose_btn.visible = is_last
	completion_panel.visible = true
	hole_completed.emit(hole_index, sim.strokes)

static func _stars_for(strokes: int, target: int) -> int:
	if strokes <= target:
		return 3
	elif strokes == target + 1:
		return 2
	else:
		return 1

## Standard golf scoring terms relative to par (the hole's target stroke
## count), per playtest feedback asking for par/birdie/eagle/hole-in-one.
static func _golf_term(strokes: int, par: int) -> String:
	if strokes == 1:
		return "Hole in One!"
	var diff: int = strokes - par
	if diff <= -2:
		return "Eagle!"
	elif diff == -1:
		return "Birdie!"
	elif diff == 0:
		return "Par"
	elif diff == 1:
		return "Bogey"
	else:
		return "+%d" % diff

# --- Input / aiming ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if sim == null or sim.completed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down(event.position)
		else:
			_pointer_up(event.position)
	elif event is InputEventMouseMotion and is_dragging:
		_pointer_move(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pointer_down(event.position)
		else:
			_pointer_up(event.position)
	elif event is InputEventScreenDrag and is_dragging:
		_pointer_move(event.position)

func _pointer_down(global_pos: Vector2) -> void:
	if is_dragging or not sim.can_shoot():
		return
	var local: Vector2 = course_root.to_local(global_pos)
	if local.distance_to(sim.position) > Constants.AIM_TOUCH_RADIUS:
		return
	is_dragging = true
	aim_start_local = local
	aim_ball_pos = sim.position
	aim_mode = sim.mode
	shot_label.text = "PUTT" if aim_mode == BallSim.Mode.PUTT else "CHIP"
	_update_preview(local)

func _pointer_move(global_pos: Vector2) -> void:
	if not is_dragging:
		return
	var local: Vector2 = course_root.to_local(global_pos)
	_update_preview(local)

func _pointer_up(global_pos: Vector2) -> void:
	if not is_dragging:
		return
	var local: Vector2 = course_root.to_local(global_pos)
	var drag_vec: Vector2 = local - aim_start_local
	is_dragging = false
	course_view.set_preview({"active": false})
	shot_label.text = ""

	if drag_vec.length() < Constants.CANCEL_DRAG_PIXELS:
		return # cancelled gesture, no stroke

	var direction: Vector2 = -drag_vec.normalized()
	var power_t: float = clamp(drag_vec.length() / Constants.MAX_DRAG_PIXELS, 0.0, 1.0)

	undo_stack.append(sim.snapshot())
	if aim_mode == BallSim.Mode.PUTT:
		sim.shoot_putt(direction, power_t * Constants.PUTT_MAX_SPEED)
		Sound.play_putt()
	else:
		sim.shoot_chip(direction, power_t * Constants.CHIP_MAX_RANGE)
		Sound.play_chip()
	_refresh_hud()

func _cancel_aim() -> void:
	if is_dragging:
		is_dragging = false
		course_view.set_preview({"active": false})
		shot_label.text = ""

func _update_preview(local: Vector2) -> void:
	var drag_vec: Vector2 = local - aim_start_local
	if drag_vec.length() < Constants.CANCEL_DRAG_PIXELS:
		course_view.set_preview({"active": false})
		return
	var direction: Vector2 = -drag_vec.normalized()
	var power_t: float = clamp(drag_vec.length() / Constants.MAX_DRAG_PIXELS, 0.0, 1.0)
	var preview := {
		"active": true,
		"mode": aim_mode,
		"ball_pos": aim_ball_pos,
		"direction": direction,
		"power_t": power_t,
	}
	if aim_mode == BallSim.Mode.CHIP:
		var distance: float = power_t * Constants.CHIP_MAX_RANGE
		var target: Vector2 = aim_ball_pos + direction * distance
		preview.target = target
		preview.valid = sim.is_chip_target_valid(target)
	else:
		var speed: float = power_t * Constants.PUTT_MAX_SPEED
		preview.trajectory = _simulate_putt_trajectory(direction, speed)
	course_view.set_preview(preview)

## Predicts where a putt of this direction/speed will actually travel —
## including wall bounces and the hole-rim lip-out — by running a throwaway
## scratch simulation through the exact same physics as the real shot.
## Playtest feedback: "when you're aiming off a wall, I want to see what the
## potential trajectory is."
func _simulate_putt_trajectory(direction: Vector2, speed: float) -> PackedVector2Array:
	var scratch := BallSim.new()
	scratch.setup(level)
	scratch.position = aim_ball_pos
	scratch.in_sand = sim.in_sand
	scratch.velocity = direction.normalized() * speed
	scratch.state = BallSim.State.ROLLING
	var points := PackedVector2Array()
	var dt := 1.0 / 60.0
	var max_ticks := 240 # generous bound (4s simulated), prevents a hang
	var sample_every := 3
	for i in range(max_ticks):
		scratch.step(dt)
		if i % sample_every == 0:
			points.append(scratch.position)
		if scratch.state != BallSim.State.ROLLING or scratch.completed:
			break
	return points

# --- Button handlers ---------------------------------------------------------

func _on_undo_pressed() -> void:
	if undo_stack.is_empty() or sim.state != BallSim.State.RESTING or sim.completed:
		return
	var snap: Dictionary = undo_stack.pop_back()
	sim.restore(snap)
	_refresh_hud()

func _on_restart_pressed() -> void:
	sim.reset()
	undo_stack.clear()
	completion_panel.visible = false
	_cancel_aim()
	_refresh_hud()

func _on_sound_pressed() -> void:
	Save.set_sound_enabled(not Save.sound_enabled)
	_refresh_sound_button()
