class_name ScreenArea
extends RefCounted
## "Area dello schermo", as in Windows 98's Display properties: the logical resolution
## of the desktop. The macOS window doesn't change size; fewer pixels make everything
## bigger, more pixels give more room. With the "expand" stretch aspect the desktop
## also takes the extra room of a window with another shape.

const PREF := "screen_area"
## The one in project.godot (window/size/viewport_*), used until the Manager picks another.
const DEFAULT := Vector2i(1280, 720)
const SIZES: Array[Vector2i] = [
	Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1152, 864), Vector2i(1280, 720),
	Vector2i(1280, 1024), Vector2i(1600, 900), Vector2i(1920, 1080),
]


## The saved choice; anything unknown falls back to DEFAULT.
static func current() -> Vector2i:
	var saved := parse(str(Save.get_ui(PREF, "")))
	return saved if saved in SIZES else DEFAULT


static func apply(window: Window, area: Vector2i) -> void:
	window.content_scale_size = area


## "1024x768" -> Vector2i(1024, 768); Vector2i.ZERO if it's not a size.
static func parse(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


static func format(area: Vector2i) -> String:
	return "%dx%d" % [area.x, area.y]


## Shown on screen, as Windows 98 wrote it.
static func label(area: Vector2i) -> String:
	return "%d per %d pixel" % [area.x, area.y]
