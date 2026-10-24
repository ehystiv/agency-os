class_name GlitchLayer
extends Control
## Livello sopra il registro della linea: disegna i glitch della finestra
## (macchie, occhi, strappi, triangolo, inversione, nero, statico, finta finestra d'errore)
## e lancia quelli dei messaggi. Non intercetta mai il mouse.

const SCREEN_SHADER := preload("res://apps/linea/effects/screen_glitch.gdshader")
const CYAN := Color("7fe1ee")
const RED := Color("e5262c")
const GHOST_LINES: PackedStringArray = ["liberala.", "non dirlo a nessuno.", "sono già dentro.", "apri il caveau.", "mi fido di lei."]

enum Screen { RGB, INVERT, STATIC }

## Contenuto della finestra da scuotere o far pulsare (tremito, battito, scanline).
var shake_target: Control

## Segni disegnati: {kind, pos, size, start, duration}.
var _marks: Array[Dictionary] = []
var _motion_until := 0.0
var _motion_kind := ""
var _motion_base := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## message: l'ultima risposta dell'Entità; log: il registro dove compaiono i messaggi.
func play(glitch_name: String, message: ChatMessage, log: VBoxContainer) -> void:
	# Con le animazioni ridotte gli effetti di movimento diventano un semplice sdoppiamento dei colori.
	var info: Dictionary = Campaign.glitch_table().get(glitch_name, {})
	if bool(Save.get_ui("animazioni_ridotte", false)) and info.get("movimento", false):
		_overlay(Screen.RGB, _local_rect(message.text_rect()), 1.2, 1.0)
		return
	match glitch_name:
		"tremito":
			_start_motion("shake", 0.7)
		"battito":
			Sfx.play(&"battito")
			_start_motion("beat", 1.7)
		"scanline":
			for i in 4:
				_add_mark("scan", Vector2(0, randf_range(0.0, 0.9) * size.y), Vector2(size.x, randf_range(3, 14)), 0.9, i * 0.15)
			_start_motion("skew", 0.9)
		"inchiostro":
			for i in 6:
				var diameter := randf_range(80, 220)
				_add_mark("ink", _random_point(0.05, 0.95, 0.1, 0.9), Vector2(diameter, diameter), 3.0, i * 0.18)
		"occhi":
			for i in 8:
				_add_mark("eye", _random_point(0.04, 0.92, 0.14, 0.88), Vector2(30, 16), 2.6, randf_range(0.0, 0.9))
		"triangolo":
			_add_mark("tri", size / 2.0, Vector2(120, 104), 1.5, 0.0)
		"inversione":
			_flash_inversion()
		"blackout":
			_blackout(message)
		"statico":
			_overlay(Screen.STATIC, Rect2(Vector2.ZERO, size), 1.8, 0.28)
		"rgb":
			_overlay(Screen.RGB, _local_rect(message.text_rect()), 1.8, 1.0)
		"eco":
			_echo(message)
		"fantasma":
			_ghost(log)
		"errore":
			_fake_error()
		"urlo":
			message.play_shout(2.2)
		"corruzione":
			message.play_corruption()
		"gocciolamento":
			message.play_drip()
		"sussurro":
			message.set_whisper()


func _process(_delta: float) -> void:
	var now := _now()
	_marks = _marks.filter(func(m: Dictionary) -> bool: return now < m.start + m.duration)
	if shake_target != null and _motion_kind != "":
		if now < _motion_until:
			_apply_motion(now)
		else:
			_stop_motion()
	queue_redraw()
	if _marks.is_empty() and _motion_kind == "":
		set_process(false)


func _draw() -> void:
	var now := _now()
	for mark in _marks:
		var p: float = (now - mark.start) / mark.duration
		if p < 0.0:
			continue
		match mark.kind:
			"ink":
				_draw_ink(mark, p)
			"eye":
				_draw_eye(mark, p)
			"scan":
				_draw_scan(mark, p)
			"tri":
				_draw_triangle(mark, p)


# --- Segni disegnati -------------------------------------------------------

