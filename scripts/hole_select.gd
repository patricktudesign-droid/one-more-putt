extends Control

## Replay selection screen: choose any hole, see best score / stars so far.
## Shown on Back, and offered at the end of hole five ("Prototype complete").

signal hole_chosen(index: int)

var holes: Array = []

func setup(lvls: Array) -> void:
	holes = lvls
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("FAF5E9")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var all_done: bool = true
	for i in range(holes.size()):
		if not Save.is_completed(i):
			all_done = false
			break

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(Constants.SCREEN_SIZE.x - 40, 0)
	col.position = Vector2(20, 40)
	col.add_theme_constant_override("separation", 14)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "ONE MORE PUTT"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("173D32"))
	col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Prototype complete — choose a hole to replay" if all_done else "Choose a hole"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("80634B"))
	col.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)

	for i in range(holes.size()):
		col.add_child(_build_row(i))

func _build_row(index: int) -> Control:
	var lvl: Dictionary = holes[index]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 60)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var best: int = Save.get_best(index)
	var best_text: String = "best %d" % best if best >= 0 else "not played"
	var stars_text: String = ""
	if best >= 0:
		var stars: int = 3 if best <= lvl.target else (2 if best == lvl.target + 1 else 1)
		stars_text = "  " + "★".repeat(stars)
	btn.text = "Hole %d — %s\nTarget %d · %s%s" % [index + 1, lvl.name, lvl.target, best_text, stars_text]
	btn.pressed.connect(func(): hole_chosen.emit(index))
	return btn
