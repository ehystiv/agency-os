extends AppContent
## Media player. Three sources, one per tab: the company hold music and the ambient
## sounds (synthesized live), the audio files of a folder, and the saved collection
## (audio downloaded from YouTube with yt-dlp, under a name chosen by the Manager).

enum Source { COMPANY, FOLDER, COLLECTION }

const SELECTED_TEXT := Color.WHITE
const IDLE_STATUS: Array[String] = [
	"Musiche d'attesa aziendali e suoni d'ambiente · sintetizzati dal vivo",
	"File mp3, ogg e wav della cartella scelta",
	"Brani salvati nella raccolta",
]

var _library := PlayerLibrary.new()
var _folder := ""
var _folder_files: PackedStringArray = []
## The tab shown, and the source and position of what is playing (or was last played).
var _tab := Source.COMPANY
var _playing_source := Source.COMPANY
var _playing_index := -1
var _seeking := false
## The collection row last clicked: Rinomina and Elimina act on it.
var _selected_id := ""
var _delete_armed := false
## The link being downloaded.
var _downloading_url := ""

@onready var _engine: MusicEngine = %Engine
@onready var _now: Label = %NowPlaying
@onready var _time: Label = %Time
@onready var _play: Button = %Play
@onready var _loop: Button = %Loop
@onready var _volume: HSlider = %Volume
@onready var _seek_row: HBoxContainer = %SeekRow
@onready var _seek: HSlider = %Seek
@onready var _length: Label = %Length
@onready var _tabs: TabBar = %Tabs
@onready var _folder_bar: HBoxContainer = %FolderBar
@onready var _folder_label: Label = %Folder
@onready var _rows: VBoxContainer = %Rows
@onready var _status: Label = %Status
@onready var _library_bar: HBoxContainer = %LibraryBar
@onready var _rename: Button = %Rename
@onready var _delete: Button = %Delete
@onready var _youtube_form: PanelContainer = %YoutubeForm
@onready var _url: LineEdit = %Url
@onready var _track_name: LineEdit = %TrackName
@onready var _download: Button = %Download
@onready var _cancel_download: Button = %CancelDownload
@onready var _progress: ProgressBar = %Progress
@onready var _form_status: Label = %FormStatus
@onready var _rename_row: HBoxContainer = %RenameRow
@onready var _rename_field: LineEdit = %RenameField
@onready var _fetch: YouTubeFetch = %Fetch


func _ready() -> void:
	%Visualizer.engine = _engine
	%Prev.pressed.connect(_skip.bind(-1))
	%Next.pressed.connect(_skip.bind(1))
	%Stop.pressed.connect(_engine.stop)
	%OpenFolder.pressed.connect(_choose_folder)
	_play.pressed.connect(_on_play_pressed)
	_volume.value = float(Save.get_ui("player_volume", 70))
	_volume.value_changed.connect(func(value: float) -> void:
		_engine.set_volume(value / 100.0)
		Save.set_ui("player_volume", int(value)))
	_loop.button_pressed = bool(Save.get_ui("player_loop", false))
	_engine.loop = _loop.button_pressed
	_loop.toggled.connect(func(on: bool) -> void:
		_engine.loop = on
		Save.set_ui("player_loop", on))
	_seek.drag_started.connect(func() -> void: _seeking = true)
	_seek.drag_ended.connect(func(_changed: bool) -> void:
		_engine.seek(_seek.value * _engine.length())
		_seeking = false)
	_tab = clampi(int(Save.get_ui("player_tab", Source.COMPANY)), 0, Source.size() - 1) as Source
	_tabs.current_tab = _tab
	_tabs.tab_changed.connect(_on_tab_changed)
	_set_folder(str(Save.get_ui("player_folder", "")))
	%AddYoutube.pressed.connect(_toggle_youtube_form)
	_download.pressed.connect(_start_download)
	_url.text_submitted.connect(func(_t: String) -> void: _start_download())
	_track_name.text_submitted.connect(func(_t: String) -> void: _start_download())
	_cancel_download.pressed.connect(func() -> void:
		if _fetch.busy:
			_fetch.cancel()
		else:
			_youtube_form.hide())
	_fetch.progress.connect(func(fraction: float) -> void: _progress.value = fraction)
	_fetch.finished.connect(_on_downloaded)
	_rename.pressed.connect(_start_rename)
	%RenameSave.pressed.connect(_apply_rename)
	_rename_field.text_submitted.connect(func(_t: String) -> void: _apply_rename())
	%RenameCancel.pressed.connect(_rename_row.hide)
	_delete.pressed.connect(_on_delete_pressed)
	_engine.state_changed.connect(_refresh)
	_engine.file_finished.connect(_on_file_finished)
	Campaign.interviews_changed.connect(_refresh)
	_refresh()


func on_opened(_args: Dictionary = {}) -> void:
	# The folder may have changed outside AgencyOS.
	_set_folder(_folder)
	_refresh()


## Closing the Player stops the music (minimizing doesn't).
func on_closed() -> void:
	_engine.stop()


