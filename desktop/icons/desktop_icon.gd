class_name DesktopIcon
extends VBoxContainer
## Desktop icon: click selects, double click or Enter opens, dragging moves it.

signal selected(icon: DesktopIcon)
signal activated(icon: DesktopIcon)
## End of a drag: the grid decides the cell.
signal dropped(icon: DesktopIcon)

const DRAG_THRESHOLD := 5.0
const BLINK_SECONDS := 0.8

var key: String
var is_selected: bool = false:
	set(value):
		is_selected = value
		_caption.theme_type_variation = &"IconLabelSelected" if value else &"IconLabel"

var _pressing := false
var _dragging := false
var _press_at := Vector2.ZERO
var _start_position := Vector2.ZERO
var _blink: Tween
var _badge: Label

@onready var _picture: TextureRect = $Picture
@onready var _caption: Label = $Caption


func setup(icon_key: String, label: String, texture: Texture2D) -> void:
	key = icon_key
	_caption.text = label
	_picture.texture = texture
	tooltip_text = label
	reset_size()


func set_texture(texture: Texture2D) -> void:
	_picture.texture = texture


## Red counter at the top right (e.g. unread memos); 0 hides it.
func set_badge(count: int) -> void:
	if _badge == null:
		_badge = Label.new()
		_badge.theme_type_variation = &"IconBadge"
		_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_picture.add_child(_badge)
	_badge.visible = count > 0
	_badge.text = str(count)
	_badge.reset_size()
	_badge.position = Vector2(_picture.custom_minimum_size.x - _badge.size.x / 2.0, -4.0)


## A file not opened yet blinks in steps, as in the prototype.
func set_unread(unread: bool) -> void:
	if _blink != null:
		_blink.kill()
		_blink = null
	_picture.modulate.a = 1.0
	if unread:
		_blink = create_tween().set_loops()
		_blink.tween_property(_picture, "modulate:a", 0.35, 0.0).set_delay(BLINK_SECONDS)
		_blink.tween_property(_picture, "modulate:a", 1.0, 0.0).set_delay(BLINK_SECONDS)


## A new file appearing.
func pop() -> void:
	pivot_offset = size / 2.0
	scale = Vector2.ONE * 0.3
	var tween := create_tween()
	for step: float in [0.7, 1.15, 1.0]:
		tween.tween_property(self, "scale", Vector2.ONE * step, 0.0).set_delay(0.12)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if click.double_click:
			_pressing = false
			activated.emit(self)
		elif click.pressed:
			_pressing = true
			_press_at = get_parent_control().get_local_mouse_position()
			_start_position = position
			selected.emit(self)
		elif _pressing:
			_pressing = false
			if _dragging:
				_dragging = false
				modulate.a = 1.0
				dropped.emit(self)
		return
	if event is InputEventMouseMotion and _pressing:
		var delta := get_parent_control().get_local_mouse_position() - _press_at
		if not _dragging:
			if delta.length() < DRAG_THRESHOLD:
				return
			_dragging = true
			modulate.a = 0.8
			move_to_front()
		position = _start_position + delta
		return
	if event.is_action_pressed("ui_accept"):
		accept_event()
		activated.emit(self)
