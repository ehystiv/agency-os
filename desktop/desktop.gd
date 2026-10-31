extends Control
## The AgencyOS desktop: connects icons, windows, taskbar, Start menu and balloons.
## It's the only place that knows all the pieces; the pieces talk to each other only through signals.

const REGISTRY: AppRegistry = preload("res://data/apps/registry.tres")
const TRASH_EMPTY := preload("res://ui/icons/trash.svg")
const TRASH_FULL := preload("res://ui/icons/trash_full.svg")
## Arrow with an hourglass, as Windows 98 "working in background".
const BUSY_CURSOR := preload("res://ui/icons/cursor_busy.svg")
const ZOOM_SECONDS := 0.2
const CAPTION_HEIGHT := 24.0

@onready var _wallpaper: Wallpaper = $Wallpaper
@onready var _icons: DesktopIcons = $Icons
@onready var _windows: WindowManager = $Windows
@onready var _catcher: Control = %ClickCatcher
@onready var _taskbar: Taskbar = %Taskbar
@onready var _start_menu: StartMenu = %StartMenu
@onready var _balloon: Balloon = %Balloon
@onready var _boot: BootScreen = %Boot
@onready var _saver: ScreenSaver = %Saver
@onready var _shutdown: ShutdownDialog = %Shutdown

var _jackpot: JackpotOverlay
var _players: PlayerScreen
## Right-click menu, shared by desktop, icons and taskbar.
var _context := PopupMenu.new()
var _context_actions: Array[Callable] = []


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
	_windows.window_minimized.connect(func(window: AppWindow) -> void:
		_zoom(_caption_rect(window), _taskbar.task_rect(window.app.id)))
	_windows.window_restored.connect(func(window: AppWindow) -> void:
		_zoom(_taskbar.task_rect(window.app.id), _caption_rect(window)))
	_windows.notification_requested.connect(_show_balloon)
	_windows.command_requested.connect(_on_start_command)
	_windows.restore(REGISTRY)
	Save.ui_changed.connect(_on_ui_changed)

	_taskbar.start_toggled.connect(_set_start_open)
	_taskbar.task_pressed.connect(_on_task_pressed)
	_taskbar.quick_launch_pressed.connect(_on_start_app_chosen)
	_taskbar.context_requested.connect(_on_taskbar_context)
	_icons.context_requested.connect(_on_icons_context)
	add_child(_context)
	_context.id_pressed.connect(func(id: int) -> void: _context_actions[id].call())
	_taskbar.show_desktop_pressed.connect(func() -> void:
		_set_start_open(false)
		_windows.toggle_desktop())
	var quick: Array[Dictionary] = []
	for app in REGISTRY.quick_launch_apps():
		quick.append({"id": app.id, "label": tr(app.label), "icon": app.icon})
	_taskbar.set_quick_launch(quick)
	_taskbar.sound_toggled.connect(Sfx.toggle)
	_taskbar.volume_changed.connect(func(value: float) -> void: Sfx.volume = value)
	Sfx.settings_changed.connect(_on_sound_changed)
	_on_sound_changed()

	_jackpot = JackpotOverlay.new()
	add_child(_jackpot)
	_players = PlayerScreen.new()
	add_child(_players)
	_windows.present_requested.connect(_players.present)
	if bool(Save.get_ui(PlayerScreen.PREF, {}).get("open", false)):
		_players.set_open(true)

	_start_menu.app_chosen.connect(_on_start_app_chosen)
	_start_menu.command_chosen.connect(_on_start_command)
	_shutdown.confirmed.connect(func(restart: bool) -> void:
		_on_start_command(&"restart" if restart else &"quit"))
	_catcher.gui_input.connect(_on_catcher_input)
	Entity.glitch_started.connect(_on_glitch_started)
	Updater.state_changed.connect(_on_update_state)
	Brain.busy_changed.connect(func(busy: bool) -> void:
		Input.set_custom_mouse_cursor(BUSY_CURSOR if busy else null, Input.CURSOR_ARROW, Vector2(1, 1)))

	_on_windows_changed()
	BootPatch.confirm()
	if bool(Save.get_ui("show_boot", true)):
		_boot.play()
		await _boot.finished
	# The Welcome screen: the first time, then only if the Manager asked for it.
	if bool(Save.get_ui("welcome_at_start", true)):
		Save.set_ui("welcome_at_start", Save.get_ui("welcome_at_start", false))
		_windows.open(&"welcome")
	_show_balloon("AgencyOS 98", tr("Benvenuto, Manager. La Filiale è operativa."))
	_remind_session_today()
	_announce_patch()
	if bool(Save.get_ui("update_auto", true)):
		# After the other start-up balloons, so they don't cover each other.
		await get_tree().create_timer(8.0).timeout
		Updater.check_daily()


