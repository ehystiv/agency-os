class_name AppWindow
extends PanelContainer
## '98 frame for an app: draggable title bar, minimize and close.
## It doesn't know the other windows: asks the WindowManager for everything through signals.

signal focus_requested(window: AppWindow)
signal minimize_requested(window: AppWindow)
signal close_requested(window: AppWindow)
## Double click on the title bar: back to the default position.
signal reset_requested(window: AppWindow)
## End of a drag.
signal moved(window: AppWindow)
signal notification_requested(title: String, text: String, action: Dictionary)
signal app_requested(id: StringName, args: Dictionary)
signal command_requested(command: StringName)

## How much of the window must stay inside the desktop horizontally.
const KEEP_VISIBLE := 140.0

var app: AppInfo
var content: AppContent
var active: bool = false:
	set(value):
		active = value
		if content != null:
			content.window_active = value
		if is_node_ready():
			_title_bar.theme_type_variation = &"TitleBarActive" if value else &"TitleBarInactive"

var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var _title_bar: PanelContainer = %TitleBar
@onready var _title: Label = %Title
@onready var _menu_strip: MarginContainer = %MenuStrip
@onready var _menu_items: HBoxContainer = %MenuItems
@onready var _content_slot: MarginContainer = %Content


func _ready() -> void:
	%MinButton.pressed.connect(func() -> void: minimize_requested.emit(self))
	%CloseButton.pressed.connect(func() -> void: close_requested.emit(self))
	_title_bar.gui_input.connect(_on_title_bar_input)
	# Windows aren't resized by hand: they always follow their content,
	# even when it shrinks (e.g. wrapped text finally finding its width).
	minimum_size_changed.connect(reset_size)
	active = active


## Call after the window has entered the tree.
func setup(info: AppInfo, app_content: AppContent) -> void:
	app = info
	content = app_content
	name = String(info.id)
	_title.text = info.window_title if info.window_title != "" else info.label
	custom_minimum_size = Vector2(info.default_size)
	_build_menu_strip(info.menu_strip)
	content.app = info
	content.title_changed.connect(func(text: String) -> void: _title.text = text)
	content.notification_requested.connect(notification_requested.emit)
	content.app_requested.connect(app_requested.emit)
	content.close_requested.connect(func() -> void: close_requested.emit(self))
	content.command_requested.connect(command_requested.emit)
	_content_slot.add_child(content)
	reset_size()


## Keeps the title bar reachable inside the desktop.
func clamp_position(pos: Vector2) -> Vector2:
	var area := get_parent_control().size
	return Vector2(
		clampf(pos.x, -(size.x - KEEP_VISIBLE), area.x - KEEP_VISIBLE),
		clampf(pos.y, 0.0, maxf(0.0, area.y - _title_bar.size.y - 8.0))
	).round()


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


func _on_title_bar_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			_dragging = false
			reset_requested.emit(self)
		elif click.pressed:
			_dragging = true
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
