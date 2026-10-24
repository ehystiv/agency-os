class_name Balloon
extends PanelContainer
## Notification balloon above the notification area. Goes away by itself or on click.

## Distance from the bottom right corner of the screen (above the taskbar).
const MARGIN := Vector2(8, 48)

var _on_click: Callable = Callable()

@onready var _title: Label = %Title
@onready var _text: Label = %Text
@onready var _timer: Timer = %HideTimer


func _ready() -> void:
	_timer.timeout.connect(hide)
	minimum_size_changed.connect(_place)


func show_message(title: String, text: String, on_click: Callable = Callable()) -> void:
	_title.text = title
	_text.text = text
	_on_click = on_click
	show()
	_place()
	_timer.start()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		hide()
		if _on_click.is_valid():
			_on_click.call()


func _place() -> void:
	reset_size()
	position = get_viewport_rect().size - size - MARGIN
