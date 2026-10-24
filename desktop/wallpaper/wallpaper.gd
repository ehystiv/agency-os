class_name Wallpaper
extends Control
## Desktop background: triangular lattice, vault or solid color.

const MODES: Array[StringName] = [&"lattice", &"vault", &"solid"]
const VAULT_BG := Color("05080f")
const SOLID_BG := Color("11244f")

var mode: StringName = &"lattice"

@onready var _lattice: ColorRect = $Lattice
@onready var _solid: ColorRect = $Solid
@onready var _vault: TextureRect = $Vault


## The cage lattice pulses (visible with the lattice background).
func pulse(seconds: float = 2.9) -> void:
	var material := _lattice.material as ShaderMaterial
	var tween := create_tween()
	var previous := 0.0
	# [fraction of the duration, intensity to reach]
	for step: Array in [[0.25, 1.0], [0.25, 0.35], [0.2, 0.9], [0.3, 0.0]]:
		tween.tween_method(func(v: float) -> void: material.set_shader_parameter("pulse", v),
			previous, step[1], seconds * step[0])
		previous = step[1]


func set_mode(value: StringName) -> void:
	mode = value if value in MODES else &"lattice"
	_lattice.visible = mode == &"lattice"
	_solid.visible = mode != &"lattice"
	_solid.color = VAULT_BG if mode == &"vault" else SOLID_BG
	_vault.visible = mode == &"vault"
