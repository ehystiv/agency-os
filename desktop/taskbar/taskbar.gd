class_name Taskbar
extends PanelContainer
## Taskbar: Start, one button per open window, notification area.

signal start_toggled(open: bool)
signal task_pressed(id: StringName)
signal sound_toggled

const TASK_MIN_WIDTH := 70.0
const TASK_MAX_WIDTH := 150.0
const SOUND_ON := preload("res://ui/icons/tray_sound_on.svg")
const SOUND_OFF := preload("res://ui/icons/tray_sound_off.svg")

@onready var _start: Button = %StartButton
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
		button.pressed.connect(func() -> void: task_pressed.emit(id))
		_tasks.add_child(button)
	_fit_tasks()


func set_sound_enabled(enabled: bool) -> void:
	_sound.texture_normal = SOUND_ON if enabled else SOUND_OFF
	_sound.tooltip_text = "Suoni attivi: clic per disattivare" if enabled else "Suoni disattivati: clic per attivare"


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
	_mode.text = "MODALITÀ SICURA ▒▒▒ DISATTIVATA"
	_clock.text = "88:88"
	await get_tree().create_timer(seconds).timeout
	_sabotaged = false
	_mode.text = "Modalità Sicura"
	_update_clock()


func _update_clock() -> void:
	if _sabotaged:
		return
	var now := Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [now.hour, now.minute]
