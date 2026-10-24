class_name StartMenu
extends PanelContainer
## Menu Start: le app installate e qualche comando di sistema.

signal app_chosen(id: StringName)
## Uno tra &"suoni", &"schermo_intero", &"allinea_icone", &"riavvia", &"azzera", &"spegni".
signal command_chosen(command: StringName)

const ICON_SOUND := preload("res://ui/icons/suono.svg")
const ICON_FULLSCREEN := preload("res://ui/icons/schermo.svg")
const ICON_ALIGN := preload("res://ui/icons/fascicolo.svg")
const ICON_RESTART := preload("res://ui/icons/riavvia.svg")
const ICON_SHUTDOWN := preload("res://ui/icons/spegni.svg")
const ICON_RESET := preload("res://ui/icons/reset.svg")

@onready var _scroll: ScrollContainer = %Scroll
@onready var _items: VBoxContainer = %Items


func build(registry: AppRegistry, sound_enabled: bool, fullscreen: bool) -> void:
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	for app in registry.start_menu_apps():
		var id := app.id
		_add_item(app.icon, app.label, func() -> void: app_chosen.emit(id))
	_items.add_child(HSeparator.new())
	_add_command(ICON_SOUND, "Disattiva i suoni" if sound_enabled else "Attiva i suoni", &"suoni")
	_add_command(ICON_FULLSCREEN, "Esci dallo schermo intero" if fullscreen else "Schermo intero", &"schermo_intero")
	_add_command(ICON_ALIGN, "Allinea le icone", &"allinea_icone")
	_add_command(ICON_RESTART, "Riavvia AgencyOS", &"riavvia")
	_items.add_child(HSeparator.new())
	_add_command(ICON_RESET, "Azzera la Filiale…", &"azzera")
	_add_command(ICON_SHUTDOWN, "Spegni il terminale", &"spegni")


## Apre il menu con l'angolo in basso a sinistra in bottom_left.
## Se le voci non ci stanno sopra la barra, l'elenco scorre.
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
