class_name AppTheme
extends RefCounted

## Minimal on-brand Theme (brief section 05 palette), built in code so no
## external .tres/font assets are required. Applied once to the root Control.

static func build() -> Theme:
	var theme := Theme.new()

	var forest := Color("173D32")
	var coral := Color("EF846C")
	var cream := Color("FAF5E9")
	var panel := Color("E7EDD9")

	var normal := StyleBoxFlat.new()
	normal.bg_color = panel
	normal.corner_radius_top_left = 12
	normal.corner_radius_top_right = 12
	normal.corner_radius_bottom_left = 12
	normal.corner_radius_bottom_right = 12
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6

	var hover := normal.duplicate()
	hover.bg_color = panel.lightened(0.08)

	var pressed := normal.duplicate()
	pressed.bg_color = coral
	pressed.content_margin_top = 7

	var disabled := normal.duplicate()
	disabled.bg_color = panel.darkened(0.03)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", forest)
	theme.set_color("font_hover_color", "Button", forest)
	theme.set_color("font_pressed_color", "Button", cream)
	theme.set_color("font_disabled_color", "Button", forest.lerp(panel, 0.5))
	theme.set_font_size("font_size", "Button", 16)

	theme.set_color("font_color", "Label", forest)

	return theme