## Global shortcuts, before the focused field sees the keys (Cmd on a Mac, Ctrl elsewhere):
## Cmd+W closes, Cmd+M minimizes, Ctrl+Tab / Cmd+` switch window (Shift = backwards),
## Cmd+1…9 open the Start menu's apps, Cmd+D shows the desktop, Cmd+R opens Esegui.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or _boot.is_running() or _saver.active:
		return
	var command := key.is_command_or_control_pressed()
	var active := _windows.active_window()
	var handled := true
	if (key.keycode == KEY_TAB and key.ctrl_pressed) or (key.keycode == KEY_QUOTELEFT and command):
		_windows.cycle(-1 if key.shift_pressed else 1)
	elif not command or key.alt_pressed or key.echo:
		handled = false
	elif key.keycode == KEY_W and active != null:
		_windows.close(active)
	elif key.keycode == KEY_M and active != null:
		_windows.minimize(active)
	elif key.keycode == KEY_D:
		_windows.toggle_desktop()
	elif key.keycode == KEY_R:
		_windows.open(&"run")
	elif key.keycode == KEY_B:
		_players.blank()
	elif key.keycode == KEY_P and key.shift_pressed and active != null:
		# Apps that can show something answer to "present"; the others ignore it.
		active.content.on_menu_action(&"present")
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9 and not key.shift_pressed:
		var apps := REGISTRY.start_menu_apps()
		var index := key.keycode - KEY_1
		handled = index < apps.size()
		if handled:
			_windows.open(apps[index].id)
	else:
		handled = false
	if handled:
		_set_start_open(false)
		get_viewport().set_input_as_handled()


## An image from the disk, straight to the players' screen (handouts, maps, portraits).
func _choose_player_image() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = tr("Immagine da mostrare ai giocatori")
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.svg ; %s" % tr("Immagini")])
	var folder := str(Save.get_ui("players_image_dir", ""))
	if folder != "":
		dialog.current_dir = folder
	dialog.file_selected.connect(func(path: String) -> void:
		Save.set_ui("players_image_dir", path.get_base_dir())
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			_show_balloon(tr("Schermo giocatori"), tr("Non riesco ad aprire l'immagine «%s».") % path.get_file())
			return
		_players.present({"kind": "image", "caption": path.get_file(), "texture": ImageTexture.create_from_image(image)}))
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free.call_deferred())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _show_shortcuts() -> void:
	var command := "Cmd" if OS.get_name() == "macOS" else "Ctrl"
	var lines: PackedStringArray = [
		"%s+W\t%s" % [command, tr("chiude la finestra")],
		"%s+M\t%s" % [command, tr("riduce la finestra a icona")],
		"Ctrl+Tab\t%s" % tr("finestra successiva (Maiusc: precedente)"),
		"%s+D\t%s" % [command, tr("mostra il desktop (di nuovo: ripristina)")],
		"%s+R\t%s" % [command, tr("Esegui…: apre un programma o un file per nome")],
		"%s+%s+P\t%s" % [command, tr("Maiusc"), tr("mostra ai giocatori (memo, file, pagina, tiro)")],
		"%s+B\t%s" % [command, tr("oscura lo schermo giocatori")],
		"F11\t%s" % tr("schermo intero"),
		"",
	]
	var apps := REGISTRY.start_menu_apps()
	for i in mini(apps.size(), 9):
		lines.append("%s+%d\t%s" % [command, i + 1, tr(apps[i].label)])
	lines.append_array(["", tr("Nelle finestre: Alt + la lettera sottolineata apre il menu."), tr("%s+F cerca nel Canone e nel Blocco note, %s+N nuova pagina nel Taccuino.") % [command, command]])
	var dialog := AcceptDialog.new()
	dialog.title = tr("Scorciatoie da tastiera")
	# The font is monospaced: the first column is padded to line up the descriptions.
	var aligned: PackedStringArray = []
	for line in lines:
		var parts := line.split("\t")
		aligned.append(parts[0].rpad(13) + "  " + parts[1] if parts.size() == 2 else line)
	dialog.dialog_text = "\n".join(aligned)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


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
		_start_menu.build(REGISTRY, Sfx.enabled, _is_fullscreen(), _players.visible)
		_start_menu.open_at(Vector2(4.0, _taskbar.position.y))
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


