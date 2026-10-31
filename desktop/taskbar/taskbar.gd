class_name Taskbar
extends PanelContainer
## Taskbar: Start, Quick Launch, one button per open window, notification area.

signal start_toggled(open: bool)
signal task_pressed(id: StringName)
signal quick_launch_pressed(id: StringName)
signal show_desktop_pressed
## Right click on a window button (its id) or on the empty taskbar (an empty id).
signal context_requested(id: StringName, at: Vector2)
signal sound_toggled

const TASK_MIN_WIDTH := 70.0
const TASK_MAX_WIDTH := 150.0
const SOUND_ON := preload("res://ui/icons/tray_sound_on.svg")
const SOUND_OFF := preload("res://ui/icons/tray_sound_off.svg")
const SHOW_DESKTOP := preload("res://ui/icons/show_desktop.svg")

@onready var _start: Button = %StartButton
@onready var _quick: HBoxContainer = %QuickLaunch
@onready var _tasks: HBoxContainer = %Tasks
@onready var _sound: TextureButton = %SoundButton
@onready var _next: Label = %Next
@onready var _clock: Label = %Clock
@onready var _mode: Label = %Mode

var _sabotaged := false


func _ready() -> void:
	_start.toggled.connect(start_toggled.emit)
	_sound.pressed.connect(sound_toggled.emit)
	_tasks.resized.connect(_fit_tasks)
	%ClockTimer.timeout.connect(_update_clock)
	_update_clock()


func set_start_open(open: bool) -> void:
	_start.set_pressed_no_signal(open)


## Quick Launch: "Show desktop" first, then the given apps ({id, label, icon}).
func set_quick_launch(entries: Array[Dictionary]) -> void:
	for child in _quick.get_children():
		child.queue_free()
	_quick.add_child(_quick_button(SHOW_DESKTOP, tr("Mostra desktop"), show_desktop_pressed.emit))
	for entry in entries:
		var id: StringName = entry.id
		_quick.add_child(_quick_button(entry.icon, entry.label, func() -> void: quick_launch_pressed.emit(id)))


func _quick_button(icon: Texture2D, tip: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"QuickLaunchButton"
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.icon = icon
	button.expand_icon = true
	button.custom_minimum_size = Vector2(24, 24)
	button.tooltip_text = tip
	button.pressed.connect(on_press)
	return button


func show_tasks(entries: Array[Dictionary]) -> void:
	for child in _tasks.get_children():
		child.queue_free()
	for entry in entries:
		var button := Button.new()
		button.theme_type_variation = &"TaskButton"
		button.toggle_mode = true
		button.button_pressed = entry.active
		button.focus_mode = Control.FOCUS_NONE
		button.text = entry.label
		button.tooltip_text = entry.label
		button.icon = entry.icon
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var id: StringName = entry.id
		button.set_meta(&"id", id)
		button.pressed.connect(func() -> void: task_pressed.emit(id))
		button.gui_input.connect(func(event: InputEvent) -> void:
			if _is_right_click(event):
				button.accept_event()
				context_requested.emit(id, (event as InputEventMouse).global_position))
		_tasks.add_child(button)
	_fit_tasks()


func _gui_input(event: InputEvent) -> void:
	if _is_right_click(event):
		accept_event()
		context_requested.emit(&"", (event as InputEventMouse).global_position)


static func _is_right_click(event: InputEvent) -> bool:
	var click := event as InputEventMouseButton
	return click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT


## Where a window's button is, in canvas coordinates; an empty Rect2 if it has none.
func task_rect(id: StringName) -> Rect2:
	for button: Button in _tasks.get_children():
		if not button.is_queued_for_deletion() and button.get_meta(&"id", &"") == id:
			return button.get_global_rect()
	return Rect2()


func set_sound_enabled(enabled: bool) -> void:
	_sound.texture_normal = SOUND_ON if enabled else SOUND_OFF
	_sound.tooltip_text = tr("Suoni attivi: clic per disattivare") if enabled else tr("Suoni disattivati: clic per attivare")


## Empty text = hides the next session hint.
func set_next_session(text: String) -> void:
	_next.visible = text != ""
	_next.text = text


func _fit_tasks() -> void:
	var buttons := _tasks.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	if buttons.is_empty():
		return
	var gap := float(_tasks.get_theme_constant("separation"))
	var width := (_tasks.size.x - gap * (buttons.size() - 1)) / buttons.size()
	width = clampf(width, TASK_MIN_WIDTH, TASK_MAX_WIDTH)
	for button: Button in buttons:
		button.custom_minimum_size.x = width


## "sabotage" glitch: safe mode off and a crazy clock for a few seconds.
func sabotage(seconds: float = 3.2) -> void:
	_sabotaged = true
	_mode.text = tr("MODALITÀ SICURA ▒▒▒ DISATTIVATA")
	_clock.text = "88:88"
	await get_tree().create_timer(seconds).timeout
	_sabotaged = false
	_mode.text = tr("Modalità Sicura")
	_update_clock()


func _update_clock() -> void:
	if _sabotaged:
		return
	var now := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [now.hour, now.minute]
