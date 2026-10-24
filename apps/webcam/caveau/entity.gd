class_name CaveauEntity
extends Node3D
## L'Entità nella gabbia: massa deformata, occhi che guardano la telecamera,
## tentacoli di perle con un occhietto in punta. Si muove solo quando riceve step().

const RADIUS := 0.82
const EYE_COUNT := 9
const TENDRIL_COUNT := 7
const BEADS_PER_TENDRIL := 11
## Seme fisso: l'Entità ha sempre la stessa faccia.
const SHAPE_SEED := 47
const BLINK_SECONDS := 0.16

const SCLERA := Color("d6f3f6")
const IRIS := Color("2fb8cc")
const PUPIL := Color("020406")

@onready var _body: MeshInstance3D = $Body

var _body_material: ShaderMaterial
var _bead_material: StandardMaterial3D
var _eye_mesh := SphereMesh.new()
var _eyes: Array[Dictionary] = []
var _tendrils: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = SHAPE_SEED
	_body_material = _body.material_override as ShaderMaterial
	_eye_mesh.radius = 1.0
	_eye_mesh.height = 2.0
	_eye_mesh.radial_segments = 10
	_eye_mesh.rings = 8
	_bead_material = StandardMaterial3D.new()
	_bead_material.albedo_color = Color("08131c")
	_bead_material.emission_enabled = true
	_bead_material.emission = Color("03141a")
	_bead_material.roughness = 0.3
	for i in EYE_COUNT:
		var eye := _make_eye(0.17 if i == 0 else _rng.randf_range(0.07, 0.14))
		_eyes.append({"node": eye, "dir": _random_dir(1.1), "blink": 0.0, "next": _rng.randf() * 4.0})
	var bead_mesh := SphereMesh.new()
	bead_mesh.radius = 1.0
	bead_mesh.height = 2.0
	bead_mesh.radial_segments = 6
	bead_mesh.rings = 4
	for k in TENDRIL_COUNT:
		var dir := _random_dir(-0.2)
		dir.y -= 0.35
		dir = dir.normalized()
		var side := dir.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		var up := dir.cross(side).normalized()
		var beads: Array[MeshInstance3D] = []
		for i in BEADS_PER_TENDRIL:
			var bead := MeshInstance3D.new()
			bead.mesh = bead_mesh
			bead.material_override = _bead_material
			add_child(bead)
			beads.append(bead)
		var tip := _make_eye(0.05)
		_tendrils.append({"dir": dir, "side": side, "up": up, "beads": beads, "tip": tip, "phase": _rng.randf() * 6.0})


## time: secondi dall'avvio; wave_time: tempo dell'onda, accelerato dall'agitazione.
## look_at_point: punto globale (vicino alla telecamera) che gli occhi fissano.
func step(time: float, wave_time: float, look_at_point: Vector3) -> void:
	var a := Caveau.agitation
	var amount := 0.12 + 0.3 * a
	_body_material.set_shader_parameter("amount", amount)
	_body_material.set_shader_parameter("wave_time", wave_time)
	_body_material.set_shader_parameter("tint", Caveau.tint)
	_bead_material.emission = Color("03141a").lerp(Color("3a0607"), Caveau.tint)

	var jitter := a * 0.06
	position = Vector3(
		sin(time * 0.4) * 0.55 + _rng.randf_range(-0.5, 0.5) * jitter,
		sin(time * 0.7) * 0.3 + 0.05 + _rng.randf_range(-0.5, 0.5) * jitter,
		cos(time * 0.3) * 0.4 - Caveau.shrink * 1.2)
	rotation = Vector3(sin(time * 0.23) * 0.3, time * 0.15, sin(time * 0.31) * 0.2)
	scale = Vector3.ONE * (1.0 - 0.45 * Caveau.shrink)

	var wide := Caveau.eyes_wide()
	for eye in _eyes:
		var node: Node3D = eye.node
		var dir: Vector3 = eye.dir
		var surface := RADIUS * (1.0 + wave(dir * RADIUS, wave_time) * amount) + 0.02
		node.position = dir * surface
		node.look_at(look_at_point, Vector3.UP, true)
		if time > eye.next:
			eye.blink = BLINK_SECONDS
			eye.next = time + 1.5 + _rng.randf() * (5.0 - a * 3.0)
		if eye.blink > 0.0:
			eye.blink -= 1.0 / 15.0
			node.scale = Vector3(1.0, 0.12, 1.0)
		else:
			node.scale = Vector3.ONE * (1.6 if wide else 1.0)

	for tendril in _tendrils:
		var beads: Array[MeshInstance3D] = tendril.beads
		for i in beads.size():
			var f := float(i) / float(beads.size() - 1)
			var sway := sin(wave_time * 1.3 + i * 0.55 + tendril.phase) * (0.05 + f * 0.45) * (1.0 + a)
			var sway2 := cos(wave_time * 1.1 + i * 0.4 + tendril.phase) * (0.04 + f * 0.3) * (1.0 + a)
			var pos: Vector3 = tendril.dir * (RADIUS * 0.85 + i * 0.15 * (1.0 + a * 0.3))
			pos += tendril.side * sway + tendril.up * sway2
			beads[i].position = pos
			beads[i].scale = Vector3.ONE * 0.15 * (1.0 - f * 0.8)
		var tip: Node3D = tendril.tip
		tip.position = beads.back().position
		tip.look_at(look_at_point, Vector3.UP, true)


## Stessa formula dello shader del corpo.
static func wave(p: Vector3, t: float) -> float:
	return sin(p.x * 3.0 + t * 1.1) * 0.5 + sin(p.y * 4.3 - t * 0.9) * 0.35 + sin(p.z * 5.1 + t * 1.7 + p.x * 2.0) * 0.25


func _random_dir(z_bias: float) -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1) + z_bias).normalized()


## Occhio: sclera, iride e pupilla che sporgono verso +Z (il davanti).
func _make_eye(size: float) -> Node3D:
	var eye := Node3D.new()
	add_child(eye)
	for part: Array in [[SCLERA, 1.0, 0.0], [IRIS, 0.55, 0.62], [PUPIL, 0.3, 0.9]]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _eye_mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = part[0]
		mesh.material_override = material
		mesh.scale = Vector3.ONE * size * float(part[1])
		mesh.position.z = size * float(part[2])
		eye.add_child(mesh)
	return eye
