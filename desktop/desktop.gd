extends Control
## Scrivania di AgencyOS: collega icone, finestre, barra, menu Start e fumetti.
## È l'unico punto che conosce tutti i pezzi; i pezzi tra loro si parlano solo con segnali.

const REGISTRY: AppRegistry = preload("res://data/apps/registry.tres")
const TRASH_EMPTY := preload("res://ui/icons/cestino.svg")
const TRASH_FULL := preload("res://ui/icons/cestino_pieno.svg")

@onready var _wallpaper: Wallpaper = $Wallpaper
@onready var _icons: DesktopIcons = $Icons
@onready var _windows: WindowManager = $Windows
@onready var _catcher: Control = %ClickCatcher
@onready var _taskbar: Taskbar = %Taskbar
@onready var _start_menu: StartMenu = %StartMenu
@onready var _balloon: Balloon = %Balloon
@onready var _boot: BootScreen = %Boot
@onready var _saver: ScreenSaver = %Saver


func _ready() -> void:
	_set_fullscreen(bool(Save.get_ui("schermo_intero", false)))
	get_window().size_changed.connect(_on_window_size_changed)
	_wallpaper.set_mode(StringName(Save.get_ui("sfondo", "reticolo")))

	_icons.app_requested.connect(_windows.open)
	_icons.file_requested.connect(func(id: String) -> void: _windows.open(&"note", {"file": id}))
	_icons.populate(REGISTRY)
	var mail := Campaign.correspondence
	mail.files_changed.connect(_refresh_files)
	mail.mail_changed.connect(_refresh_mail_badge)
	mail.delivered.connect(_on_delivered)
	Campaign.trash_changed.connect(_refresh_trash_icon)
	Campaign.agenda_changed.connect(_refresh_next_session)
	_refresh_next_session()
	_refresh_files()
	_refresh_mail_badge()
	_refresh_trash_icon()

	_windows.windows_changed.connect(_on_windows_changed)
	_windows.notification_requested.connect(_show_balloon)
	_windows.command_requested.connect(_on_start_command)
	_windows.restore(REGISTRY)
	Save.ui_changed.connect(_on_ui_changed)

	_taskbar.start_toggled.connect(_set_start_open)
	_taskbar.task_pressed.connect(_on_task_pressed)
	_taskbar.sound_toggled.connect(Sfx.toggle)
	Sfx.settings_changed.connect(_on_sound_changed)
	_on_sound_changed()

	_start_menu.app_chosen.connect(_on_start_app_chosen)
	_start_menu.command_chosen.connect(_on_start_command)
	_catcher.gui_input.connect(_on_catcher_input)
	Caveau.glitch_started.connect(_on_glitch_started)

	_on_windows_changed()
	if bool(Save.get_ui("mostra_avvio", true)):
		_boot.play()
		await _boot.finished
	_show_balloon("AgencyOS 98", "Benvenuto, Manager. La Filiale è operativa.")
	_remind_session_today()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _start_menu.visible:
		_set_start_open(false)
		get_viewport().set_input_as_handled()
	elif _is_fullscreen_shortcut(event):
		_set_fullscreen(not _is_fullscreen())
		get_viewport().set_input_as_handled()


