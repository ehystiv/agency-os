class_name DiceTray
extends Node3D
## Dice tray: floor with a lattice, invisible walls, six d4 with real physics.
## roll() throws them and returns the values read from the simulation once they are still.

signal rolling_changed(rolling: bool)
## A die hit the floor, a wall or another die; strength 0..1 (for the sound).
signal impact(strength: float)

const DICE := 6
const FLOOR_COLOR := Color("0e1a26")
const GRID_CENTER := Color("1d3a4a")
const GRID_LINE := Color("13242f")
## Inner area of the walls (x, z), inside the shot.
const TRAY_MIN := Vector2(-1.6, -0.9)
const TRAY_MAX := Vector2(1.6, 1.05)
const CAMERA_POSITION := Vector3(0, 3.1, 2.3)
const CAMERA_TARGET := Vector3(0, 0, 0.1)
const WALL_HEIGHT := 3.0
## Still = almost motionless for this long.
const REST_SPEED := 0.06
const REST_SPIN := 0.15
const REST_SECONDS := 0.3
const MAX_ROLL_SECONDS := 4.0
const MAX_NUDGES := 3
## A sudden change of a die's speed is a hit: below this (m/s) it's just rolling or falling
## (gravity alone adds about 0.16 m/s per physics frame).
const HIT_MIN := 0.35
## Change of speed that sounds at full volume.
const HIT_FULL := 4.0
## A die makes at most one sound in this time: one landing is often several contacts.
const HIT_GAP_MS := 35
## Just after the throw the physics pushes apart dice that appeared overlapping: not a sound.
const HIT_QUIET_MS := 60

var rolling := false
var _dice: Array[D4] = []
## Speed of each die at the last physics frame, and when it last sounded.
var _last_velocity: Array[Vector3] = []
var _last_hit_ms: Array[int] = []
var _quiet_until_ms := 0


func _ready() -> void:
	var camera := Camera3D.new()
	camera.fov = 38.0
	add_child(camera)
	camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("070b14")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("8090a8")
	environment.environment.ambient_light_energy = 1.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(-2, 5, 3), Vector3.ZERO)
	var glow := OmniLight3D.new()
	glow.light_color = Color("7fe1ee")
	glow.light_energy = 0.8
	glow.omni_range = 10.0
	glow.position = Vector3(2.5, 2, 1.5)
	add_child(glow)
	_build_floor()
	_build_walls()
	for i in DICE:
		var die := D4.create()
		add_child(die)
		_dice.append(die)
	_line_up()


## Throws the six dice and waits for them to stop; returns the values, in dice order.
func roll() -> Array[int]:
	rolling = true
	rolling_changed.emit(true)
	for die in _dice:
		die.highlight(null)
		die.freeze = false
		die.sleeping = false
		die.global_transform = Transform3D(_random_basis(), Vector3(randf_range(-1.2, 1.2), randf_range(1.2, 1.9), randf_range(-0.6, 0.8)))
		die.linear_velocity = Vector3(-die.position.x * 0.8 + randf_range(-0.8, 0.8), randf_range(-2.0, -0.5), randf_range(-0.9, 0.5))
		var spin := randf_range(3.0, 6.0) if bool(Save.get_ui("reduced_motion", false)) else randf_range(8.0, 15.0)
		die.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * spin
	_quiet_until_ms = Time.get_ticks_msec() + HIT_QUIET_MS
	_last_velocity.clear()
	_last_hit_ms.clear()
	for die in _dice:
		_last_velocity.append(die.linear_velocity)
		_last_hit_ms.append(0)
	await _wait_until_rest()
	var nudges := 0
	while nudges < MAX_NUDGES and _dice.any(func(d: D4) -> bool: return not d.is_flat()):
		# A die leaning askew is rerolled with a small push, like at the table.
		for die in _dice:
			if not die.is_flat():
				die.sleeping = false
				die.apply_central_impulse(Vector3(randf_range(-0.03, 0.03), 0.06, randf_range(-0.03, 0.03)))
				die.angular_velocity = Vector3(randf(), randf(), randf()) * 6.0
		await _wait_until_rest()
		nudges += 1
	var values: Array[int] = []
	for die in _dice:
		values.append(die.top_value())
	rolling = false
	rolling_changed.emit(false)
	return values


