class_name CrtOverlay
extends CanvasLayer
## Overlay CRT a tutto schermo. Sempre leggero; per mezzo secondo più forte
## quando parte un glitch violento. Si spegne con l'impostazione "crt_attivo".

const STRONG_GLITCHES: PackedStringArray = ["urlo", "triangolo", "inversione", "statico", "tremito"]
const KICK_SECONDS := 0.5

@onready var _screen: ColorRect = $Screen

var _material: ShaderMaterial


func _ready() -> void:
	_material = _screen.material as ShaderMaterial
	_screen.visible = bool(Save.get_ui("crt_attivo", true))
	Caveau.glitch_started.connect(_on_glitch_started)
	Save.ui_changed.connect(func(key: String) -> void:
		if key == "crt_attivo":
			_screen.visible = bool(Save.get_ui("crt_attivo", true)))


func set_enabled(enabled: bool) -> void:
	_screen.visible = enabled
	Save.set_ui("crt_attivo", enabled)


func _on_glitch_started(glitch_name: String) -> void:
	if glitch_name in STRONG_GLITCHES:
		kick()


## Sdoppiamento dei colori e strappo che si spengono in fretta.
func kick() -> void:
	_material.set_shader_parameter("aberration", 1.0)
	_material.set_shader_parameter("tear", 1.0)
	var tween := create_tween().set_parallel()
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("aberration", v), 1.0, 0.0, KICK_SECONDS)
	tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("tear", v), 1.0, 0.0, KICK_SECONDS)
