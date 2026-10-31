class_name StartMenu
extends PanelContainer
## Start menu: Programmi and Impostazioni (submenus opening on the right, as in Windows 98),
## then the players' screen, Help, Run and the system commands.

signal app_chosen(id: StringName)
## One of &"sounds", &"fullscreen", &"align_icons" (in Impostazioni), &"shortcuts", &"players_toggle",
## &"players_image", &"players_blank", &"run", &"reset_branch", &"shutdown" (the Shut Down dialog).
signal command_chosen(command: StringName)

const ICON_SOUND := preload("res://ui/icons/sound.svg")
const ICON_FULLSCREEN := preload("res://ui/icons/fullscreen.svg")
const ICON_ALIGN := preload("res://ui/icons/dossier.svg")
const ICON_SHUTDOWN := preload("res://ui/icons/shutdown.svg")
const ICON_RESET := preload("res://ui/icons/reset.svg")
const ICON_KEYS := preload("res://ui/icons/keys.svg")
const ICON_PLAYERS := preload("res://ui/icons/players.svg")
const ICON_IMAGE := preload("res://ui/icons/image.svg")
const ICON_BLANK := preload("res://ui/icons/blank.svg")
const ICON_RUN := preload("res://ui/icons/run.svg")

const SLIDE_SECONDS := 0.14
const ICON_PROGRAMS := preload("res://ui/icons/programs.svg")
const ICON_SETTINGS := preload("res://ui/icons/ctrl.svg")
const MENU_ARROW := preload("res://desktop/start_menu/menu_arrow.gd")

var _slide: Tween
## The submenu of Programmi or Impostazioni, and the item it belongs to.
var _folder: PanelContainer
var _folder_items: VBoxContainer
var _open_button: Button

@onready var _scroll: ScrollContainer = %Scroll
@onready var _items: VBoxContainer = %Items


func _ready() -> void:
	_folder = PanelContainer.new()
	_folder.theme_type_variation = &"StartMenuPanel"
	# Outside the menu's layout, so it can stand to its right.
	_folder.top_level = true
	_folder.hide()
	_folder_items = VBoxContainer.new()
	_folder_items.add_theme_constant_override(&"separation", 0)
	_folder_items.custom_minimum_size.x = 190.0
	_folder.add_child(_folder_items)
	add_child(_folder)


func build(registry: AppRegistry, sound_enabled: bool, fullscreen: bool, players_open: bool) -> void:
	_close_folder()
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	var programs: Array = []
	for app in registry.start_folder_apps(&"programs"):
		programs.append(_app_entry(app))
	var settings: Array = []
	for app in registry.start_folder_apps(&"settings"):
		settings.append(_app_entry(app))
	settings.append([])
	settings.append([ICON_SOUND, "Disattiva i suoni" if sound_enabled else "Attiva i suoni", _command(&"sounds")])
	settings.append([ICON_FULLSCREEN, "Esci dallo schermo intero" if fullscreen else "Schermo intero", _command(&"fullscreen")])
	settings.append([ICON_ALIGN, "Allinea le icone", _command(&"align_icons")])
	_add_folder(ICON_PROGRAMS, "Programmi", programs)
	_add_folder(ICON_SETTINGS, "Impostazioni", settings)
	_items.add_child(HSeparator.new())
	_add_command(ICON_PLAYERS, "Chiudi lo schermo giocatori" if players_open else "Schermo giocatori (TV)", &"players_toggle")
	_add_command(ICON_IMAGE, "Mostra un'immagine ai giocatori…", &"players_image")
	if players_open:
		_add_command(ICON_BLANK, "Oscura lo schermo giocatori", &"players_blank")
	_items.add_child(HSeparator.new())
	for app in registry.start_folder_apps(&""):
		var entry := _app_entry(app)
		_add_item(_items, entry[0], entry[1], entry[2])
	_add_command(ICON_KEYS, "Scorciatoie da tastiera", &"shortcuts")
	_add_command(ICON_RUN, "Esegui…", &"run")
	_items.add_child(HSeparator.new())
	_add_command(ICON_RESET, "Azzera la Filiale…", &"reset_branch")
	_add_command(ICON_SHUTDOWN, "Chiudi sessione…", &"shutdown")


## Opens the menu with its bottom left corner at bottom_left.
## If the items don't fit above the taskbar, the list scrolls.
func open_at(bottom_left: Vector2) -> void:
	show()
	var frame := get_theme_stylebox("panel").get_minimum_size().y
	var available := bottom_left.y - frame - 4.0
	var needed := _items.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = minf(needed, available)
	_scroll.custom_minimum_size.x = _items.get_combined_minimum_size().x + (_scroll.get_v_scroll_bar().get_combined_minimum_size().x if needed > available else 0.0)
	reset_size()
	# It slides up from behind the taskbar (drawn after it), as in Windows 98.
	var final := bottom_left - Vector2(0.0, size.y)
	position = final + Vector2(0.0, size.y)
	if _slide != null:
		_slide.kill()
	_slide = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_slide.tween_property(self, "position", final, SLIDE_SECONDS)


func _app_entry(app: AppInfo) -> Array:
	var id := app.id
	return [app.icon, tr(app.label), func() -> void: app_chosen.emit(id)]


func _command(command: StringName) -> Callable:
	return func() -> void: command_chosen.emit(command)


func _add_command(icon: Texture2D, label: String, command: StringName) -> void:
	_add_item(_items, icon, label, _command(command))


func _add_item(box: VBoxContainer, icon: Texture2D, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"StartMenuItem"
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = icon
	button.text = tr(label)
	button.pressed.connect(action)
	box.add_child(button)
	if box == _items:
		# Like Windows: pointing at another item of the menu closes the open folder.
		button.mouse_entered.connect(_close_folder)
	return button


## An item that opens a submenu on its right, when pointed at or clicked.
## entries: [icon, label, action] or [] for a separator.
func _add_folder(icon: Texture2D, label: String, entries: Array) -> void:
	var button := Button.new()
	button.theme_type_variation = &"StartMenuItem"
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.icon = icon
	button.text = tr(label)
	var arrow := Control.new()
	arrow.set_script(MENU_ARROW)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	arrow.offset_left = -18.0
	button.add_child(arrow)
	_items.add_child(button)
	button.mouse_entered.connect(func() -> void: _open_folder(button, entries))
	button.pressed.connect(func() -> void: _open_folder(button, entries))


func _open_folder(button: Button, entries: Array) -> void:
	if _open_button == button:
		button.set_pressed_no_signal(true)
		return
	_close_folder()
	_open_button = button
	button.set_pressed_no_signal(true)
	for entry: Array in entries:
		if entry.is_empty():
			_folder_items.add_child(HSeparator.new())
		else:
			_add_item(_folder_items, entry[0], entry[1], entry[2])
	_folder.reset_size()
	_folder.show()
	# Next to the item, its first entry level with it; never below the menu's bottom.
	var frame := _folder.get_theme_stylebox("panel").get_margin(SIDE_TOP)
	var bottom := get_global_rect().end.y
	var top := minf(button.global_position.y - frame, bottom - _folder.size.y)
	_folder.global_position = Vector2(get_global_rect().end.x - 3.0, maxf(0.0, top))


func _close_folder() -> void:
	if _open_button != null and is_instance_valid(_open_button):
		_open_button.set_pressed_no_signal(false)
	_open_button = null
	_folder.hide()
	for child in _folder_items.get_children():
		_folder_items.remove_child(child)
		child.queue_free()