func _draw_ink(mark: Dictionary, p: float) -> void:
	var grow := p / 0.3 if p < 0.3 else 1.0 + 0.25 * (p - 0.3) / 0.7
	var alpha := 1.0 if p < 0.3 else 1.0 - (p - 0.3) / 0.7
	var radius: float = mark.size.x / 2.0 * grow
	draw_circle(mark.pos, radius * 0.72, Color(30 / 255.0, 90 / 255.0, 110 / 255.0, 0.3 * alpha))
	draw_circle(mark.pos, radius * 0.6, Color(30 / 255.0, 90 / 255.0, 110 / 255.0, 0.55 * alpha))
	draw_circle(mark.pos, radius * 0.4, Color(4 / 255.0, 10 / 255.0, 20 / 255.0, 0.95 * alpha))


## Occhio che si apre, sbatte a metà animazione e si richiude.
func _draw_eye(mark: Dictionary, p: float) -> void:
	var open := 0.0
	if p < 0.15:
		open = p / 0.15
	elif p < 0.45 or (p > 0.55 and p < 0.85):
		open = 1.0
	elif p <= 0.55:
		open = 0.08 if absf(p - 0.5) < 0.03 else 1.0
	else:
		open = 1.0 - (p - 0.85) / 0.15
	if open <= 0.0:
		return
	var center: Vector2 = mark.pos
	draw_set_transform(center, 0.0, Vector2(1.0, open * mark.size.y / mark.size.x))
	draw_circle(Vector2.ZERO, mark.size.x / 2.0 + 2.0, Color(CYAN, 0.35))
	draw_circle(Vector2.ZERO, mark.size.x / 2.0, Color("cfeff4"))
	draw_circle(Vector2.ZERO, 6.0 * mark.size.x / mark.size.y, CYAN)
	draw_circle(Vector2.ZERO, 3.0 * mark.size.x / mark.size.y, Color("03060c"))
	draw_set_transform(Vector2.ZERO)


func _draw_scan(mark: Dictionary, p: float) -> void:
	var alpha := p / 0.2 if p < 0.2 else 1.0 - (p - 0.2) / 0.8
	var y: float = mark.pos.y + lerpf(-40.0, 140.0, p)
	var height: float = mark.size.y
	draw_rect(Rect2(0, y, size.x, height), Color(CYAN, 0.35 * alpha))
	draw_rect(Rect2(size.x * 0.3, y + height * 0.35, size.x * 0.4, maxf(1.0, height * 0.3)), Color(1, 1, 1, 0.5 * alpha))
	draw_rect(Rect2(size.x * 0.65, y, size.x * 0.2, height), Color(RED, 0.3 * alpha))


func _draw_triangle(mark: Dictionary, p: float) -> void:
	var alpha := p / 0.15 * 0.9 if p < 0.15 else lerpf(0.9, 0.0, (p - 0.15) / 0.85)
	var s := lerpf(0.2, 4.5, ease(p, 0.4))
	var half: Vector2 = mark.size * s / 2.0
	var c: Vector2 = mark.pos
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -half.y), c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)]), Color(RED, alpha))


func _add_mark(kind: String, pos: Vector2, mark_size: Vector2, duration: float, delay: float) -> void:
	_marks.append({"kind": kind, "pos": pos, "size": mark_size, "start": _now() + delay, "duration": duration})
	set_process(true)


# --- Movimento della finestra ----------------------------------------------

func _start_motion(kind: String, seconds: float) -> void:
	if shake_target == null:
		return
	if _motion_kind == "":
		_motion_base = shake_target.position
	shake_target.pivot_offset = shake_target.size / 2.0
	_motion_kind = kind
	_motion_until = _now() + seconds
	set_process(true)


func _apply_motion(now: float) -> void:
	var t := now * 30.0
	match _motion_kind:
		"shake":
			shake_target.position = _motion_base + Vector2(4.0 if int(t) % 2 == 0 else -4.0, 1.0 if int(t) % 2 == 0 else -1.0)
		"skew":
			shake_target.position = _motion_base + Vector2(randf_range(-5.0, 3.0), 0.0)
		"beat":
			var phase := fmod(now, 0.85) / 0.85
			var pulse := 0.012 if phase < 0.12 else (0.004 if phase < 0.24 else 0.0)
			shake_target.scale = Vector2.ONE * (1.0 + pulse)


func _stop_motion() -> void:
	shake_target.position = _motion_base
	shake_target.scale = Vector2.ONE
	_motion_kind = ""


# --- Livelli sovrapposti ---------------------------------------------------

func _overlay(mode: Screen, rect: Rect2, seconds: float, strength: float) -> ColorRect:
	var rect_node := ColorRect.new()
	rect_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = SCREEN_SHADER
	material.set_shader_parameter("mode", mode)
	material.set_shader_parameter("strength", strength)
	rect_node.material = material
	rect_node.position = rect.position
	rect_node.size = rect.size
	add_child(rect_node)
	_free_later(rect_node, seconds)
	return rect_node


