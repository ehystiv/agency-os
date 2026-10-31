class_name JackpotOverlay
extends CanvasLayer
## Triscendence celebration over the whole desktop, like a slot machine jackpot:
## golden rays, a burst of triangles from the calculator, then a rain of them over the
## screen, a blinking "▲ TRISCENDENZA ▲" banner and a fanfare. Ends by itself or on a click.
## Above the windows and the taskbar, below the screensaver and the CRT.

const SECONDS := 3.6
const FADE_SECONDS := 0.4
const GRAVITY := 620.0
const DRAG := 0.6
const BURST := 110
const RAIN := 90
const RAIN_SECONDS := 1.6
## With reduced motion: fewer triangles, still rays, no blinking.
const CALM_BURST := 30
const CALM_RAIN := 20
const RAYS := 16
const COLORS: Array[Color] = [Color("ffd23f"), Color("ffd23f"), Color("e5262c"), Color("7fe1ee"), Color("ffffff")]
const GOLD := Color("ffd23f")
const RED := Color("e5262c")
const NAVY := Color("0b1230")
const TITLE_FONT := preload("res://ui/fonts/VT323-Regular.ttf")

var _stage: Control
var _banner: PanelContainer
var _title: Label
var _time := 0.0
var _calm := false
var _rain_left := 0
var _ending := false
## Triangles: position, velocity, rotation, spin, size, color, hollow.
var _pos: Array[Vector2] = []
var _vel: Array[Vector2] = []
var _rot: Array[float] = []
var _spin: Array[float] = []
var _size: Array[float] = []
var _color: Array[Color] = []
var _hollow: Array[bool] = []


func _init() -> void:
	layer = 50
	visible = false


func _ready() -> void:
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.draw.connect(_draw_stage)
	_stage.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_end())
	add_child(_stage)
	_banner = _make_banner()
	_stage.add_child(_banner)
	set_process(false)


## origin: where the burst starts (the top of the calculator), in desktop coordinates.
func play(origin: Vector2) -> void:
	_calm = bool(Save.get_ui("reduced_motion", false))
	_time = 0.0
	_ending = false
	_clear()
	for i in CALM_BURST if _calm else BURST:
		var angle := deg_to_rad(randf_range(-150.0, -30.0))
		_spawn(origin + Vector2(randf_range(-40, 40), 0), Vector2.from_angle(angle) * randf_range(280.0, 760.0))
	_rain_left = CALM_RAIN if _calm else RAIN
	_stage.modulate.a = 1.0
	visible = true
	_show_banner()
	Sfx.play(&"jackpot")
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	var area := _stage.size
	# The rain: new triangles from the top during the first seconds.
	var due := int(float(CALM_RAIN if _calm else RAIN) * clampf(_time / RAIN_SECONDS, 0.0, 1.0))
	var rained := (CALM_RAIN if _calm else RAIN) - _rain_left
	for i in due - rained:
		_spawn(Vector2(randf() * area.x, -20.0), Vector2(randf_range(-60, 60), randf_range(80, 260)))
		_rain_left -= 1
	for i in _pos.size():
		_vel[i].y += GRAVITY * delta
		_vel[i] *= 1.0 - DRAG * delta
		# A little flutter, like paper.
		_vel[i].x += sin(_time * 6.0 + i) * 30.0 * delta
		_pos[i] += _vel[i] * delta
		_rot[i] += _spin[i] * delta
	if not _calm and _time < 1.2:
		_title.modulate = Color.WHITE if int(_time * 9.0) % 2 == 0 else GOLD.lightened(0.4)
	else:
		_title.modulate = Color.WHITE
	_stage.queue_redraw()
	if _time >= SECONDS:
		_end()


func _end() -> void:
	if _ending or not visible:
		return
	_ending = true
	var tween := create_tween()
	tween.tween_property(_stage, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(func() -> void:
		visible = false
		set_process(false)
		_clear())


func _spawn(at: Vector2, velocity: Vector2) -> void:
	_pos.append(at)
	_vel.append(velocity)
	_rot.append(randf() * TAU)
	_spin.append(randf_range(-9.0, 9.0))
	_size.append(randf_range(6.0, 14.0))
	_color.append(COLORS[randi() % COLORS.size()])
	_hollow.append(randf() < 0.3)


func _clear() -> void:
	for list: Array in [_pos, _vel, _rot, _spin, _size, _color, _hollow]:
		list.clear()


func _draw_stage() -> void:
	var area := _stage.size
	var center := area / 2.0
	# Rays behind the banner, turning slowly; they fade in and out.
	var rays_alpha := clampf(_time / 0.3, 0.0, 1.0) * 0.16
	var turn := 0.0 if _calm else _time * 0.5
	var reach := area.length()
	for i in RAYS:
		var a := turn + TAU * i / RAYS
		var b := a + TAU / RAYS / 2.0
		_stage.draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(a) * reach, center + Vector2.from_angle(b) * reach]), Color(GOLD, rays_alpha))
	for i in _pos.size():
		var points := PackedVector2Array()
		for k in 3:
			points.append(_pos[i] + Vector2.from_angle(_rot[i] + TAU * k / 3.0) * _size[i])
		if _hollow[i]:
			points.append(points[0])
			_stage.draw_polyline(points, _color[i], 2.0)
		else:
			_stage.draw_colored_polygon(points, _color[i])


func _make_banner() -> PanelContainer:
	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = NAVY
	style.border_color = GOLD
	style.set_border_width_all(4)
	style.set_content_margin_all(18)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_offset = Vector2(8, 8)
	banner.add_theme_stylebox_override(&"panel", style)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(column)
	_title = Label.new()
	_title.text = "▲ TRISCENDENZA ▲"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var settings := LabelSettings.new()
	settings.font = TITLE_FONT
	settings.font_size = 72
	settings.font_color = GOLD
	settings.shadow_color = RED
	settings.shadow_offset = Vector2(4, 4)
	settings.shadow_size = 0
	_title.label_settings = settings
	column.add_child(_title)
	var subtitle := Label.new()
	subtitle.text = "★  tre 3 su sei dadi · nessun Caos  ★"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var small := LabelSettings.new()
	small.font = TITLE_FONT
	small.font_size = 26
	small.font_color = Color("7fe1ee")
	subtitle.label_settings = small
	column.add_child(subtitle)
	return banner


## The banner pops in from the middle of the screen, with a little overshoot.
func _show_banner() -> void:
	_banner.reset_size()
	_banner.position = (_stage.size - _banner.size) / 2.0
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2.ONE * (0.6 if _calm else 0.15)
	var tween := create_tween()
	tween.tween_property(_banner, "scale", Vector2.ONE, 0.25 if _calm else 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
