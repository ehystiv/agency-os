class_name StartMenu
extends PanelContainer
## Start menu: the installed apps and a few system commands.

signal app_chosen(id: StringName)
## One of &"sounds", &"fullscreen", &"align_icons", &"shortcuts", &"players_toggle",
## &"players_image", &"players_blank", &"restart", &"reset_branch", &"shutdown".
signal command_chosen(command: StringName)

const ICON_SOUND := preload("res://ui/icons/sound.svg")
const ICON_FULLSCREEN := preload("res://ui/icons/fullscreen.svg")
const ICON_ALIGN := preload("res://ui/icons/dossier.svg")
const ICON_RESTART := preload("res://ui/icons/restart.svg")
const ICON_SHUTDOWN := preload("res://ui/icons/shutdown.svg")
const ICON_RESET := preload("res://ui/icons/reset.svg")
const ICON_KEYS := preload("res://ui/icons/keys.svg")
const ICON_PLAYERS := preload("res://ui/icons/players.svg")
const ICON_IMAGE := preload("res://ui/icons/image.svg")
const ICON_BLANK := preload("res://ui/icons/blank.svg")

@onready var _scroll: ScrollContainer = %Scroll
@onready var _items: VBoxContainer = %Items


func build(registry: AppRegistry, sound_enabled: bool, fullscreen: bool, players_open: bool) -> void:
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	for app in registry.start_menu_apps():
		var id := app.id
		_add_item(app.icon, app.label, func() -> void: app_chosen.emit(id))
	_items.add_child(HSeparator.new())
	_add_command(ICON_PLAYERS, "Chiudi lo schermo giocatori" if players_open else "Schermo giocatori (TV)", &"players_toggle")
	_add_command(ICON_IMAGE, "Mostra un'immagine ai giocatori…", &"players_image")
	if players_open:
		_add_command(ICON_BLANK, "Oscura lo schermo giocatori", &"players_blank")
	_items.add_child(HSeparator.new())
	_add_command(ICON_SOUND, "Disattiva i suoni" if sound_enabled else "Attiva i suoni", &"sounds")
	_add_command(ICON_FULLSCREEN, "Esci dallo schermo intero" if fullscreen else "Schermo intero", &"fullscreen")
	_add_command(ICON_ALIGN, "Allinea le icone", &"align_icons")
	_add_command(ICON_KEYS, "Scorciatoie da tastiera", &"shortcuts")
	_add_command(ICON_RESTART, "Riavvia AgencyOS", &"restart")
	_items.add_child(HSeparator.new())
	_add_command(ICON_RESET, "Azzera la Filiale…", &"reset_branch")
	_add_command(ICON_SHUTDOWN, "Spegni il terminale", &"shutdown")


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
	position = bottom_left - Vector2(0.0, size.y)


func _add_command(icon: Texture2D, label: String, command: StringName) -> void:
	_add_item(icon, label, func() -> void: command_chosen.emit(command))


func _add_item(icon: Texture2D, label: String, action: Callable) -> void:
	var button := Button.new()
	button.theme_type_variation = &"StartMenuItem"
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon = icon
	button.text = label
	button.pressed.connect(action)
	_items.add_child(button)