func _process(_delta: float) -> void:
	if not _engine.playing and not _engine.paused:
		return
	var text := _clock(_engine.elapsed)
	if _time.text != text:
		_time.text = text
	if _engine.is_file() and not _seeking and _engine.length() > 0.0:
		_seek.set_value_no_signal(_engine.elapsed / _engine.length())


# --- Sources -----------------------------------------------------------------

## The rows of a source: {name, note, locked}.
func _entries(source: Source) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	match source:
		Source.COMPANY:
			for i in MusicEngine.TRACKS.size():
				var track: Dictionary = MusicEngine.TRACKS[i]
				var locked := _engine.is_locked(i)
				var note := "livello %d" % track.level if locked else ("ambiente" if track.get("utility", false) else "")
				result.append({"name": track.name, "note": note, "locked": locked})
		Source.FOLDER:
			for path in _folder_files:
				result.append({"name": path.get_file().get_basename(), "note": path.get_extension().to_lower(), "locked": false})
		Source.COLLECTION:
			for item in _library.items:
				var missing := not FileAccess.file_exists(PlayerLibrary.path_of(item))
				result.append({"name": item.name, "note": "file mancante" if missing else "", "locked": missing})
	return result


func _play_entry(source: Source, index: int) -> void:
	var entries := _entries(source)
	if index < 0 or index >= entries.size():
		return
	_playing_source = source
	_playing_index = index
	match source:
		Source.COMPANY:
			if _engine.is_locked(index):
				_engine.stop()
				_engine.track = index
				_refresh()
				_status.text = "Accesso negato. Livello richiesto: %d." % MusicEngine.TRACKS[index].level
				Sfx.play(&"ding")
				return
			_engine.play(index)
		Source.FOLDER:
			_play_file(_folder_files[index], entries[index].name)
		Source.COLLECTION:
			_play_file(PlayerLibrary.path_of(_library.items[index]), entries[index].name)


func _play_file(path: String, display_name: String) -> void:
	var stream := PlayerLibrary.load_audio(path) if FileAccess.file_exists(path) else null
	if stream == null:
		_engine.stop()
		_status.text = "Impossibile leggere «%s»." % path.get_file()
		Sfx.play(&"ding")
		return
	_engine.play_file(stream, display_name)


func _on_play_pressed() -> void:
	if _engine.playing:
		_engine.pause()
	elif _engine.paused:
		_engine.resume()
	elif _playing_index >= 0 and _playing_source == _tab:
		_play_entry(_tab, _playing_index)
	else:
		_play_entry(_tab, _engine.track if _tab == Source.COMPANY else 0)


## Previous or next row of the source in use (or of the tab shown, if nothing was played).
func _skip(step: int) -> void:
	var source := _playing_source if _playing_index >= 0 else _tab
	var count := _entries(source).size()
	if count == 0:
		return
	var index := posmod(_playing_index + step, count) if _playing_index >= 0 else 0
	if _engine.playing or _engine.paused:
		_play_entry(source, index)
	else:
		_engine.stop()
		_playing_source = source
		_playing_index = index
		if source == Source.COMPANY:
			_engine.track = index
		_refresh()


## At the end of a file the Player goes on to the next one, back to the first after the last.
func _on_file_finished() -> void:
	var count := _entries(_playing_source).size()
	if _playing_index >= 0 and count > 0:
		_play_entry(_playing_source, posmod(_playing_index + 1, count))


func _on_tab_changed(tab: int) -> void:
	_tab = tab as Source
	_delete_armed = false
	Save.set_ui("player_tab", tab)
	_refresh()


func _choose_folder() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Cartella con la musica"
	if _folder != "":
		dialog.current_dir = _folder
	dialog.dir_selected.connect(func(path: String) -> void:
		_set_folder(path)
		Save.set_ui("player_folder", path)
		if _playing_source == Source.FOLDER:
			_playing_index = -1
		_refresh())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free.call_deferred())
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _set_folder(path: String) -> void:
	_folder = path
	_folder_files = PlayerLibrary.folder_files(path)
	_folder_label.text = path.get_file() if path != "" else "Nessuna cartella"
	_folder_label.tooltip_text = path


# --- View --------------------------------------------------------------------

func _refresh() -> void:
	var active := _engine.playing or _engine.paused
	var current_name := ""
	if active:
		current_name = _engine.file_name if _engine.is_file() else str(MusicEngine.TRACKS[_engine.track].name)
	_now.text = current_name if active else "nessuna traccia"
	if not active:
		_time.text = "00:00"
	_seek_row.visible = _engine.is_file()
	if _engine.is_file():
		_length.text = _clock(_engine.length())
	_play.text = "❚❚" if _engine.playing else "▶"
	_play.tooltip_text = "Pausa" if _engine.playing else "Riproduci"
	if _engine.playing:
		_status.text = "In riproduzione"
	elif _engine.paused:
		_status.text = "In pausa"
	else:
		_status.text = IDLE_STATUS[_tab]
	_folder_bar.visible = _tab == Source.FOLDER
	var in_collection := _tab == Source.COLLECTION
	_library_bar.visible = in_collection
	if not in_collection:
		_youtube_form.hide()
		_rename_row.hide()
	var has_selection := not _library.find(_selected_id).is_empty()
	_rename.disabled = not has_selection
	_delete.disabled = not has_selection
	_delete.text = "Conferma" if _delete_armed and has_selection else "Elimina"
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var shown := _entries(_tab)
	for i in shown.size():
		var current := active and _tab == _playing_source and i == _playing_index
		_rows.add_child(_make_row(i, shown[i], current))
	if shown.is_empty():
		_rows.add_child(_empty_label())


