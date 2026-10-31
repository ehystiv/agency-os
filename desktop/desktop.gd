extends Control
## The AgencyOS desktop: connects icons, windows, taskbar, Start menu and balloons.
## It's the only place that knows all the pieces; the pieces talk to each other only through signals.

const REGISTRY: AppRegistry = preload("res://data/apps/registry.tres")
const TRASH_EMPTY := preload("res://ui/icons/trash.svg")
const TRASH_FULL := preload("res://ui/icons/trash_full.svg")

@onready var _wallpaper: Wallpaper = $Wallpaper
@onready var _icons: DesktopIcons = $Icons
@onready var _windows: WindowManager = $Windows
@onready var _catcher: Control = %ClickCatcher
@onready var _taskbar: Taskbar = %Taskbar
@onready var _start_menu: StartMenu = %StartMenu
@onready var _balloon: Balloon = %Balloon
@onready var _boot: BootScreen = %Boot
@onready var _saver: ScreenSaver = %Saver

var _jackpot: JackpotOverlay


func _ready() -> void:
	# Before the windows are restored, so they are placed inside the right area.
	ScreenArea.apply(get_window(), ScreenArea.current())
	_set_fullscreen(bool(Save.get_ui("fullscreen", false)))
	get_window().size_changed.connect(_on_window_size_changed)
	_wallpaper.set_mode(StringName(Save.get_ui("wallpaper", "lattice")))

	_icons.app_requested.connect(_windows.open)
	_icons.file_requested.connect(func(id: String) -> void: _windows.open(&"notepad", {"file": id}))
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

	_jackpot = JackpotOverlay.new()
	add_child(_jackpot)

	_start_menu.app_chosen.connect(_on_start_app_chosen)
	_start_menu.command_chosen.connect(_on_start_command)
	_catcher.gui_input.connect(_on_catcher_input)
	Entity.glitch_started.connect(_on_glitch_started)
	Updater.state_changed.connect(_on_update_state)

	_on_windows_changed()
	BootPatch.confirm()
	if bool(Save.get_ui("show_boot", true)):
		_boot.play()
		await _boot.finished
	_show_balloon("AgencyOS 98", "Benvenuto, Manager. La Filiale è operativa.")
	_remind_session_today()
	_announce_patch()
	if bool(Save.get_ui("update_auto", true)):
		# After the other start-up balloons, so they don't cover each other.
		await get_tree().create_timer(8.0).timeout
		Updater.check_daily()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _start_menu.visible:
		_set_start_open(false)
		get_viewport().set_input_as_handled()
	elif _is_fullscreen_shortcut(event):
		_set_fullscreen(not _is_fullscreen())
		get_viewport().set_input_as_handled()


## F11, Cmd+Ctrl+F (the Mac shortcut) or Alt+Enter.
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
	Save.set_ui("fullscreen", enabled)


## Settings changed elsewhere (e.g. from the Control panel).
func _on_ui_changed(key: String) -> void:
	match key:
		"wallpaper":
			_wallpaper.set_mode(StringName(Save.get_ui("wallpaper", "lattice")))
		ScreenArea.PREF:
			ScreenArea.apply(get_window(), ScreenArea.current())
		"fullscreen":
			var wanted := bool(Save.get_ui("fullscreen", false))
			if wanted != _is_fullscreen():
				_set_fullscreen(wanted)


## Keeps the setting in sync even when the Mac's green button is used.
func _on_window_size_changed() -> void:
	if bool(Save.get_ui("fullscreen", false)) != _is_fullscreen():
		Save.set_ui("fullscreen", _is_fullscreen())


func _set_start_open(open: bool) -> void:
	if open:
		_icons.deselect_all()
		_start_menu.build(REGISTRY, Sfx.enabled, _is_fullscreen())
		_start_menu.open_at(Vector2(4.0, _taskbar.position.y + 2.0))
	else:
		_start_menu.hide()
	_catcher.visible = open
	_taskbar.set_start_open(open)


## action: {"app": id, "args": {...}} to open by clicking the balloon, or
## {"folder": path} to open in the Finder; empty = the click just closes it.
func _show_balloon(title: String, text: String, action: Dictionary = {}) -> void:
	var on_click := Callable()
	if action.has("app"):
		on_click = _windows.open.bind(StringName(action.app), action.get("args", {}))
	elif action.has("folder"):
		on_click = OS.shell_open.bind(str(action.folder))
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
	var day := str(session.date)
	_taskbar.set_next_session("Prossima: %s %s %s" % [ItalianDate.weekday_short(day), ItalianDate.numeric(day).left(5), str(session.get("time", ""))])


