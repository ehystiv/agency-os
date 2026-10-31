class_name ScreenSaver
extends CanvasLayer
## Screensaver: wireframe triangles coming at you in the dark
## and, now and then, an eye opening in the middle. Starts after the minutes chosen
## in the Control panel; a key or the mouse closes it.

const TRIANGLES := 40
const CYAN := Color("7fe1ee")
const RED := Color("e5262c")
const DEPTH := 12.0
const SPEED := 2.2
const FOCAL := 420.0
const EYE_EVERY := 9.0
const EYE_SECONDS := 3.0
## The mouse must move a bit to close the screensaver (not a twitch): screen pixels, summed up.
const WAKE_DISTANCE := 6.0

var active := false
var _idle := 0.0
## Mouse movement since the screensaver started.
var _wake_motion := 0.0
var _time := 0.0
var _triangles: Array[Dictionary] = []

@onready var _canvas: Control = $Canvas


func _ready() -> void:
	_canvas.hide()
	_canvas.draw.connect(_draw_scene)


## Starts it right away (preview from the Control panel).
func start() -> void:
	active = true
	_time = 0.0
	_wake_motion = 0.0
	_triangles.clear()
	for i in TRIANGLES:
		_triangles.append(_new_triangle(randf() * DEPTH))
	_canvas.show()


func stop() -> void:
	active = false
	_idle = 0.0
	_canvas.hide()


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		# Slow movements arrive as many 1-2 px events: any of them means someone is there,
		# and while the screensaver runs they add up until they are a real movement.
		if motion.screen_relative.is_zero_approx():
			return
		_idle = 0.0
		_wake_motion += motion.screen_relative.length()
		if active and _wake_motion >= WAKE_DISTANCE:
			_wake()
	# Trackpad scrolling and pinching on macOS come as gestures, not as mouse buttons.
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventGesture or event is InputEventScreenTouch:
		_idle = 0.0
		if active:
			_wake()


func _wake() -> void:
	stop()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if active:
		_time += delta
		for t in _triangles:
			t.z -= SPEED * delta
			t.angle += t.spin * delta
			if t.z < 0.3:
				t.merge(_new_triangle(DEPTH), true)
		_canvas.queue_redraw()
		return
	var minutes := int(Save.get_ui("screensaver_minutes", 3))
	if minutes <= 0 or _blocked():
		_idle = 0.0
		return
	_idle += delta
	if _idle >= minutes * 60.0:
		start()


## Doesn't start while the Entity is writing or the Player is playing, as in the prototype.
func _blocked() -> bool:
	if Entity.speaking:
		return true
	for node in get_tree().get_nodes_in_group(&"music"):
		if node.get("playing"):
			return true
	return false


func _new_triangle(z: float) -> Dictionary:
	return {
		"x": randf_range(-4.0, 4.0),
		"y": randf_range(-2.5, 2.5),
		"z": z,
		"size": randf_range(0.3, 0.9),
		"angle": randf() * TAU,
		"spin": randf_range(-1.2, 1.2),
		"red": randf() < 0.06,
	}


func _draw_scene() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var center := size / 2.0
	for t in _triangles:
		var points := PackedVector2Array()
		for corner in 3:
			var a: float = t.angle + corner * TAU / 3.0
			var local: Vector2 = Vector2(cos(a), sin(a)) * float(t.size)
			var perspective: float = FOCAL / t.z
			points.append(center + (Vector2(t.x, t.y) + local) * perspective)
		points.append(points[0])
		var fade := clampf(1.0 - t.z / DEPTH, 0.0, 1.0)
		_canvas.draw_polyline(points, Color(RED if t.red else CYAN, fade), 1.0 + fade)
	_draw_eye(center)


## The eye opens for a few seconds every EYE_EVERY seconds.
func _draw_eye(center: Vector2) -> void:
	var cycle := fmod(_time, EYE_EVERY)
	if cycle > EYE_SECONDS:
		return
	var open := sin(cycle / EYE_SECONDS * PI)
	_canvas.draw_set_transform(center, 0.0, Vector2(1.0, maxf(0.05, open) * 0.5))
	_canvas.draw_circle(Vector2.ZERO, 60.0, Color("cfeff4"))
	_canvas.draw_set_transform(Vector2.ZERO)
	if open > 0.4:
		_canvas.draw_circle(center, 22.0, CYAN)
		_canvas.draw_circle(center, 10.0, Color("02050a"))
