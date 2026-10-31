class_name ShutdownDialog
extends CanvasLayer
## Start › Chiudi sessione…: the '98 "Shut Down" dialog over a dotted, dimmed screen,
## then "please wait" and, when switching off, the orange "you can now turn off" screen.

## The Manager confirmed: the desktop restarts or quits.
signal confirmed(restart: bool)

const WAIT_SECONDS := 1.6
## How long "you can now turn off" stays up; a key or a click quits sooner.
const OFF_SECONDS := 3.0
const ORANGE := Color("f0a030")

var _ending := false
var _done := false

@onready var _dim: TextureRect = %Dim
@onready var _center: CenterContainer = %Center
@onready var _final: ColorRect = %Final
@onready var _message: Label = %Message
@onready var _restart: CheckBox = %Restart
@onready var _ok: Button = %Ok


func _ready() -> void:
	_dim.texture = _checker()
	_ok.pressed.connect(_on_ok)
	%Cancel.pressed.connect(hide)
	%Close.pressed.connect(hide)


func open() -> void:
	if _ending:
		return
	%PowerOff.button_pressed = true
	_center.show()
	_final.hide()
	show()
	_ok.grab_focus.call_deferred()


func _on_ok() -> void:
	_ending = true
	var restart := _restart.button_pressed
	_center.hide()
	Sfx.play(&"shutdown")
	_message.remove_theme_color_override(&"font_color")
	_message.text = tr("Attendere mentre il sistema viene arrestato…") if not restart else tr("Riavvio di AgencyOS in corso…")
	_final.show()
	await get_tree().create_timer(WAIT_SECONDS).timeout
	if restart:
		_finish(true)
		return
	_message.add_theme_color_override(&"font_color", ORANGE)
	_message.text = tr("Ora è possibile spegnere il computer.")
	var timer := get_tree().create_timer(OFF_SECONDS)
	timer.timeout.connect(_finish.bind(false))
	_final.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_finish(false))


func _finish(restart: bool) -> void:
	if _done:
		return
	_done = true
	confirmed.emit(restart)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _ending:
		if event is InputEventKey and event.pressed and _message.has_theme_color_override(&"font_color"):
			_finish(false)
	elif event.is_action_pressed("ui_cancel"):
		hide()
	else:
		return
	get_viewport().set_input_as_handled()


## Every other pixel black, as Windows 98 dimmed the screen behind this dialog.
static func _checker() -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.set_pixel(0, 0, Color.BLACK)
	image.set_pixel(1, 1, Color.BLACK)
	return ImageTexture.create_from_image(image)
