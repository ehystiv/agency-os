class_name BootScreen
extends CanvasLayer
## BIOS-style boot: diagnostic lines (with a real check of the model server),
## the Agency's triangle and a fade. A click or a key skips it.

signal finished

const LINE_SECONDS := 0.18
const OK_COLOR := "#3fd27a"
const FAIL_COLOR := "#ff6b70"
const DIM_COLOR := "#9aa3a0"
const LOGO_SECONDS := 1.1
const FADE_SECONDS := 0.5
const SERVER_TIMEOUT := 4.0

var _skipped := false
var _running := false
## Lines printed so far (bbcode); the last one can be rewritten.
var _lines: PackedStringArray = []

@onready var _screen: ColorRect = $Screen
@onready var _text: RichTextLabel = %Text
@onready var _logo: Control = %Logo
@onready var _hint: Label = %Hint


func _ready() -> void:
	_screen.hide()


func play() -> void:
	_running = true
	_skipped = false
	_screen.show()
	_screen.modulate.a = 1.0
	_logo.hide()
	_hint.show()
	_lines.clear()
	_text.text = ""
	await _line("AgencyOS 98 BIOS v4.98 · (C) 1998 Triangle Agency", DIM_COLOR)
	await _line("")
	await _line("Memoria .................... 0K")
	for kb in [64, 128, 256, 512, 640]:
		if _skipped:
			break
		_replace_last("Memoria .................... %dK" % kb)
		await _wait(0.06)
	_replace_last("Memoria .................... 640K [color=%s]OK[/color]" % OK_COLOR)
	await _line("Unità C: FILIALE ........... [color=%s]OK[/color]" % OK_COLOR)
	await _line("CAM 03 · CAVEAU ............ [color=%s]OK[/color]" % OK_COLOR)
	await _check_server()
	await _line("Linea riservata ............ [color=%s]NON REGISTRATA[/color]" % FAIL_COLOR)
	await _line("")
	await _line("Avvio di AgencyOS in Modalità Sicura…")
	await _wait(0.5)
	if not _skipped:
		_text.hide()
		_logo.show()
		await _wait(LOGO_SECONDS)
	_hint.hide()
	_text.show()
	var tween := create_tween()
	tween.tween_property(_screen, "modulate:a", 0.0, FADE_SECONDS)
	await tween.finished
	_screen.hide()
	_running = false
	Sfx.play(&"chime")
	finished.emit()


func _input(event: InputEvent) -> void:
	if not _running:
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		_skipped = true
		get_viewport().set_input_as_handled()


## Really queries the model server: if it's off you know before opening the line.
func _check_server() -> void:
	var where := str(Brain.get_setting("url")).trim_prefix("http://").trim_prefix("https://").trim_suffix("/v1")
	await _line("Server del modello (%s) ... " % where)
	if _skipped:
		_replace_last("Server del modello (%s) ... [color=%s]non controllato[/color]" % [where, DIM_COLOR])
		return
	var request := Brain.list_models()
	var waited := 0.0
	while not request.is_done and waited < SERVER_TIMEOUT and not _skipped:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var state := "[color=%s]OK[/color]" % OK_COLOR if request.ok() else "[color=%s]NON RISPONDE[/color]" % FAIL_COLOR
	if not request.is_done:
		request.cancel()
		state = "[color=%s]%s[/color]" % [DIM_COLOR, "non controllato" if _skipped else "NON RISPONDE"]
	_replace_last("Server del modello (%s) ... %s" % [where, state])


func _line(text: String, color: String = "") -> void:
	_lines.append("[color=%s]%s[/color]" % [color, text] if color != "" else text)
	_text.text = "\n".join(_lines)
	await _wait(LINE_SECONDS)


func _replace_last(bbcode: String) -> void:
	if _lines.is_empty():
		_lines.append(bbcode)
	else:
		_lines[-1] = bbcode
	_text.text = "\n".join(_lines)


func _wait(seconds: float) -> void:
	if not _skipped:
		await get_tree().create_timer(seconds).timeout