## F11, Cmd+Ctrl+F (la scorciatoia del Mac) oppure Alt+Invio.
func _is_fullscreen_shortcut(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.keycode == KEY_F11 \
		or (key.keycode == KEY_F and key.ctrl_pressed and key.meta_pressed) \
		or (key.keycode in [KEY_ENTER, KEY_KP_ENTER] and key.alt_pressed)


func _is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


func _set_fullscreen(enabled: bool) -> void:
	get_window().mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
	Save.set_ui("schermo_intero", enabled)


## Impostazioni cambiate altrove (es. dal Pannello di controllo).
func _on_ui_changed(key: String) -> void:
	match key:
		"sfondo":
			_wallpaper.set_mode(StringName(Save.get_ui("sfondo", "reticolo")))
		"schermo_intero":
			var wanted := bool(Save.get_ui("schermo_intero", false))
			if wanted != _is_fullscreen():
				_set_fullscreen(wanted)


## Tiene allineata l'impostazione anche quando si usa il pulsante verde del Mac.
func _on_window_size_changed() -> void:
	if bool(Save.get_ui("schermo_intero", false)) != _is_fullscreen():
		Save.set_ui("schermo_intero", _is_fullscreen())


func _set_start_open(open: bool) -> void:
	if open:
		_icons.deselect_all()
		_start_menu.build(REGISTRY, Sfx.enabled, _is_fullscreen())
		_start_menu.open_at(Vector2(4.0, _taskbar.position.y + 2.0))
	else:
		_start_menu.hide()
	_catcher.visible = open
	_taskbar.set_start_open(open)


## action: {"app": id, "args": {...}} da aprire cliccando il fumetto, oppure
## {"cartella": percorso} da aprire nel Finder; vuota = il clic chiude e basta.
func _show_balloon(title: String, text: String, action: Dictionary = {}) -> void:
	var on_click := Callable()
	if action.has("app"):
		on_click = _windows.open.bind(StringName(action.app), action.get("args", {}))
	elif action.has("cartella"):
		on_click = OS.shell_open.bind(str(action.cartella))
	_balloon.show_message(title, text, on_click)


func _on_windows_changed() -> void:
	_taskbar.show_tasks(_windows.entries())


func _on_task_pressed(id: StringName) -> void:
	_set_start_open(false)
	_windows.activate_from_taskbar(id)


func _on_sound_changed() -> void:
	_taskbar.set_sound_enabled(Sfx.enabled)


func _on_catcher_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_set_start_open(false)


func _refresh_files() -> void:
	_icons.set_files(Campaign.correspondence.delivered_files())


func _refresh_next_session() -> void:
	var session := Campaign.next_session()
	if session.is_empty():
		_taskbar.set_next_session("")
		return
	var day := str(session.data)
	_taskbar.set_next_session("Prossima: %s %s %s" % [ItalianDate.weekday_short(day), ItalianDate.numeric(day).left(5), str(session.get("ora", ""))])


## Se la prossima sessione è oggi, dopo il benvenuto ricorda cosa resta da preparare.
func _remind_session_today() -> void:
	var session := Campaign.next_session()
	if session.is_empty() or session.data != ItalianDate.today():
		return
	await get_tree().create_timer(4.0).timeout
	var todo: int = session.checklist.filter(func(item: Dictionary) -> bool: return not item.ok).size()
	var text := ("Alle %s. " % session.ora if str(session.get("ora", "")) != "" else "")
	text += "%d %s da preparare." % [todo, "cosa" if todo == 1 else "cose"] if todo > 0 else "Tutto pronto."
	_show_balloon("Sessione oggi", text, {"app": &"agenda", "args": {"giorno": session.data}})


func _refresh_trash_icon() -> void:
	_icons.set_icon_texture("cestino", TRASH_FULL if not Campaign.trash.is_empty() else TRASH_EMPTY)


func _refresh_mail_badge() -> void:
	_icons.set_badge("amail", Campaign.correspondence.unread_count())


## Un memo o un file è appena arrivato: fumetto cliccabile e reazioni del soggetto.
func _on_delivered(kind: String, item: Dictionary) -> void:
	Sfx.play(&"mail" if kind == "memo" else &"pop")
	if kind == "memo":
		_show_balloon("Nuovo messaggio in AMail", "%s: %s" % [item.mittente, item.oggetto], {"app": &"amail", "args": {"memo": item.id}})
	else:
		_show_balloon("Nuovo file sulla scrivania", "%s · origine sconosciuta" % item.nome, {"app": &"note", "args": {"file": item.id}})
		Caveau.stir(0.45)
		Caveau.glitch("reticolo")


## Glitch che escono dalla finestra della linea e toccano il sistema.
func _on_glitch_started(glitch_name: String) -> void:
	match glitch_name:
		"sabotaggio":
			_taskbar.sabotage()
		"reticolo":
			_wallpaper.pulse()


func _on_start_app_chosen(id: StringName) -> void:
	_set_start_open(false)
	_windows.open(id)


func _on_start_command(command: StringName) -> void:
	_set_start_open(false)
	match command:
		&"suoni":
			Sfx.toggle()
		&"allinea_icone":
			_icons.align()
		&"riordina_finestre":
			_windows.reset_positions()
		&"salvaschermo":
			_saver.start()
		&"azzera":
			_windows.open(&"fascicolo", {"azzera": true})
		&"schermo_intero":
			_set_fullscreen(not _is_fullscreen())
		&"riavvia":
			Save.flush()
			get_tree().reload_current_scene()
		&"spegni":
			Save.flush()
			get_tree().quit()
