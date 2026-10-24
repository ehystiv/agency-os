@tool
class_name StyleBoxBevel
extends StyleBox
## '98-style bevelled border: black outline, light at the top left, shadow at the bottom right.
## SUNKEN swaps light and shadow. Optional solid offset drop shadow, without blur.

enum Kind { RAISED, SUNKEN }

@export var kind: Kind = Kind.RAISED:
	set(value):
		kind = value
		emit_changed()
@export var bg_color: Color = Color("c6c9d1"):
	set(value):
		bg_color = value
		emit_changed()
@export var light_color: Color = Color("f2f3f6"):
	set(value):
		light_color = value
		emit_changed()
@export var shadow_color: Color = Color("6a6f7e"):
	set(value):
		shadow_color = value
		emit_changed()
@export var draw_outline: bool = true:
	set(value):
		draw_outline = value
		emit_changed()
@export var outline_color: Color = Color.BLACK:
	set(value):
		outline_color = value
		emit_changed()
@export var drop_shadow_offset: Vector2 = Vector2.ZERO:
	set(value):
		drop_shadow_offset = value
		emit_changed()
@export var drop_shadow_color: Color = Color(0, 0, 0, 0.35):
	set(value):
		drop_shadow_color = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var rs := RenderingServer
	if drop_shadow_offset != Vector2.ZERO:
		rs.canvas_item_add_rect(to_canvas_item, Rect2(rect.position + drop_shadow_offset, rect.size), drop_shadow_color)
	var inner := rect
	if draw_outline:
		rs.canvas_item_add_rect(to_canvas_item, rect, outline_color)
		inner = rect.grow(-1.0)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	rs.canvas_item_add_rect(to_canvas_item, inner, bg_color)
	var top_left := light_color if kind == Kind.RAISED else shadow_color
	var bottom_right := shadow_color if kind == Kind.RAISED else light_color
	var p := inner.position
	var e := inner.end
	rs.canvas_item_add_rect(to_canvas_item, Rect2(p.x, e.y - 1.0, inner.size.x, 1.0), bottom_right)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(e.x - 1.0, p.y, 1.0, inner.size.y), bottom_right)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(p.x, p.y, inner.size.x - 1.0, 1.0), top_left)
	rs.canvas_item_add_rect(to_canvas_item, Rect2(p.x, p.y, 1.0, inner.size.y - 1.0), top_left)