func _make_row(index: int, entry: Dictionary, current: bool) -> Button:
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = current
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.text = "%d.  %s%s" % [index + 1, entry.name, "   [%s]" % entry.note if entry.note != "" else ""]
	row.tooltip_text = str(entry.name)
	if current:
		row.add_theme_color_override("font_pressed_color", SELECTED_TEXT)
		row.add_theme_color_override("font_hover_pressed_color", SELECTED_TEXT)
	if entry.locked:
		row.modulate.a = 0.55
	var source := _tab
	if source == Source.COLLECTION:
		var id: String = _library.items[index].id
		if id == _selected_id:
			row.button_pressed = true
		row.pressed.connect(func() -> void:
			_selected_id = id
			_delete_armed = false
			_rename_row.hide()
			_play_entry(source, index)
			_refresh())
	else:
		row.pressed.connect(func() -> void: _play_entry(source, index))
	return row


# --- Collection --------------------------------------------------------------

func _toggle_youtube_form() -> void:
	_rename_row.hide()
	_youtube_form.visible = not _youtube_form.visible
	if _youtube_form.visible and not _fetch.busy:
		_form_status.text = "L'audio viene scaricato con yt-dlp e salvato: si ascolta anche senza rete."
		_url.grab_focus.call_deferred()


func _start_download() -> void:
	if _fetch.busy:
		return
	var url := _url.text.strip_edges()
	if not (url.begins_with("http://") or url.begins_with("https://")):
		_form_status.text = "Incolla il link completo del video (https://…)."
		return
	_downloading_url = url
	_set_downloading(true)
	_form_status.text = "Scaricamento in corso…"
	var base := ProjectSettings.globalize_path(PlayerLibrary.CACHE_DIR).path_join("y-%d" % Time.get_unix_time_from_system())
	_fetch.start(url, base)


func _on_downloaded(ok: bool, path: String, title: String, error: String) -> void:
	_set_downloading(false)
	if not ok:
		_form_status.text = error
		Sfx.play(&"ding")
		return
	var chosen := _track_name.text.strip_edges()
	var display_name := chosen if chosen != "" else (title if title != "" else "Brano senza titolo")
	var item := _library.add(display_name, _downloading_url, path.get_file())
	_selected_id = item.id
	_url.clear()
	_track_name.clear()
	_youtube_form.hide()
	Sfx.play(&"mail")
	_refresh()
	_status.text = "Salvato nella raccolta: «%s»" % display_name


func _set_downloading(active: bool) -> void:
	_download.disabled = active
	_url.editable = not active
	_track_name.editable = not active
	_progress.visible = active
	_progress.value = 0.0
	_cancel_download.text = "Interrompi" if active else "Annulla"


func _start_rename() -> void:
	var item := _library.find(_selected_id)
	if item.is_empty():
		return
	_youtube_form.hide()
	_rename_row.show()
	_rename_field.text = str(item.name)
	_rename_field.grab_focus.call_deferred()
	_rename_field.select_all.call_deferred()


func _apply_rename() -> void:
	var item := _library.find(_selected_id)
	var new_name := _rename_field.text.strip_edges()
	if item.is_empty() or new_name == "":
		return
	_library.rename(item, new_name)
	if _engine.is_file() and _playing_source == Source.COLLECTION and _library.items.find(item) == _playing_index:
		_engine.file_name = new_name
	_rename_row.hide()
	_refresh()


## Two clicks, like Azzera in the calculator: the first arms, the second deletes.
func _on_delete_pressed() -> void:
	var item := _library.find(_selected_id)
	if item.is_empty():
		return
	if not _delete_armed:
		_delete_armed = true
		_refresh()
		return
	_delete_armed = false
	if _playing_source == Source.COLLECTION and _playing_index >= 0:
		if _library.items.find(item) == _playing_index:
			_engine.stop()
		_playing_index = -1
	_library.remove(item)
	_selected_id = ""
	_refresh()


func _empty_label() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HintLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200, 0)
	match _tab:
		Source.FOLDER:
			label.text = "Scegli una cartella con file mp3, ogg o wav." if _folder == "" else "Nessun file mp3, ogg o wav in questa cartella."
		_:
			label.text = "La raccolta è vuota. Con «+ Da YouTube…» salvi l'audio di un video con il nome che vuoi."
	return label


static func _clock(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]