## If the next session is today, after the welcome it reminds what is left to prepare.
func _remind_session_today() -> void:
	var session := Campaign.next_session()
	if session.is_empty() or session.date != ItalianDate.today():
		return
	await get_tree().create_timer(4.0).timeout
	var todo: int = session.checklist.filter(func(item: Dictionary) -> bool: return not item.done).size()
	var text := ("Alle %s. " % session.time if str(session.get("time", "")) != "" else "")
	text += "%d %s da preparare." % [todo, "cosa" if todo == 1 else "cose"] if todo > 0 else "Tutto pronto."
	_show_balloon("Sessione oggi", text, {"app": &"agenda", "args": {"day": session.date}})


func _refresh_trash_icon() -> void:
	_icons.set_icon_texture("trash", TRASH_FULL if not Campaign.trash.is_empty() else TRASH_EMPTY)


func _refresh_mail_badge() -> void:
	_icons.set_badge("amail", Campaign.correspondence.unread_count())


## A memo or a file just arrived: clickable balloon and the subject's reactions.
func _on_delivered(kind: String, item: Dictionary) -> void:
	Sfx.play(&"mail" if kind == "memo" else &"pop")
	if kind == "memo":
		_show_balloon("Nuovo messaggio in AMail", "%s: %s" % [item.sender, item.subject], {"app": &"amail", "args": {"memo": item.id}})
	else:
		_show_balloon("Nuovo file sulla scrivania", "%s · origine sconosciuta" % item.name, {"app": &"notepad", "args": {"file": item.id}})
		Entity.stir(0.45)
		Entity.glitch("lattice")


## Once per version: the patch just installed, or the one that broke the startup and was undone.
func _announce_patch() -> void:
	var title := ""
	var text := ""
	if BootPatch.failed_version != "" and Save.get_ui("update_failed_seen", "") != BootPatch.failed_version:
		Save.set_ui("update_failed_seen", BootPatch.failed_version)
		title = "Aggiornamento annullato"
		text = "La versione %s non si avviava correttamente: AgencyOS è tornato alla %s." % [BootPatch.failed_version, BootPatch.base_version]
	elif BootPatch.patch_version != "" and Save.get_ui("update_seen", "") != BootPatch.patch_version:
		Save.set_ui("update_seen", BootPatch.patch_version)
		title = "AgencyOS aggiornato"
		text = "Ora è in esecuzione la versione %s." % BootPatch.patch_version
	if title != "":
		await get_tree().create_timer(2.0).timeout
		_show_balloon(title, text)


## Automatic checks only speak up when there's something to do; downloads always do.
func _on_update_state(state: Updater.State) -> void:
	var details := {"app": &"ctrl", "args": {"tab": "update"}}
	match state:
		Updater.State.AVAILABLE when Updater.automatic:
			_show_balloon("Aggiornamento disponibile", "AgencyOS 98 %s è pronto da scaricare. Fare clic per i dettagli." % Updater.manifest.version, details)
		Updater.State.NEEDS_INSTALLER when Updater.automatic:
			_show_balloon("Nuova versione disponibile", "AgencyOS 98 %s richiede il nuovo programma di installazione. Fare clic per i dettagli." % Updater.manifest.version, details)
		Updater.State.READY:
			Sfx.play(&"ding")
			_show_balloon("Aggiornamento scaricato", "Riavviare AgencyOS per completare l'installazione.", details)


## Glitches that leave the line window and touch the system.
func _on_glitch_started(glitch_name: String) -> void:
	match glitch_name:
		"sabotage":
			_taskbar.sabotage()
		"lattice":
			_wallpaper.pulse()


func _on_start_app_chosen(id: StringName) -> void:
	_set_start_open(false)
	_windows.open(id)


func _on_start_command(command: StringName) -> void:
	_set_start_open(false)
	match command:
		&"sounds":
			Sfx.toggle()
		&"align_icons":
			_icons.align()
		&"arrange_windows":
			_windows.reset_positions()
		&"screensaver":
			_saver.start()
		&"jackpot":
			# The burst comes out of the calculator, if it's on screen.
			var calc := _windows.rect_of(&"calc")
			var origin := calc.position + Vector2(calc.size.x / 2.0, 40.0) if calc.has_area() else Vector2(size.x / 2.0, size.y * 0.6)
			_jackpot.play(origin)
		&"reset_branch":
			_windows.open(&"dossier", {"reset": true})
		&"fullscreen":
			_set_fullscreen(not _is_fullscreen())
		&"restart":
			Save.flush()
			get_tree().reload_current_scene()
		&"shutdown":
			Save.flush()
			get_tree().quit()
