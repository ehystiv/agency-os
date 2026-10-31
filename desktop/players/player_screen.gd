class_name PlayerScreen
extends Window
## "Schermo giocatori": a second macOS window to drag onto the TV or a second monitor.
## It shows only what the Manager sends (a memo, a file, a page, a roll, an image),
## big and in the '98 style, over the desktop wallpaper and the CRT; otherwise it waits.
## F11 or a double click toggle full screen, Esc leaves it. Position and size are remembered.

const PREF := "players_screen"
const BASE_SIZE := Vector2i(1280, 720)
const FRAME_WIDTH := 980.0
const IMAGE_SIZE := Vector2(1120, 600)
const WALLPAPER := preload("res://desktop/wallpaper/wallpaper.tscn")
const CRT := preload("res://system/crt/crt.tscn")
const THEME := preload("res://ui/theme/agency98.tres")
const TITLE_FONT := preload("res://ui/fonts/VT323-Regular.ttf")
## Long texts get a smaller body, so a whole memo fits on the TV.
const BODY_SIZE := 26
const BODY_SIZE_LONG := 20
const LONG_TEXT := 700

var _stage: Control
var _idle: Control
var _frame: PanelContainer
var _caption: Label
var _heading: Label
var _meta: Label
var _body: Label
var _image: TextureRect
var _text_box: VBoxContainer


func _init() -> void:
	# A real window of its own even though the app's popups are embedded
	# (it can only be set while the window is hidden).
	visible = false
	force_native = true
	title = "AgencyOS 98 · Schermo giocatori"
	size = BASE_SIZE
	min_size = Vector2i(480, 270)
	content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	content_scale_size = BASE_SIZE
	theme = THEME
	wrap_controls = false


func _ready() -> void:
	var wallpaper: Wallpaper = WALLPAPER.instantiate()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)
	wallpaper.set_mode(StringName(Save.get_ui("wallpaper", "lattice")))
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	add_child(_stage)
	_idle = _make_idle()
	_stage.add_child(_idle)
	_frame = _make_frame()
	_stage.add_child(_frame)
	_frame.hide()
	add_child(CRT.instantiate())
	close_requested.connect(func() -> void: set_open(false))
	size_changed.connect(_store)
	_restore_geometry()


func set_open(open: bool) -> void:
	if open and not visible:
		show()
		_restore_geometry()
	elif not open and visible:
		_store()
		hide()
	var state: Dictionary = Save.get_ui(PREF, {}).duplicate()
	state["open"] = open
	Save.set_ui(PREF, state)


## item: {kind: "text", caption, heading?, meta?, body} or {kind: "image", caption, texture}.
func present(item: Dictionary) -> void:
	set_open(true)
	_idle.hide()
	_frame.show()
	_caption.text = str(item.get("caption", "AgencyOS"))
	var is_image: bool = item.get("kind", "text") == "image"
	_text_box.visible = not is_image
	_image.visible = is_image
	if is_image:
		_image.texture = item.texture
	else:
		_heading.text = str(item.get("heading", ""))
		_heading.visible = _heading.text != ""
		_meta.text = str(item.get("meta", ""))
		_meta.visible = _meta.text != ""
		var body := str(item.get("body", ""))
		_body.text = body
		_body.add_theme_font_size_override(&"font_size", BODY_SIZE_LONG if body.length() > LONG_TEXT else BODY_SIZE)
	_place_frame.call_deferred()
	var tween := create_tween()
	_frame.modulate.a = 0.0
	tween.tween_property(_frame, "modulate:a", 1.0, 0.25)


## Back to the waiting screen: nothing for the players to read.
func blank() -> void:
	_frame.hide()
	_idle.show()


## Centered; if a long text doesn't fit the screen's height, the whole frame is scaled down
## (nobody can scroll a TV).
func _place_frame() -> void:
	_frame.reset_size()
	var area := _stage.size
	var fit := minf(1.0, minf((area.x - 40.0) / _frame.size.x, (area.y - 40.0) / _frame.size.y))
	_frame.scale = Vector2.ONE * fit
	_frame.position = ((area - _frame.size * fit) / 2.0).round()


func _on_stage_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.double_click and click.button_index == MOUSE_BUTTON_LEFT:
		_toggle_fullscreen()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11 or (key.keycode == KEY_F and key.ctrl_pressed and key.meta_pressed):
		_toggle_fullscreen()
	elif key.keycode == KEY_ESCAPE and mode == Window.MODE_FULLSCREEN:
		_toggle_fullscreen()
	else:
		return
	set_input_as_handled()


func _toggle_fullscreen() -> void:
	mode = Window.MODE_WINDOWED if mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	_store()


func _store() -> void:
	if not visible:
		return
	var state: Dictionary = Save.get_ui(PREF, {}).duplicate()
	state.merge({"x": position.x, "y": position.y, "w": size.x, "h": size.y, "fullscreen": mode == Window.MODE_FULLSCREEN, "screen": current_screen}, true)
	Save.set_ui(PREF, state)


func _restore_geometry() -> void:
	var state: Dictionary = Save.get_ui(PREF, {})
	if state.has("w"):
		var screen := int(state.get("screen", -1))
		if screen >= 0 and screen < DisplayServer.get_screen_count():
			current_screen = screen
		size = Vector2i(int(state.w), int(state.h))
		position = Vector2i(int(state.x), int(state.y))
	if bool(state.get("fullscreen", false)) and visible:
		mode = Window.MODE_FULLSCREEN


func _make_idle() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	center.add_child(column)
	var logo := Label.new()
	logo.text = "▲ AgencyOS 98"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.label_settings = _label_settings(64, Color("d9dde7"))
	column.add_child(logo)
	var waiting := Label.new()
	waiting.text = "In attesa di trasmissione dalla Filiale…"
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.label_settings = _label_settings(26, Color("7fe1ee"))
	column.add_child(waiting)
	return center


## A '98 window, like the desktop's, with big text or an image.
func _make_frame() -> PanelContainer:
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"WindowFrame"
	frame.custom_minimum_size.x = FRAME_WIDTH
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(&"separation", 0)
	frame.add_child(layout)
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TitleBarActive"
	layout.add_child(bar)
	_caption = Label.new()
	_caption.label_settings = _label_settings(28, Color.WHITE)
	bar.add_child(_caption)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layout.add_child(margin)
	var content := VBoxContainer.new()
	margin.add_child(content)
	_text_box = VBoxContainer.new()
	_text_box.add_theme_constant_override(&"separation", 12)
	content.add_child(_text_box)
	_heading = Label.new()
	_heading.label_settings = _label_settings(44, Color("14161c"))
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_box.add_child(_heading)
	_meta = Label.new()
	_meta.theme_type_variation = &"HintLabel"
	_meta.add_theme_font_size_override(&"font_size", 18)
	_text_box.add_child(_meta)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override(&"font_size", BODY_SIZE)
	_body.add_theme_color_override(&"font_color", Color("14161c"))
	_body.add_theme_constant_override(&"line_spacing", 6)
	_text_box.add_child(_body)
	_image = TextureRect.new()
	_image.custom_minimum_size = IMAGE_SIZE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	content.add_child(_image)
	return frame


static func _label_settings(font_size: int, color: Color) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = TITLE_FONT
	settings.font_size = font_size
	settings.font_color = color
	return settings
