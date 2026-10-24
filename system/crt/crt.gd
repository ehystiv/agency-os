class_name CrtOverlay
extends CanvasLayer
## Full-screen CRT overlay. Always light; stronger for half a second
## when a violent glitch starts. Turned off by the "crt_enabled" setting.

const STRONG_GLITCHES: PackedStringArray = ["scream", "triangle", "inversion", "static", "tremor"]
const KICK_SECONDS := 0.5

@onready var _screen: ColorRect = $Screen

var _material: ShaderMaterial


func _ready() -> void:
	_material = _screen.material as ShaderMaterial
	_screen.visible = bool(Save.get_ui("crt_enabled", true))
	Entity.glitch_started.connect(_on_glitch_started)
	Save.ui_changed.connect(func(key: String) -> void:
		if key == "crt_enabled":
			_screen.visible = bool(Save.get_ui("crt_enabled", true)))


func set_enabled(enabled: bool) -> void:
	_screen.visible = enabled
	Save.set_ui("crt_enabled", enabled)


func _on_glitch_started(glitch_name: String) -> void:
	if glitch_name in STRONG_GLITCHES:
		kick()


## Color split and tear that fade out quickly.
func kick() -> void:
	_material.set_shader_parameter("aberration", 1.0)
	_material.set_shader_parameter("tear", 1.0)
	var tween := create_tween().set_parallel()
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("aberration", v), 1.0, 0.0, KICK_SECONDS)
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("tear", v), 1.0, 0.0, KICK_SECONDS)
