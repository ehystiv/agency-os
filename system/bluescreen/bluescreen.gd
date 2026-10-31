class_name BlueScreen
extends CanvasLayer
## The "bluescreen" glitch: Windows 98's fatal exception screen, signed by the Entity.
## A key or a click brings the desktop back (nothing is really closed), or it goes by itself.

const BLUE := Color("0000aa")
const GREY := Color("aaaaaa")
const FONT := preload("res://ui/fonts/VT323-Regular.ttf")
const FONT_SIZE := 24
const MAX_SECONDS := 12.0
## A key pressed right when it appears doesn't close it at once.
const GRACE_SECONDS := 0.5

var _shown_at := 0.0
var _screen: ColorRect
var _cursor: Label


func _ready() -> void:
	layer = 58
	visible = false
	_screen = ColorRect.new()
	_screen.color = BLUE
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 22)
	center.add_child(column)
	var header := Label.new()
	header.text = " AgencyOS "
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header.label_settings = _settings(BLUE)
	var header_bg := StyleBoxFlat.new()
	header_bg.bg_color = GREY
	header.add_theme_stylebox_override(&"normal", header_bg)
	column.add_child(header)
	var body := Label.new()
	body.label_settings = _settings(Color.WHITE)
	body.text = tr("Si è verificata un'eccezione irreversibile 0E in 0047:BB000047 in VXD ENTITA(01) +\n0000U047. L'applicazione corrente verrà terminata.\n\n*  Premere un tasto per terminare l'applicazione corrente.\n*  Premere CTRL+ALT+CANC per riavviare il computer. Tutte le\n   informazioni non salvate andranno perse.")
	column.add_child(body)
	_cursor = Label.new()
	_cursor.label_settings = _settings(Color.WHITE)
	_cursor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_cursor)


func crash() -> void:
	_shown_at = _now()
	visible = true
	_blink()
	await get_tree().create_timer(MAX_SECONDS).timeout
	if _now() - _shown_at >= MAX_SECONDS - 0.1:
		_close()


func _blink() -> void:
	while visible:
		var on := int(_now() * 2.0) % 2 == 0
		_cursor.text = tr("Premere un tasto per continuare") + (" _" if on else "  ")
		await get_tree().create_timer(0.25).timeout


func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()
	var pressed := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed()
	if pressed and _now() - _shown_at > GRACE_SECONDS:
		_close()


func _close() -> void:
	visible = false


static func _settings(color: Color) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = FONT
	settings.font_size = FONT_SIZE
	settings.font_color = color
	return settings


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