## entries: {label, call, disabled?}; an empty Dictionary is a separator.
func _show_context(entries: Array[Dictionary], at: Vector2) -> void:
	_set_start_open(false)
	_context.clear()
	_context_actions.clear()
	for entry in entries:
		if entry.is_empty():
			_context.add_separator()
			continue
		_context.add_item(tr(str(entry.label)), _context_actions.size())
		_context.set_item_disabled(_context.item_count - 1, bool(entry.get("disabled", false)))
		_context_actions.append(entry.call)
	_context.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_icons_context(key: String, at: Vector2) -> void:
	if key != "":
		_show_context([
			{"label": "Apri", "call": _icons.open.bind(key)},
			{},
			{"label": "Proprietà", "call": _windows.open.bind(&"props", _props_args(key))},
		], at)
		return
	_show_context([
		{"label": "Allinea le icone", "call": _icons.align},
		{"label": "Aggiorna", "call": _icons.refresh},
		{},
		{"label": "Proprietà", "call": _windows.open.bind(&"ctrl", {"tab": "screen"})},
	], at)


## What the Properties window needs for an icon: its app, or its file's id.
func _props_args(key: String) -> Dictionary:
	if key.begins_with(DesktopIcons.FILE_PREFIX):
		return {"file": key.trim_prefix(DesktopIcons.FILE_PREFIX)}
	return {"app": REGISTRY.find(StringName(key))}


func _on_taskbar_context(id: StringName, at: Vector2) -> void:
	if id == &"":
		_show_context([
			{"label": "Disponi le finestre", "call": _windows.reset_positions},
			{"label": "Riduci a icona tutte le finestre", "call": _windows.toggle_desktop, "disabled": not _windows.any_shown()},
		], at)
		return
	var window := _windows.window_of(id)
	if window == null:
		return
	_show_context([
		{"label": "Ripristina", "call": func() -> void: _show_window(window, false), "disabled": window.visible and not window.maximized},
		{"label": "Riduci a icona", "call": _windows.minimize.bind(window), "disabled": not window.visible},
		{"label": "Ingrandisci", "call": func() -> void: _show_window(window, true), "disabled": not window.app.resizable or (window.visible and window.maximized)},
		{},
		{"label": "Chiudi", "call": _windows.close.bind(window)},
	], at)


func _show_window(window: AppWindow, maximized: bool) -> void:
	_windows.open(window.app.id)
	if window.maximized != maximized:
		window.toggle_maximized()


## The '98 minimize/restore animation: a title bar flying between the window and its button.
func _zoom(from: Rect2, to: Rect2) -> void:
	if not from.has_area() or not to.has_area():
		return
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"TitleBarActive"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_taskbar.get_parent().add_child(bar)
	bar.position = from.position
	bar.size = from.size
	var tween := bar.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	tween.tween_property(bar, "position", to.position, ZOOM_SECONDS)
	tween.tween_property(bar, "size", to.size, ZOOM_SECONDS)
	tween.chain().tween_callback(bar.queue_free)


static func _caption_rect(window: AppWindow) -> Rect2:
	return Rect2(window.global_position, Vector2(window.size.x, CAPTION_HEIGHT))


func _on_sound_changed() -> void:
	_taskbar.set_sound_enabled(Sfx.enabled)
	_taskbar.set_volume(Sfx.volume)


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
	_taskbar.set_next_session(tr("Prossima: %s %s %s") % [ItalianDate.weekday_short(day), ItalianDate.numeric(day).left(5), str(session.get("time", ""))])


