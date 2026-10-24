extends Control
## Foglio del Taccuino dietro al testo: carta color crema, margine rosso
## e righe blu alla stessa altezza delle righe di testo, che scorrono con lui.

const PAPER := Color("fbf8e8")
const MARGIN_LINE := Color(229 / 255.0, 38 / 255.0, 44 / 255.0, 0.45)
const RULE := Color(35 / 255.0, 64 / 255.0, 181 / 255.0, 0.18)
const MARGIN_X := 36.0

@export var text_edit: TextEdit


func _ready() -> void:
	text_edit.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: queue_redraw())
	text_edit.resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var line_height := float(text_edit.get_line_height())
	if line_height <= 0.0:
		return
	var top := text_edit.get_theme_stylebox("normal").get_margin(SIDE_TOP)
	var offset := fmod(text_edit.scroll_vertical, 1.0) * line_height
	var y := top + line_height - offset
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), RULE)
		y += line_height
	draw_line(Vector2(MARGIN_X, 0), Vector2(MARGIN_X, size.y), MARGIN_LINE)
