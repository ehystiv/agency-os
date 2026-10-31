extends Control
## The small ▸ of a Start menu item that opens a folder, in the item's text color.

const DARK := Color("14161c")


func _ready() -> void:
	var button := get_parent() as Button
	button.mouse_entered.connect(queue_redraw)
	button.mouse_exited.connect(queue_redraw)
	button.toggled.connect(func(_on: bool) -> void: queue_redraw())


func _draw() -> void:
	var button := get_parent() as Button
	var lit := button.is_hovered() or button.button_pressed
	var c := size / 2.0
	draw_colored_polygon(PackedVector2Array([c + Vector2(-2, -4), c + Vector2(2, 0), c + Vector2(-2, 4)]), Color.WHITE if lit else DARK)