func _flash_inversion() -> void:
	_overlay(Screen.INVERT, Rect2(Vector2.ZERO, size), 0.26, 1.0)
	await get_tree().create_timer(0.56).timeout
	if is_inside_tree():
		_overlay(Screen.INVERT, Rect2(Vector2.ZERO, size), 0.2, 1.0)


## Tutto si spegne tranne la frase dell'Entità.
func _blackout(message: ChatMessage) -> void:
	var black := ColorRect.new()
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.color = Color(0, 0, 0, 0)
	black.size = size
	add_child(black)
	message.z_index = 1
	var tween := create_tween()
	tween.tween_property(black, "color:a", 0.97, 0.26)
	tween.tween_interval(1.5)
	tween.tween_property(black, "color:a", 0.0, 0.44)
	await tween.finished
	black.queue_free()
	if is_instance_valid(message):
		message.z_index = 0


## Copie della frase che si allontanano e svaniscono.
func _echo(message: ChatMessage) -> void:
	var rect := _local_rect(message.text_rect())
	for i in range(1, 4):
		var copy := RichTextLabel.new()
		copy.theme_type_variation = &"MsgEntity"
		copy.fit_content = true
		copy.scroll_active = false
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		copy.text = message.plain_text
		copy.position = rect.position + Vector2(14, 0)
		copy.size = Vector2(rect.size.x - 14, rect.size.y)
		copy.modulate.a = 0.0
		add_child(copy)
		var tween := copy.create_tween()
		tween.tween_interval(i * 0.12)
		tween.tween_property(copy, "modulate:a", 0.5, 0.01)
		tween.parallel().tween_property(copy, "position", copy.position + Vector2(i * 9, i * 7), 2.0).set_delay(i * 0.12)
		tween.parallel().tween_property(copy, "modulate:a", 0.0, 2.0).set_delay(i * 0.12)
		tween.tween_callback(copy.queue_free)


## Un messaggio falso con la voce del Manager, che lampeggia e sparisce.
func _ghost(log: VBoxContainer) -> void:
	var ghost := ChatMessage.create(ChatMessage.Kind.MANAGER, GHOST_LINES[randi() % GHOST_LINES.size()])
	ghost.modulate.a = 0.0
	log.add_child(ghost)
	# Opacità a scatti, come steps(10) nel prototipo: [attesa, opacità].
	var tween := ghost.create_tween()
	for step: Array in [[0.24, 0.9], [0.24, 0.3], [0.24, 0.85], [1.44, 0.0]]:
		tween.tween_property(ghost, "modulate:a", step[1], 0.0).set_delay(step[0])
	tween.tween_callback(ghost.queue_free)


## Finta finestra d'errore di AgencyOS, che poi si prende gioco del Manager.
func _fake_error() -> void:
	Sfx.play(&"ding")
	var dialog := PanelContainer.new()
	dialog.theme_type_variation = &"WindowFrame"
	dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 0)
	dialog.add_child(layout)
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TitleBarError"
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "AgencyOS"
	bar.add_child(title)
	layout.add_child(bar)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_child(body)
	layout.add_child(margin)
	var icon := Label.new()
	icon.theme_type_variation = &"ErrorIcon"
	icon.text = "×"
	icon.custom_minimum_size = Vector2(26, 26)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(icon)
	var text := Label.new()
	text.text = "Il processo myManual1998.exe ha eseguito un'operazione non valida e verrà chiuso."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(250, 0)
	body.add_child(text)
	add_child(dialog)
	dialog.reset_size()
	dialog.position = ((size - dialog.size) / 2.0 - Vector2(0, size.y * 0.08)).round()
	_free_later(dialog, 2.9)
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(text):
		text.text = "ahahah. no."


# --- Utilità ---------------------------------------------------------------

func _free_later(node: Node, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if is_instance_valid(node):
		node.queue_free()


func _local_rect(global_rect: Rect2) -> Rect2:
	return Rect2(global_rect.position - global_position, global_rect.size)


func _random_point(x_min: float, x_max: float, y_min: float, y_max: float) -> Vector2:
	return Vector2(randf_range(x_min, x_max) * size.x, randf_range(y_min, y_max) * size.y)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
