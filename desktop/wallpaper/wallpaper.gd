class_name Wallpaper
extends Control
## Sfondo della scrivania: reticolo triangolare, Caveau o tinta unita.

const MODES: Array[StringName] = [&"reticolo", &"caveau", &"tinta"]
const CAVEAU_BG := Color("05080f")
const SOLID_BG := Color("11244f")

var mode: StringName = &"reticolo"

@onready var _lattice: ColorRect = $Lattice
@onready var _solid: ColorRect = $Solid
@onready var _caveau: TextureRect = $Caveau


## Il reticolo della gabbia pulsa (si vede con lo sfondo a reticolo).
func pulse(seconds: float = 2.9) -> void:
	var material := _lattice.material as ShaderMaterial
	var tween := create_tween()
	var previous := 0.0
	# [frazione della durata, intensità da raggiungere]
	for step: Array in [[0.25, 1.0], [0.25, 0.35], [0.2, 0.9], [0.3, 0.0]]:
		tween.tween_method(func(v: float) -> void: material.set_shader_parameter("pulse", v),
			previous, step[1], seconds * step[0])
		previous = step[1]


func set_mode(value: StringName) -> void:
	mode = value if value in MODES else &"reticolo"
	_lattice.visible = mode == &"reticolo"
	_solid.visible = mode != &"reticolo"
	_solid.color = CAVEAU_BG if mode == &"caveau" else SOLID_BG
	_caveau.visible = mode == &"caveau"