## If the next session is today, after the welcome it reminds what is left to prepare.
func _remind_session_today() -> void:
	var session := Campaign.next_session()
	if session.is_empty() or session.date != ItalianDate.today():
		return
	await get_tree().create_timer(4.0).timeout
	var todo: int = session.checklist.filter(func(item: Dictionary) -> bool: return not item.done).size()
	var text := (tr("Alle %s. ") % session.time if str(session.get("time", "")) != "" else "")
	if todo > 0:
		text += (tr("%d cosa da preparare.") if todo == 1 else tr("%d cose da preparare.")) % todo
	else:
		text += tr("Tutto pronto.")
	_show_balloon(tr("Sessione oggi"), text, {"app": &"agenda", "args": {"day": session.date}})


func _refresh_trash_icon() -> void:
	_icons.set_icon_texture("trash", TRASH_FULL if not Campaign.trash.is_empty() else TRASH_EMPTY)


func _refresh_mail_badge() -> void:
	_icons.set_badge("amail", Campaign.correspondence.unread_count())


## A memo or a file just arrived: clickable balloon and the subject's reactions.
func _on_delivered(kind: String, item: Dictionary) -> void:
	Sfx.play(&"mail" if kind == "memo" else &"pop")
	if kind == "memo":
		_show_balloon(tr("Nuovo messaggio in AMail"), "%s: %s" % [item.sender, item.subject], {"app": &"amail", "args": {"memo": item.id}})
	else:
		_show_balloon(tr("Nuovo file sulla scrivania"), tr("%s · origine sconosciuta") % item.name, {"app": &"notepad", "args": {"file": item.id}})
		Entity.stir(0.45)
		Entity.glitch("lattice")


## Once per version: the patch just installed, or the one that broke the startup and was undone.
func _announce_patch() -> void:
	var title := ""
	var text := ""
	if BootPatch.failed_version != "" and Save.get_ui("update_failed_seen", "") != BootPatch.failed_version:
		Save.set_ui("update_failed_seen", BootPatch.failed_version)
		title = tr("Aggiornamento annullato")
		text = tr("La versione %s non si avviava correttamente: AgencyOS è tornato alla %s.") % [BootPatch.failed_version, BootPatch.base_version]
	elif BootPatch.patch_version != "" and Save.get_ui("update_seen", "") != BootPatch.patch_version:
		Save.set_ui("update_seen", BootPatch.patch_version)
		title = tr("AgencyOS aggiornato")
		text = tr("Ora è in esecuzione la versione %s.") % BootPatch.patch_version
	if title != "":
		await get_tree().create_timer(2.0).timeout
		_show_balloon(title, text)


## Automatic checks only speak up when there's something to do; downloads always do.
func _on_update_state(state: Updater.State) -> void:
	var details := {"app": &"ctrl", "args": {"tab": "update"}}
	match state:
		Updater.State.AVAILABLE when Updater.automatic:
			_show_balloon(tr("Aggiornamento disponibile"), tr("AgencyOS 98 %s è pronto da scaricare. Fare clic per i dettagli.") % Updater.manifest.version, details)
		Updater.State.NEEDS_INSTALLER when Updater.automatic:
			_show_balloon(tr("Nuova versione disponibile"), tr("AgencyOS 98 %s richiede il nuovo programma di installazione. Fare clic per i dettagli.") % Updater.manifest.version, details)
		Updater.State.READY:
			Sfx.play(&"ding")
			_show_balloon(tr("Aggiornamento scaricato"), tr("Riavviare AgencyOS per completare l'installazione."), details)


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
		&"shortcuts":
			_show_shortcuts()
		&"players_toggle":
			_players.set_open(not _players.visible)
		&"players_blank":
			_players.blank()
		&"players_image":
			_choose_player_image()
		&"jackpot":
			# The burst comes out of the calculator, if it's on screen.
			var calc := _windows.rect_of(&"calc")
			var origin := calc.position + Vector2(calc.size.x / 2.0, 40.0) if calc.has_area() else Vector2(size.x / 2.0, size.y * 0.6)
			_jackpot.play(origin)
		&"reset_branch":
			_windows.open(&"dossier", {"reset": true})
		&"fullscreen":
			_set_fullscreen(not _is_fullscreen())
		&"run":
			_windows.open(&"run")
		&"restart":
			Save.flush()
			get_tree().reload_current_scene()
		&"shutdown":
			_shutdown.open()
		&"quit":
			Save.flush()
			get_tree().quit()
