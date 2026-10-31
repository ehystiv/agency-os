class_name AppWindow
extends PanelContainer
## '98 frame for an app: draggable title bar, minimize and close.
## Resizable apps (AppInfo.resizable) also have edges and corners to drag and a maximize button.
## It doesn't know the other windows: asks the WindowManager for everything through signals.

signal focus_requested(window: AppWindow)
signal minimize_requested(window: AppWindow)
signal close_requested(window: AppWindow)
## Double click on the title bar of a fixed window: back to the default position.
signal reset_requested(window: AppWindow)
## End of a drag, of a resize, or maximize/restore: the geometry is worth saving.
signal moved(window: AppWindow)
signal notification_requested(title: String, text: String, action: Dictionary)
signal app_requested(id: StringName, args: Dictionary)
signal command_requested(command: StringName)

## How much of the window must stay inside the desktop horizontally.
const KEEP_VISIBLE := 140.0
## Along an edge, this close to a corner the drag resizes both sides.
const CORNER := 16.0
const MAXIMIZE_ICON := preload("res://ui/icons/win_max.svg")
const RESTORE_ICON := preload("res://ui/icons/win_restore.svg")

enum Edge { LEFT = 1, RIGHT = 2, TOP = 4, BOTTOM = 8 }

var app: AppInfo
var content: AppContent
var active: bool = false:
	set(value):
		active = value
		if content != null:
			content.window_active = value
		if is_node_ready():
			_title_bar.theme_type_variation = &"TitleBarActive" if value else &"TitleBarInactive"
var maximized: bool = false

var _dragging := false
var _drag_offset := Vector2.ZERO
## Size chosen by hand (resizable windows only); the content's minimum still wins.
var _wanted_size := Vector2.ZERO
## Position and size to go back to when un-maximizing.
var _restore_rect := Rect2()
## Edges being dragged (Edge flags), 0 when not resizing.
var _resize_edges := 0
var _resize_from_mouse := Vector2.ZERO
var _resize_from_rect := Rect2()

@onready var _title_bar: PanelContainer = %TitleBar
@onready var _title: Label = %Title
@onready var _max_button: Button = %MaxButton
@onready var _menu_strip: MarginContainer = %MenuStrip
@onready var _menu_items: HBoxContainer = %MenuItems
@onready var _content_slot: MarginContainer = %Content


func _ready() -> void:
	%MinButton.pressed.connect(func() -> void: minimize_requested.emit(self))
	%CloseButton.pressed.connect(func() -> void: close_requested.emit(self))
	_max_button.pressed.connect(toggle_maximized)
	_title_bar.gui_input.connect(_on_title_bar_input)
	# Fixed windows always follow their content, even when it shrinks (e.g. wrapped text
	# finally finding its width); resizable ones keep their size unless the content needs more.
	minimum_size_changed.connect(_fit_size)
	active = active


## Call after the window has entered the tree.
func setup(info: AppInfo, app_content: AppContent) -> void:
	app = info
	content = app_content
	name = String(info.id)
	_title.text = info.window_title if info.window_title != "" else info.label
	_build_menu_strip(info.menu_strip)
	content.app = info
	content.title_changed.connect(func(text: String) -> void: _title.text = text)
	content.notification_requested.connect(notification_requested.emit)
	content.app_requested.connect(app_requested.emit)
	content.close_requested.connect(func() -> void: close_requested.emit(self))
	content.command_requested.connect(command_requested.emit)
	_content_slot.add_child(content)
	if info.resizable:
		_max_button.show()
		_wanted_size = Vector2(info.default_size)
	else:
		custom_minimum_size = Vector2(info.default_size)
	_fit_size()


## The size the Manager gave the window, to save; ZERO for fixed windows.
func wanted_size() -> Vector2:
	return _restore_rect.size if maximized else _wanted_size


## The position to save: for a maximized window, the one it goes back to.
func restored_position() -> Vector2:
	return _restore_rect.position if maximized else position


## Restores a saved size (resizable windows only).
func set_wanted_size(value: Vector2) -> void:
	if not app.resizable or value == Vector2.ZERO:
		return
	if maximized:
		_restore_rect.size = value
	else:
		_wanted_size = value
		_fit_size()


## Back to the first size and out of maximized (Arrange windows).
func reset_size_to_default() -> void:
	if not app.resizable:
		return
	maximized = false
	_update_max_button()
	_wanted_size = Vector2(app.default_size)
	_fit_size()


func toggle_maximized() -> void:
	set_maximized(not maximized)
	moved.emit(self)


func set_maximized(value: bool) -> void:
	if not app.resizable or value == maximized:
		return
	maximized = value
	if maximized:
		_restore_rect = Rect2(position, _wanted_size)
		position = Vector2.ZERO
	else:
		_wanted_size = _restore_rect.size
		position = clamp_position(_restore_rect.position)
	_update_max_button()
	_fit_size()


## Called by the WindowManager when the desktop changes size (screen area, fullscreen).
func fit_to_desktop() -> void:
	_fit_size()
	position = clamp_position(position)


## Keeps the title bar reachable inside the desktop.
func clamp_position(pos: Vector2) -> Vector2:
	if maximized:
		return Vector2.ZERO
	var area := _desktop_size()
	return Vector2(
		clampf(pos.x, -(size.x - KEEP_VISIBLE), area.x - KEEP_VISIBLE),
		clampf(pos.y, 0.0, maxf(0.0, area.y - _title_bar.size.y - 8.0))
	).round()


