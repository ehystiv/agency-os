class_name ContainmentBoard
extends Control
## Hand-drawn Containment grid: raised cells, colored numbers,
## red triangles as flags and eyes for the Anomalies.

signal changed

const CELL := 22
const CHROME := Color("c6c9d1")
const LIGHT := Color("f2f3f6")
const SHADOW := Color("6a6f7e")
const OPENED := Color("b9bcc4")
const GRID := Color("8a8f9c")
const EXPLODED := Color("e5262c")
const RED := Color("e5262c")
const SCLERA := Color("cfeff4")
const IRIS := Color("7fe1ee")
const PUPIL := Color("02050a")
const NUMBER_COLORS: Array[Color] = [Color.BLACK, Color("2340b5"), Color("1f7a2e"), Color("c4161c"), Color("14245e"), Color("7a1418"), Color("1d7f8c"), Color("14161c"), Color("6a6f7e")]
const NUMBER_FONT := preload("res://ui/fonts/IBMPlexMono-Medium.ttf")

var field: Minefield
## True = left click places flags instead of digging.
var flag_mode := false


func set_field(new_field: Minefield) -> void:
	field = new_field
	custom_minimum_size = Vector2(field.width, field.height) * CELL
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or field == null:
		return
	var cell := Vector2i(click.position / CELL)
	if cell.x < 0 or cell.y < 0 or cell.x >= field.width or cell.y >= field.height:
		return
	var i := cell.y * field.width + cell.x
	accept_event()
	if field.is_opened(i):
		field.chord(i)
	elif click.button_index == MOUSE_BUTTON_RIGHT or (click.button_index == MOUSE_BUTTON_LEFT and flag_mode):
		field.toggle_flag(i)
	elif click.button_index == MOUSE_BUTTON_LEFT:
		field.open(i)
	queue_redraw()
	changed.emit()


func _draw() -> void:
	if field == null:
		return
	for i in field.cells():
		var rect := Rect2(Vector2(i % field.width, i / field.width) * CELL, Vector2(CELL, CELL))
		if field.is_opened(i):
			draw_rect(rect, EXPLODED if i == field.exploded else OPENED)
			draw_rect(rect, GRID, false, 1.0)
			if field.is_mined(i):
				_draw_eye(rect)
			else:
				var n := field.count(i)
				if n > 0:
					draw_string(NUMBER_FONT, rect.position + Vector2(0, 16), str(n), HORIZONTAL_ALIGNMENT_CENTER, CELL, 13, NUMBER_COLORS[n])
		else:
			_draw_raised(rect)
			if field.is_flagged(i):
				var c := rect.get_center()
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 5), c + Vector2(-6, 5)]), RED)


func _draw_raised(rect: Rect2) -> void:
	draw_rect(rect, CHROME)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), LIGHT)
	draw_rect(Rect2(rect.position, Vector2(2, rect.size.y)), LIGHT)
	draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 2), Vector2(rect.size.x, 2)), SHADOW)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - 2, 0), Vector2(2, rect.size.y)), SHADOW)


## The Anomaly: an open eye.
func _draw_eye(rect: Rect2) -> void:
	var c := rect.get_center()
	draw_set_transform(c, 0.0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, 8.0, SCLERA)
	draw_set_transform(Vector2.ZERO)
	draw_circle(c, 3.5, IRIS)
	draw_circle(c, 1.8, PUPIL)
