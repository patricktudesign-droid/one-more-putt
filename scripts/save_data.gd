extends Node

## Local-only persistence: best strokes per hole, completed holes, sound
## preference and tutorial flags. No network, no accounts (brief section 06/07).

const SAVE_PATH := "user://savegame.cfg"
const SECTION := "progress"

var best_strokes: Dictionary = {}   # hole_index(int) -> int
var completed_holes: Dictionary = {} # hole_index(int) -> true
var sound_enabled: bool = true
var chip_tutorial_shown: bool = false

func _ready() -> void:
	load_data()

func load_data() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	best_strokes = cfg.get_value(SECTION, "best_strokes", {})
	completed_holes = cfg.get_value(SECTION, "completed_holes", {})
	sound_enabled = cfg.get_value(SECTION, "sound_enabled", true)
	chip_tutorial_shown = cfg.get_value(SECTION, "chip_tutorial_shown", false)

func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "best_strokes", best_strokes)
	cfg.set_value(SECTION, "completed_holes", completed_holes)
	cfg.set_value(SECTION, "sound_enabled", sound_enabled)
	cfg.set_value(SECTION, "chip_tutorial_shown", chip_tutorial_shown)
	cfg.save(SAVE_PATH)

## Records a completed hole's score. Completion is recorded once per attempt;
## replaying never worsens the stored best (brief section 06).
func record_completion(hole_index: int, strokes: int) -> void:
	completed_holes[hole_index] = true
	if not best_strokes.has(hole_index) or strokes < best_strokes[hole_index]:
		best_strokes[hole_index] = strokes
	save_data()

func get_best(hole_index: int) -> int:
	return best_strokes.get(hole_index, -1)

func is_completed(hole_index: int) -> bool:
	return completed_holes.get(hole_index, false)

func set_sound_enabled(value: bool) -> void:
	sound_enabled = value
	save_data()

func mark_chip_tutorial_shown() -> void:
	if chip_tutorial_shown:
		return
	chip_tutorial_shown = true
	save_data()
