class_name PlayersGlitch
extends Control
## The Entity's glitches as the players see them on the TV: a few short, full-screen
## versions of the Line's effects. Off unless the "players_glitches" UI pref is on;
## nothing runs between glitches (the overlays are freed when done).

const SCREEN_SHADER := preload("res://apps/line/effects/screen_glitch.gdshader")
const RED := Color("e5262c")
const BLUE := Color("0000aa")
const PREF := "players_glitches"
## The glitches the TV shows; the others stay on the Manager's screen.
const SHOWN: PackedStringArray = ["static", "inversion", "rgb", "blackout", "tremor", "scanline", "triangle", "bluescreen"]
const SHAKE_SECONDS := 0.7

## What tremor shakes (the players' stage).
var shake_target: Control

var _shake_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Entity.glitch_started.connect(play)


func play(glitch_name: String) -> void:
	if not is_visible_in_tree() or not bool(Save.get_ui(PREF, false)) or not bool(Save.get_ui("glitches_enabled", true)):
		return
	if not glitch_name in SHOWN:
		return
	var info: Dictionary = Campaign.glitch_table().get(glitch_name, {})
	if bool(Save.get_ui("reduced_motion", false)) and info.get("motion", false):
		glitch_name = "rgb"
	match glitch_name:
		"static":
			_overlay(GlitchLayer.Screen.STATIC, 1.8, 0.28)
		"inversion":
			_overlay(GlitchLayer.Screen.INVERT, 0.26, 1.0)
			await get_tree().create_timer(0.56).timeout
			_overlay(GlitchLayer.Screen.INVERT, 0.2, 1.0)
		"rgb":
			_overlay(GlitchLayer.Screen.RGB, 1.8, 1.4)
		"blackout":
			var black := _rect(Color(0, 0, 0, 0))
			var tween := create_tween()
			tween.tween_property(black, "color:a", 0.97, 0.26)
			tween.tween_interval(1.5)
			tween.tween_property(black, "color:a", 0.0, 0.44)
			tween.finished.connect(black.queue_free)
		"tremor":
			_shake()
		"scanline":
			for i in 5:
				var bar := _overlay(GlitchLayer.Screen.STATIC, 0.9, 0.5)
				bar.size.y = randf_range(6.0, 26.0)
				bar.position.y = randf() * (size.y - bar.size.y)
		"triangle":
			_triangle()
		"bluescreen":
			_bluescreen()


func _overlay(mode: GlitchLayer.Screen, seconds: float, strength: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SCREEN_SHADER
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("strength", strength)
	rect.material = material
	rect.size = size
	add_child(rect)
	get_tree().create_timer(seconds).timeout.connect(rect.queue_free)
	return rect


func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.size = size
	add_child(rect)
	return rect


func _shake() -> void:
	if shake_target == null:
		return
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween()
	for i in 10:
		_shake_tween.tween_property(shake_target, "position", Vector2(randf_range(-14, 14), randf_range(-8, 8)), SHAKE_SECONDS / 11.0)
	_shake_tween.tween_property(shake_target, "position", Vector2.ZERO, SHAKE_SECONDS / 11.0)


## The red triangle of the Line, big in the middle, fading out.
func _triangle() -> void:
	var mark := Polygon2D.new()
	var side := minf(size.x, size.y) * 0.45
	var height := side * 0.866
	mark.polygon = PackedVector2Array([Vector2(0, -height * 0.6), Vector2(side / 2.0, height * 0.4), Vector2(-side / 2.0, height * 0.4)])
	mark.color = RED
	mark.position = size / 2.0
	add_child(mark)
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(mark, "modulate:a", 0.0, 0.9)
	tween.finished.connect(mark.queue_free)


## A short blue screen, the Manager's text without the blinking prompt.
func _bluescreen() -> void:
	var screen := _rect(BLUE)
	var center := CenterContainer.new()
	center.size = size
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 22)
	center.add_child(column)
	var header := Label.new()
	header.text = " AgencyOS "
	header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	header.label_settings = _bluescreen_text(BLUE)
	var header_bg := StyleBoxFlat.new()
	header_bg.bg_color = Color("aaaaaa")
	header.add_theme_stylebox_override(&"normal", header_bg)
	column.add_child(header)
	var body := Label.new()
	body.label_settings = _bluescreen_text(Color.WHITE)
	body.text = tr("Si è verificata un'eccezione irreversibile 0E in 0047:BB000047 in VXD ENTITA(01) +\n0000U047. L'applicazione corrente verrà terminata.\n\n*  Premere un tasto per terminare l'applicazione corrente.\n*  Premere CTRL+ALT+CANC per riavviare il computer. Tutte le\n   informazioni non salvate andranno perse.")
	column.add_child(body)
	get_tree().create_timer(2.0).timeout.connect(screen.queue_free)


static func _bluescreen_text(color: Color) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = PlayerScreen.TITLE_FONT
	settings.font_size = 30
	settings.font_color = color
	return settings