## Highlights the dice showing target; -1 removes the highlight.
func highlight(target: int) -> void:
	for die in _dice:
		die.highlight(null if target < 0 else die.top_value() == target)


func _wait_until_rest() -> void:
	var still := 0.0
	var elapsed := 0.0
	while elapsed < MAX_ROLL_SECONDS:
		await get_tree().physics_frame
		_listen_for_hits()
		var delta := get_physics_process_delta_time()
		elapsed += delta
		var moving := _dice.any(func(d: D4) -> bool: return d.linear_velocity.length() > REST_SPEED or d.angular_velocity.length() > REST_SPIN)
		still = 0.0 if moving else still + delta
		if still >= REST_SECONDS:
			return


## Hits are sudden changes of speed: the floor, a wall or another die stopped or deflected
## the die. Read from the simulation, so the sound follows exactly what is seen.
func _listen_for_hits() -> void:
	var now := Time.get_ticks_msec()
	for i in _dice.size():
		var velocity := _dice[i].linear_velocity
		var change := (velocity - _last_velocity[i]).length()
		_last_velocity[i] = velocity
		if change >= HIT_MIN and now >= _quiet_until_ms and now - _last_hit_ms[i] >= HIT_GAP_MS:
			_last_hit_ms[i] = now
			impact.emit(clampf((change - HIT_MIN) / (HIT_FULL - HIT_MIN), 0.0, 1.0) * 0.9 + 0.1)


## Before the first roll the dice are in a row, resting on a face.
func _line_up() -> void:
	var flat := Basis(Quaternion(Vector3(1, 1, 1).normalized(), Vector3.UP))
	for i in _dice.size():
		var yaw := Basis(Vector3.UP, randf() * TAU)
		_dice[i].global_transform = Transform3D(yaw * flat, Vector3(-1.25 + i * 0.5, D4.RADIUS / 3.0 + 0.01, 0.15))


func _random_basis() -> Basis:
	return Basis(Quaternion(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf() * TAU))


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	var physics := PhysicsMaterial.new()
	physics.friction = 0.7
	physics.bounce = 0.2
	body.physics_material_override = physics
	add_child(body)
	var plane := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(14, 9)
	plane.mesh = plane_mesh
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	floor_material.roughness = 1.0
	plane.material_override = floor_material
	add_child(plane)
	# 14×14 m lattice in 28 divisions, like the prototype's GridHelper.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for i in 29:
		var v := -7.0 + i * 0.5
		var color := GRID_CENTER if i == 14 else GRID_LINE
		points.append_array([Vector3(v, 0.002, -7), Vector3(v, 0.002, 7), Vector3(-7, 0.002, v), Vector3(7, 0.002, v)])
		colors.append_array([color, color, color, color])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	var grid_mesh := ArrayMesh.new()
	grid_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var grid := MeshInstance3D.new()
	grid.mesh = grid_mesh
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.vertex_color_use_as_albedo = true
	grid.material_override = grid_material
	add_child(grid)


## Four invisible walls around the framed area.
func _build_walls() -> void:
	var center := (TRAY_MIN + TRAY_MAX) / 2.0
	var half := (TRAY_MAX - TRAY_MIN) / 2.0
	var walls := [
		[Vector3(TRAY_MIN.x - 0.1, WALL_HEIGHT / 2, center.y), Vector3(0.2, WALL_HEIGHT, half.y * 2 + 0.4)],
		[Vector3(TRAY_MAX.x + 0.1, WALL_HEIGHT / 2, center.y), Vector3(0.2, WALL_HEIGHT, half.y * 2 + 0.4)],
		[Vector3(center.x, WALL_HEIGHT / 2, TRAY_MIN.y - 0.1), Vector3(half.x * 2 + 0.4, WALL_HEIGHT, 0.2)],
		[Vector3(center.x, WALL_HEIGHT / 2, TRAY_MAX.y + 0.1), Vector3(half.x * 2 + 0.4, WALL_HEIGHT, 0.2)],
	]
	for wall: Array in walls:
		var body := StaticBody3D.new()
		body.position = wall[0]
		var box := BoxShape3D.new()
		box.size = wall[1]
		var shape := CollisionShape3D.new()
		shape.shape = box
		body.add_child(shape)
		add_child(body)
