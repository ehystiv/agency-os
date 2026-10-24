class_name DesktopIcons
extends Control
## Icon grid: snapping to cells, swapping places, saved positions.
## Also receives clicks on the empty desktop, to clear the selection.

signal app_requested(id: StringName)
signal file_requested(id: String)

const FILE_ICON := preload("res://ui/icons/note.svg")
const FILE_PREFIX := "file:"

const ICON_SCENE := preload("res://desktop/icons/desktop_icon.tscn")
const CELL := Vector2(90, 88)
const ORIGIN := Vector2(8, 8)

var _icons: Array[DesktopIcon] = []
var _cells: Dictionary[String, Vector2i] = {}
## After the first list of files, new ones appear with a "pop".
var _populated_files := false


func _ready() -> void:
	resized.connect(_layout)


func populate(registry: AppRegistry) -> void:
	for app in registry.desktop_apps():
		_add_icon(String(app.id), app.label, app.icon)
	_layout()


## Lays out the Entity's file icons: adds the new ones (with a "pop"), updates the read state.
func set_files(files: Array[Dictionary]) -> void:
	var added := false
	for file in files:
		var key := FILE_PREFIX + str(file.id)
		var icon := _find(key)
		if icon == null:
			icon = _add_icon(key, str(file.name), FILE_ICON)
			added = true
			if _populated_files:
				icon.pop.call_deferred()
		icon.set_unread(not file.get("read", false))
	_populated_files = true
	if added:
		_layout()


func set_icon_texture(key: String, texture: Texture2D) -> void:
	var icon := _find(key)
	if icon != null:
		icon.set_texture(texture)


func set_badge(key: String, count: int) -> void:
	var icon := _find(key)
	if icon != null:
		icon.set_badge(count)


func _add_icon(key: String, label: String, texture: Texture2D) -> DesktopIcon:
	var icon: DesktopIcon = ICON_SCENE.instantiate()
	add_child(icon)
	icon.setup(key, label, texture)
	icon.selected.connect(_on_icon_selected)
	icon.activated.connect(_on_icon_activated)
	icon.dropped.connect(_on_icon_dropped)
	_icons.append(icon)
	var cell: Variant = Save.get_ui("icons", {}).get(key)
	if cell is Array and cell.size() == 2:
		_cells[key] = Vector2i(int(cell[0]), int(cell[1]))
	return icon


func _find(key: String) -> DesktopIcon:
	for icon in _icons:
		if icon.key == key:
			return icon
	return null


func _on_icon_activated(icon: DesktopIcon) -> void:
	if icon.key.begins_with(FILE_PREFIX):
		file_requested.emit(icon.key.trim_prefix(FILE_PREFIX))
	else:
		app_requested.emit(StringName(icon.key))


## Brings every icon back into a column, in registry order.
func align() -> void:
	_cells.clear()
	_layout()
	_store()


func deselect_all() -> void:
	for icon in _icons:
		icon.is_selected = false


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		deselect_all()


func _grid_size() -> Vector2i:
	return Vector2i(
		maxi(1, floori((size.x - ORIGIN.x) / CELL.x)),
		maxi(1, floori((size.y - ORIGIN.y) / CELL.y)))


## Keeps valid and free cells, fills the others in a column from the top left.
## Saved cells aren't rewritten: if the window gets wider they go back in place.
func _layout() -> void:
	if _icons.is_empty():
		return
	var grid := _grid_size()
	var placed: Dictionary[String, Vector2i] = {}
	var used: Dictionary[Vector2i, bool] = {}
	for icon in _icons:
		if not _cells.has(icon.key):
			continue
		var cell := _cells[icon.key]
		if cell.x < grid.x and cell.y < grid.y and not used.has(cell):
			placed[icon.key] = cell
			used[cell] = true
	var slot := 0
	for icon in _icons:
		if placed.has(icon.key):
			continue
		var cell := Vector2i(slot / grid.y, slot % grid.y)
		while used.has(cell):
			slot += 1
			cell = Vector2i(slot / grid.y, slot % grid.y)
		placed[icon.key] = cell
		used[cell] = true
	for icon in _icons:
		var offset := Vector2((CELL.x - icon.size.x) / 2.0, 0.0)
		icon.position = (ORIGIN + Vector2(placed[icon.key]) * CELL + offset).round()
		if not _cells.has(icon.key):
			_cells[icon.key] = placed[icon.key]


func _on_icon_selected(icon: DesktopIcon) -> void:
	for other in _icons:
		other.is_selected = other == icon


func _on_icon_dropped(icon: DesktopIcon) -> void:
	var grid := _grid_size()
	var raw := ((icon.position - ORIGIN) / CELL).round()
	var cell := Vector2i(raw).clamp(Vector2i.ZERO, grid - Vector2i.ONE)
	var old_cell := _cells[icon.key]
	for other in _icons:
		if other != icon and _cells.get(other.key) == cell:
			_cells[other.key] = old_cell
	_cells[icon.key] = cell
	_layout()
	_store()


func _store() -> void:
	var data := {}
	for key in _cells:
		data[key] = [_cells[key].x, _cells[key].y]
	Save.set_ui("icons", data)
