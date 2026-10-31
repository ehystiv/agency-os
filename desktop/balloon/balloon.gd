class_name Balloon
extends PanelContainer
## Notification balloon above the notification area. Goes away by itself or on click.
## Messages that arrive while one is shown wait their turn (a memo and a file together).

## Distance from the bottom right corner of the screen (above the taskbar).
const MARGIN := Vector2(8, 48)
## Pause between one queued balloon and the next, so the change is visible.
const GAP := 0.3
const MAX_QUEUED := 5

var _on_click: Callable = Callable()
## [title, text, on_click] waiting to be shown.
var _queue: Array[Array] = []

@onready var _title: Label = %Title
@onready var _text: Label = %Text
@onready var _timer: Timer = %HideTimer


func _ready() -> void:
	_timer.timeout.connect(_dismiss)
	minimum_size_changed.connect(_place)


func show_message(title: String, text: String, on_click: Callable = Callable()) -> void:
	if visible:
		if _queue.size() < MAX_QUEUED:
			_queue.append([title, text, on_click])
		return
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
		var on_click := _on_click
		_dismiss()
		if on_click.is_valid():
			on_click.call()


func _dismiss() -> void:
	hide()
	_timer.stop()
	if _queue.is_empty():
		return
	await get_tree().create_timer(GAP).timeout
	if visible or _queue.is_empty():
		return
	var next: Array = _queue.pop_front()
	show_message(next[0], next[1], next[2])


func _place() -> void:
	reset_size()
	position = get_viewport_rect().size - size - MARGIN
