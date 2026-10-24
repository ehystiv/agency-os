extends Control
## Banda verticale "AgencyOS 98" a sinistra del menu Start, letta dal basso verso l'alto.

const BG := Color("14245e")
const BRAND := Color.WHITE
const SUFFIX := Color("c9d3ff")
const FONT_SIZE := 22
const PADDING := 8.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font := get_theme_font("font", &"TitleLabel")
	var brand_width := font.get_string_size("Agency", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_set_transform(Vector2(size.x - 7.0, size.y - PADDING), -PI / 2.0)
	draw_string(font, Vector2.ZERO, "Agency", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, BRAND)
	draw_string(font, Vector2(brand_width, 0.0), "OS 98", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SUFFIX)
	draw_set_transform(Vector2.ZERO)
