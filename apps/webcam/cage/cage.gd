class_name CageScene
extends Node3D
## CAM 03 shot: wireframe triangular cage, floor lattice,
## the Agency's small red triangle and the Entity. Line geometry is built here.

const CYAN := Color("7fe1ee")
const RED := Color("e5262c")
const GRID_CENTER := Color("1a3d48")
const GRID_LINE := Color("0c1c24")
const CAGE_RADIUS := 2.3
const CAGE_HEIGHT := 3.6
const CAGE_SEGMENTS := 4
const FLOOR_Y := -1.85
const KEY_ENERGY := 3.0
const RED_ENERGY := 2.2

@onready var _camera: Camera3D = $Camera3D
@onready var _key_light: OmniLight3D = $KeyLight
@onready var _red_light: OmniLight3D = $RedLight
@onready var _cage: MeshInstance3D = $Cage
@onready var _grid: MeshInstance3D = $FloorGrid
@onready var _triangle: MeshInstance3D = $RedTriangle
@onready var _entity: EntityModel = $Entity

var _cage_material: StandardMaterial3D


func _ready() -> void:
	_camera.look_at_from_position(Vector3(0, 0.7, 5.4), Vector3(0, -0.1, 0))
	_cage_material = _unshaded(CYAN, 0.5)
	_cage.mesh = _cage_lines()
	_cage.material_override = _cage_material
	_cage.rotation.y = PI / 6.0
	_grid.mesh = _floor_grid()
	var grid_material := _unshaded(Color.WHITE, 1.0)
	grid_material.vertex_color_use_as_albedo = true
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_grid.material_override = grid_material
	_triangle.mesh = _red_triangle()
	_triangle.material_override = _unshaded(RED, 1.0)


## One frame: time in seconds, wave_time sped up by agitation.
func step(time: float, wave_time: float) -> void:
	var look := _camera.global_position + Vector3(sin(time * 0.9) * 0.6, cos(time * 0.7) * 0.4, 0.0)
	_entity.step(time, wave_time, look)
	_red_light.light_energy = RED_ENERGY * Entity.tint
	_key_light.light_energy = KEY_ENERGY + sin(time * 3.0) * 0.08 + (0.3 if Entity.speaking else 0.0)
	_cage_material.albedo_color.a = 0.45 + sin(time * 1.7) * 0.07 + Entity.agitation * 0.15


func _unshaded(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## Prism corners like a 3-sided three.js CylinderGeometry (x = sin, z = cos).
func _corner(index: int, y: float) -> Vector3:
	var angle := TAU * float(index % 3) / 3.0
	return Vector3(CAGE_RADIUS * sin(angle), y, CAGE_RADIUS * cos(angle))


func _ring_y(row: int) -> float:
	return CAGE_HEIGHT / 2.0 - CAGE_HEIGHT * float(row) / CAGE_SEGMENTS


## Edges, rings and face diagonals, like the prototype's wireframe.
func _cage_lines() -> ArrayMesh:
	var points := PackedVector3Array()
	for row in CAGE_SEGMENTS + 1:
		for i in 3:
			points.append_array([_corner(i, _ring_y(row)), _corner(i + 1, _ring_y(row))])
	for row in CAGE_SEGMENTS:
		for i in 3:
			points.append_array([_corner(i, _ring_y(row)), _corner(i, _ring_y(row + 1))])
			points.append_array([_corner(i + 1, _ring_y(row)), _corner(i, _ring_y(row + 1))])
	return _mesh(Mesh.PRIMITIVE_LINES, points)


## 16×16 m lattice in 32 divisions, with the two center lines brighter.
func _floor_grid() -> ArrayMesh:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var half := 8.0
	for i in 33:
		var v := -half + i * 0.5
		var color := GRID_CENTER if i == 16 else GRID_LINE
		points.append_array([Vector3(v, FLOOR_Y, -half), Vector3(v, FLOOR_Y, half), Vector3(-half, FLOOR_Y, v), Vector3(half, FLOOR_Y, v)])
		colors.append_array([color, color, color, color])
	return _mesh(Mesh.PRIMITIVE_LINES, points, colors)


func _red_triangle() -> ArrayMesh:
	var center := Vector3(0.2, -1.83, 1.5)
	var points := PackedVector3Array()
	for i in 3:
		var angle := PI + TAU * i / 3.0
		points.append(center + Vector3(sin(angle), 0.0, cos(angle)) * 0.26)
	return _mesh(Mesh.PRIMITIVE_TRIANGLES, points)


func _mesh(primitive: Mesh.PrimitiveType, points: PackedVector3Array, colors: PackedColorArray = PackedColorArray()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(primitive, arrays)
	return mesh
