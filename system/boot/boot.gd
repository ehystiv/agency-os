class_name BootScreen
extends CanvasLayer
## BIOS-style boot: diagnostic lines (with a real check of the model server),
## ScanDisk after an improper shutdown, the Agency's triangle and a fade.
## A click or a key skips it.

signal finished

const LINE_SECONDS := 0.18
const OK_COLOR := "#3fd27a"
const FAIL_COLOR := "#ff6b70"
const DIM_COLOR := "#9aa3a0"
const LOGO_SECONDS := 1.1
const FADE_SECONDS := 0.5
const SERVER_TIMEOUT := 4.0
const SCANDISK_BLUE := Color("0000aa")
const SCANDISK_STEPS: PackedStringArray = ["Descrittore del supporto", "Tabelle di allocazione dei file", "Struttura delle cartelle", "File system", "Spazio libero", "Analisi della superficie"]
const SCANDISK_STEP_SECONDS := 0.35

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


## True while the boot sequence is on screen.
func is_running() -> bool:
	return _running


## scandisk: the last session didn't end properly, so the disk is checked first.
func play(scandisk: bool = false) -> void:
	_running = true
	_skipped = false
	_screen.show()
	_screen.modulate.a = 1.0
	_logo.hide()
	_hint.show()
	_lines.clear()
	_text.text = ""
	await _line(tr("AgencyOS 98 BIOS v4.98 · (C) 1998 Triangle Agency"), DIM_COLOR)
	await _line("")
	await _line(tr("Memoria .................... %dK") % 0)
	for kb in [64, 128, 256, 512, 640]:
		if _skipped:
			break
		_replace_last(tr("Memoria .................... %dK") % kb)
		await _wait(0.06)
	_replace_last(tr("Memoria .................... 640K %s") % _ok())
	await _line(tr("Unità C: FILIALE ........... %s") % _ok())
	await _line(tr("CAM 03 · CAVEAU ............ %s") % _ok())
	await _check_server()
	await _line(tr("Linea riservata ............ %s") % ("[color=%s]%s[/color]" % [FAIL_COLOR, tr("NON REGISTRATA")]))
	await _line("")
	if scandisk:
		await _scandisk()
	await _line(tr("Avvio di AgencyOS in Modalità Sicura…"))
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
	await _line(tr("Server del modello (%s) ... ") % where)
	if _skipped:
		_replace_last(tr("Server del modello (%s) ... ") % where + "[color=%s]%s[/color]" % [DIM_COLOR, tr("non controllato")])
		return
	var request := Brain.list_models()
	var waited := 0.0
	while not request.is_done and waited < SERVER_TIMEOUT and not _skipped:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var state := _ok() if request.ok() else "[color=%s]%s[/color]" % [FAIL_COLOR, tr("NON RISPONDE")]
	if not request.is_done:
		request.cancel()
		state = "[color=%s]%s[/color]" % [DIM_COLOR, tr("non controllato") if _skipped else tr("NON RISPONDE")]
	_replace_last(tr("Server del modello (%s) ... ") % where + state)


## Windows 98's ScanDisk in text mode, on a blue screen: the steps get a check mark,
## the surface scan a progress bar. Then back to the black boot screen.
func _scandisk() -> void:
	var black := _screen.color
	_screen.color = SCANDISK_BLUE
	var saved := _lines.duplicate()
	_lines.clear()
	await _line("[bgcolor=#aaaaaa][color=#0000aa]  ScanDisk di AgencyOS  [/color][/bgcolor]")
	await _line("")
	await _line(tr("AgencyOS non è stato chiuso correttamente. ScanDisk controlla ora\nl'unità C: FILIALE per verificare la presenza di errori.\n\nPer non vedere più questo messaggio, chiudi AgencyOS con\nStart › Chiudi sessione…"))
	await _line("")
	for step in SCANDISK_STEPS:
		await _line("  »  " + tr(step))
		if step == SCANDISK_STEPS[-1]:
			for percent in range(0, 101, 5):
				if _skipped:
					break
				_replace_last("  »  %s   [%s%s] %d%%" % [tr(step), "█".repeat(percent / 5), "░".repeat(20 - percent / 5), percent])
				await _wait(0.05)
		else:
			await _wait(SCANDISK_STEP_SECONDS)
		_replace_last("  √  " + tr(step))
	await _line("")
	await _line(tr("ScanDisk ha trovato 1 settore che non appartiene a nessun file: 0047BB.\nIl settore è stato lasciato com'è."))
	await _wait(1.6)
	_screen.color = black
	_lines = saved
	_text.text = "\n".join(_lines)


func _ok() -> String:
	return "[color=%s]OK[/color]" % OK_COLOR


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
