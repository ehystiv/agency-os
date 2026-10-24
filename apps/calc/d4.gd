class_name D4
extends RigidBody3D
## Four-sided die with real physics. Like a real d4 it has three numbers per face,
## near the corners, and its value is the number of the vertex pointing up.
## Triangle Agency dice style: grey, a red tip around the 3, white numbers.

## Radius of the circumscribed sphere (as in the prototype).
const RADIUS := 0.42
const BODY := Color("c4c7cc")
const CAP := Color("c4161c")
const INK := Color("ffffff")
## After the roll the dice without a 3 get a bit darker (multiplies the vertex colors).
const DIM := Color(0.72, 0.72, 0.75)
## The vertex with the red tip (value 3) and how far the tip goes down the edges.
const CAP_VERTEX := 2
const CAP_SIZE := 0.5
const LABEL_FONT := preload("res://ui/fonts/IBMPlexMono-Medium.ttf")
## Maximum tilt of the resting face for the die to count as properly still.
const FLAT_DOT := 0.92

## Vertices of the regular tetrahedron; the value of vertex i is i + 1.
var _vertices: PackedVector3Array
var _material := StandardMaterial3D.new()


static func create() -> D4:
	var die := D4.new()
	die._build()
	return die


## The number of the highest vertex.
func top_value() -> int:
	var best := 0
	var best_y := -INF
	for i in _vertices.size():
		var y := to_global(_vertices[i]).y
		if y > best_y:
			best_y = y
			best = i
	return best + 1


## True if the die rests on a face (and not on an edge or on another die).
func is_flat() -> bool:
	var top := top_value() - 1
	var bottom_center := Vector3.ZERO
	for i in _vertices.size():
		if i != top:
			bottom_center += _vertices[i] / 3.0
	var down := (global_transform.basis * bottom_center).normalized()
	return down.dot(Vector3.DOWN) > FLAT_DOT


## After the roll the dice not showing the good number get darker; null = all normal.
func highlight(hit: Variant) -> void:
	_material.albedo_color = DIM if hit == false else Color.WHITE


func _build() -> void:
	var s := RADIUS / sqrt(3.0)
	_vertices = PackedVector3Array([Vector3(1, 1, 1) * s, Vector3(1, -1, -1) * s, Vector3(-1, 1, -1) * s, Vector3(-1, -1, 1) * s])
	mass = 0.03
	continuous_cd = true
	var physics := PhysicsMaterial.new()
	physics.friction = 0.6
	physics.bounce = 0.25
	physics_material_override = physics

	var shape := ConvexPolygonShape3D.new()
	shape.points = _vertices
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)

	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.45
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new()
	mesh.mesh = _tetrahedron()
	mesh.material_override = _material
	add_child(mesh)
	for face in _faces():
		_add_numbers(face)


## The four faces, each given by the three vertices that make it.
func _faces() -> Array[PackedInt32Array]:
	return [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 3, 1]), PackedInt32Array([0, 2, 3]), PackedInt32Array([1, 3, 2])]


func _face_normal(face: PackedInt32Array) -> Vector3:
	var center := (_vertices[face[0]] + _vertices[face[1]] + _vertices[face[2]]) / 3.0
	return center.normalized()


## Flat faces; on the three faces touching the vertex of the 3 the tip is red.
func _tetrahedron() -> ArrayMesh:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for face in _faces():
		var normal := _face_normal(face)
		var triangles: Array[Array] = []
		if CAP_VERTEX in face:
			# Rotate the face so it starts from the vertex of the 3, keeping the vertex order.
			var start := face.find(CAP_VERTEX)
			var tip := _vertices[face[start]]
			var left := _vertices[face[(start + 1) % 3]]
			var right := _vertices[face[(start + 2) % 3]]
			var cap_left := tip.lerp(left, CAP_SIZE)
			var cap_right := tip.lerp(right, CAP_SIZE)
			triangles = [[tip, cap_left, cap_right, CAP], [cap_left, left, right, BODY], [cap_left, right, cap_right, BODY]]
		else:
			triangles = [[_vertices[face[0]], _vertices[face[1]], _vertices[face[2]], BODY]]
		for triangle in triangles:
			for corner in 3:
				points.append(triangle[corner])
				normals.append(normal)
				colors.append(triangle[3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One number per face corner, turned with its top towards its vertex.
func _add_numbers(face: PackedInt32Array) -> void:
	var normal := _face_normal(face)
	var center := (_vertices[face[0]] + _vertices[face[1]] + _vertices[face[2]]) / 3.0
	for index in face:
		var up := (_vertices[index] - center).normalized()
		var right := up.cross(normal).normalized()
		var label := Label3D.new()
		label.text = str(index + 1)
		label.font = LABEL_FONT
		label.font_size = 48
		label.pixel_size = 0.0038
		label.modulate = INK
		label.outline_size = 0
		label.double_sided = false
		label.shaded = false
		label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		label.transform = Transform3D(Basis(right, up, normal), center.lerp(_vertices[index], 0.5) + normal * 0.003)
		add_child(label)
