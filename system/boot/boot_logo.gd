extends Control
## The Agency's red triangle with the AgencyOS 98 title, in the middle of the screen.

const RED := Color("e5262c")
const WHITE := Color("e8f6f8")
const TRIANGLE_SIZE := 120.0
const FONT_SIZE := 40


func _draw() -> void:
	var center := size / 2.0 - Vector2(0, 30)
	var half := TRIANGLE_SIZE / 2.0
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -half), center + Vector2(half, half * 0.8), center + Vector2(-half, half * 0.8)]), RED)
	var font := get_theme_font("font", &"TitleLabel")
	var text := "AgencyOS 98"
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(size.x / 2.0 - width / 2.0, center.y + half + 50), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, WHITE)
