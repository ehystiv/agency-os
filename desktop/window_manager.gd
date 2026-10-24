class_name WindowManager
extends Control
## Apre, ordina e ricorda le finestre delle app. Non conosce barra né icone:
## chi vuole sapere cosa è aperto ascolta windows_changed e chiede entries().
## Una finestra chiusa viene solo nascosta: l'app conserva il suo stato e i lavori in corso.

signal windows_changed
signal notification_requested(title: String, text: String, action: Dictionary)
signal command_requested(command: StringName)

const WINDOW_SCENE := preload("res://windows/app_window.tscn")

var _registry: AppRegistry
## Tutte le finestre create, aperte o chiuse.
var _windows: Dictionary[StringName, AppWindow] = {}
## Finestre aperte (anche ridotte): sono quelle nella barra delle applicazioni.
var _open: Dictionary[StringName, bool] = {}


func _ready() -> void:
	resized.connect(_on_resized)


## Riapre le finestre della volta scorsa, oppure quelle predefinite al primo avvio.
func restore(registry: AppRegistry) -> void:
	_registry = registry
	if not Save.has_ui("ordine_finestre"):
		var first: AppWindow = null
		for app in registry.apps:
			if app.open_at_first_start:
				open(app.id)
				first = _windows[app.id] if first == null else first
		# La prima app del registro resta in primo piano.
		if first != null:
			focus(first)
		return
	var states: Dictionary = Save.get_ui("finestre", {})
	for id: String in Save.get_ui("ordine_finestre", []):
		if _registry.find(StringName(id)) == null:
			continue
		var window := _get_or_create(StringName(id))
		_open[StringName(id)] = true
		var state: Dictionary = states.get(id, {})
		window.visible = not bool(state.get("ridotta", false))
		if window.visible:
			window.content.on_opened()
	_refresh_active()
	windows_changed.emit()


func open(id: StringName, args: Dictionary = {}) -> void:
	var window := _get_or_create(id)
	if window == null:
		return
	_open[id] = true
	window.show()
	window.content.on_opened(args)
	focus(window)
	_store()


func focus(window: AppWindow) -> void:
	if window.get_index() != get_child_count() - 1:
		move_child(window, -1)
		_store()
	if not window.active:
		_refresh_active()
		windows_changed.emit()


func minimize(window: AppWindow) -> void:
	window.hide()
	_refresh_active()
	_store()
	windows_changed.emit()


func close(window: AppWindow) -> void:
	window.content.on_closed()
	_open.erase(window.app.id)
	window.hide()
	_refresh_active()
	_store()
	windows_changed.emit()


## Comportamento dei pulsanti della barra: riapre, porta davanti o riduce.
func activate_from_taskbar(id: StringName) -> void:
	var window: AppWindow = _windows.get(id)
	if window == null or not _open.has(id) or not window.visible:
		open(id)
	elif window.active:
		minimize(window)
	else:
		focus(window)


## Finestre aperte nell'ordine del registro, per la barra delle applicazioni.
func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for app in _registry.apps:
		var window: AppWindow = _windows.get(app.id)
		if window != null and _open.has(app.id):
			result.append({"id": app.id, "label": app.label, "icon": app.icon, "active": window.active and window.visible})
	return result


func _get_or_create(id: StringName) -> AppWindow:
	if _windows.has(id):
		return _windows[id]
	var info := _registry.find(id)
	if info == null or info.scene == null:
		push_warning("WindowManager: nessuna app con id '%s' (o senza scena)." % id)
		return null
	var window: AppWindow = WINDOW_SCENE.instantiate()
	add_child(window)
	window.setup(info, info.scene.instantiate() as AppContent)
	window.position = window.clamp_position(_saved_position(info, window))
	window.focus_requested.connect(focus)
	window.minimize_requested.connect(minimize)
	window.close_requested.connect(close)
	window.reset_requested.connect(_on_reset_requested)
	window.moved.connect(func(_w: AppWindow) -> void: _store())
	window.notification_requested.connect(notification_requested.emit)
	window.app_requested.connect(open)
	window.command_requested.connect(command_requested.emit)
	_windows[id] = window
	return window


func _saved_position(info: AppInfo, window: AppWindow) -> Vector2:
	var state: Dictionary = Save.get_ui("finestre", {}).get(String(info.id), {})
	if state.has("x") and state.has("y"):
		return Vector2(float(state.x), float(state.y))
	return _default_position(info, window)


func _default_position(info: AppInfo, window: AppWindow) -> Vector2:
	var pos := Vector2(info.default_position)
	if info.default_position.x < 0:
		pos.x = (size.x - window.size.x) / 2.0
	if info.default_position.y < 0:
		pos.y = (size.y - window.size.y) / 2.0
	return pos


## Riporta tutte le finestre alla posizione predefinita.
func reset_positions() -> void:
	for window: AppWindow in _windows.values():
		window.position = window.clamp_position(_default_position(window.app, window))
	_store()


func _on_reset_requested(window: AppWindow) -> void:
	window.position = window.clamp_position(_default_position(window.app, window))
	_store()


func _on_resized() -> void:
	for window: AppWindow in _windows.values():
		window.position = window.clamp_position(window.position)


func _refresh_active() -> void:
	var top: AppWindow = null
	for i in range(get_child_count() - 1, -1, -1):
		var candidate := get_child(i) as AppWindow
		if candidate != null and candidate.visible:
			top = candidate
			break
	for window: AppWindow in _windows.values():
		window.active = window == top


## Ricorda posizione e stato di ogni finestra, anche di quelle chiuse.
func _store() -> void:
	var states: Dictionary = Save.get_ui("finestre", {}).duplicate()
	var order: Array[String] = []
	for child in get_children():
		var window := child as AppWindow
		if window == null:
			continue
		var id := String(window.app.id)
		if _open.has(window.app.id):
			order.append(id)
		states[id] = {"x": int(window.position.x), "y": int(window.position.y), "ridotta": not window.visible}
	Save.set_ui("finestre", states)
	Save.set_ui("ordine_finestre", order)
