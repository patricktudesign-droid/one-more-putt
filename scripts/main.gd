extends Control

## Root screen manager: swaps between a playing Hole and the hole-select /
## replay screen. No accounts, no network — everything lives in Save (local).

var holes: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = AppTheme.build()
	holes = LevelData.holes()
	show_hole(0)

func _clear() -> void:
	for c in get_children():
		c.queue_free()

func show_hole(index: int) -> void:
	_clear()
	var h := Control.new()
	h.set_script(load("res://scripts/hole.gd"))
	add_child(h)
	h.setup(index, holes[index])
	h.back_pressed.connect(func(): show_hole_select())
	h.retry_pressed.connect(func(): show_hole(index))
	h.choose_hole_pressed.connect(func(): show_hole_select())
	h.next_hole_pressed.connect(func(i: int):
		if i + 1 < holes.size():
			show_hole(i + 1)
		else:
			show_hole_select()
	)

func show_hole_select() -> void:
	_clear()
	var screen := Control.new()
	screen.set_script(load("res://scripts/hole_select.gd"))
	add_child(screen)
	screen.setup(holes)
	screen.hole_chosen.connect(func(i: int): show_hole(i))
