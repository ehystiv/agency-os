@tool
class_name StyleBoxGradient
extends StyleBox
## Horizontal two-colour gradient, like Windows 98 title bars.

@export var from_color: Color = Color("2340b5"):
	set(value):
		from_color = value
		emit_changed()
@export var to_color: Color = Color("5c8ddc"):
	set(value):
		to_color = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var points := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var colors := PackedColorArray([from_color, to_color, to_color, from_color])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, colors)