func _fit_size() -> void:
	if app == null or not app.resizable:
		reset_size()
		return
	var minimum := _minimum()
	if maximized:
		size = _desktop_size().max(minimum)
		return
	# Never bigger than the desktop, never smaller than what the content needs.
	var area := _desktop_size()
	var fitted := _wanted_size.min(area) if area != Vector2.ZERO else _wanted_size
	size = fitted.max(minimum).round()


func _minimum() -> Vector2:
	return get_combined_minimum_size().max(Vector2(app.min_size))


func _desktop_size() -> Vector2:
	var parent := get_parent_control()
	return parent.size if parent != null else Vector2.ZERO


func _update_max_button() -> void:
	_max_button.icon = RESTORE_ICON if maximized else MAXIMIZE_ICON
	_max_button.tooltip_text = "Ripristina" if maximized else "Ingrandisci"


func _input(event: InputEvent) -> void:
	# A click anywhere inside the window brings it to the front, without consuming the event.
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or not is_visible_in_tree():
		return
	# The wheel scrolls whatever is under the mouse without raising its window.
	if not click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and (hovered == self or is_ancestor_of(hovered)):
		focus_requested.emit(self)


## Only the frame's border reaches here: the content covers the rest.
func _gui_input(event: InputEvent) -> void:
	if app == null or not app.resizable or maximized:
		return
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.pressed:
			_resize_edges = _edges_at(click.position)
			_resize_from_mouse = click.global_position
			_resize_from_rect = Rect2(position, size)
		elif _resize_edges != 0:
			_resize_edges = 0
			moved.emit(self)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _resize_edges != 0:
			_resize_to(motion.global_position - _resize_from_mouse)
		else:
			mouse_default_cursor_shape = _cursor_for(_edges_at(motion.position))


## Which edges a point of the frame belongs to (Edge flags).
func _edges_at(point: Vector2) -> int:
	var frame := get_theme_stylebox(&"panel")
	var margin := Vector2(frame.content_margin_left, frame.content_margin_top) if frame != null else Vector2(4, 4)
	var edges := 0
	if point.x <= margin.x + 1.0:
		edges |= Edge.LEFT
	elif point.x >= size.x - margin.x - 1.0:
		edges |= Edge.RIGHT
	if point.y <= margin.y + 1.0:
		edges |= Edge.TOP
	elif point.y >= size.y - margin.y - 1.0:
		edges |= Edge.BOTTOM
	# Near a corner, a side edge drags both sides.
	if edges in [Edge.LEFT, Edge.RIGHT]:
		if point.y <= CORNER:
			edges |= Edge.TOP
		elif point.y >= size.y - CORNER:
			edges |= Edge.BOTTOM
	elif edges in [Edge.TOP, Edge.BOTTOM]:
		if point.x <= CORNER:
			edges |= Edge.LEFT
		elif point.x >= size.x - CORNER:
			edges |= Edge.RIGHT
	return edges


static func _cursor_for(edges: int) -> CursorShape:
	match edges:
		Edge.LEFT, Edge.RIGHT:
			return CURSOR_HSIZE
		Edge.TOP, Edge.BOTTOM:
			return CURSOR_VSIZE
		Edge.LEFT | Edge.TOP, Edge.RIGHT | Edge.BOTTOM:
			return CURSOR_FDIAGSIZE
		Edge.RIGHT | Edge.TOP, Edge.LEFT | Edge.BOTTOM:
			return CURSOR_BDIAGSIZE
	return CURSOR_ARROW


## Moves the dragged edges by delta, keeping the minimum size and the desktop's bounds.
func _resize_to(delta: Vector2) -> void:
	var minimum := _minimum()
	var area := _desktop_size()
	var rect := _resize_from_rect
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	if _resize_edges & Edge.LEFT:
		left = clampf(left + delta.x, minf(0.0, right - minimum.x), right - minimum.x)
	if _resize_edges & Edge.RIGHT:
		right = clampf(right + delta.x, left + minimum.x, maxf(area.x, left + minimum.x))
	if _resize_edges & Edge.TOP:
		top = clampf(top + delta.y, 0.0, maxf(0.0, bottom - minimum.y))
	if _resize_edges & Edge.BOTTOM:
		bottom = clampf(bottom + delta.y, top + minimum.y, maxf(area.y, top + minimum.y))
	position = Vector2(left, top).round()
	_wanted_size = Vector2(right - left, bottom - top).round()
	_fit_size()


func _on_title_bar_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			_dragging = false
			if app.resizable:
				toggle_maximized()
			else:
				reset_requested.emit(self)
		elif click.pressed:
			# A maximized window stays where it is, as in Windows 98.
			_dragging = not maximized
			_drag_offset = get_local_mouse_position()
		elif _dragging:
			_dragging = false
			moved.emit(self)
		return
	if event is InputEventMouseMotion and _dragging:
		position = clamp_position(get_parent_control().get_local_mouse_position() - _drag_offset)


func _build_menu_strip(items: PackedStringArray) -> void:
	_menu_strip.visible = not items.is_empty()
	for item in items:
		var entry := RichTextLabel.new()
		entry.bbcode_enabled = true
		entry.fit_content = true
		entry.autowrap_mode = TextServer.AUTOWRAP_OFF
		entry.scroll_active = false
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.text = "[u]%s[/u]%s" % [item.left(1), item.substr(1)]
		_menu_items.add_child(entry)
