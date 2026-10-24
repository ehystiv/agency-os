extends AppContent
## Reserved line: the chat with U0047BB. Shows the open interview,
## streams messages through Brain and closes the session with the summary.
## Also shows closed interviews, read only (archive).

const LED_ON := Color("3fd27a")
const LED_OFF := Color("3a3f4b")
const LED_SEARCH := Color("e5262c")
const TITLE_GLITCH_SECONDS := 4.0
const TITLE_GLITCH_NAMES: PackedStringArray = ["aiutami.exe", "linea_libera.exe", "non_guardare.exe", "sono_qui.exe", "apri_il_caveau.exe"]
const SEARCH_LINE_SECONDS := 0.9
const SEARCH_SILENCE_SECONDS := 6.0
const BASE_TITLE := "linea_riservata.exe"
const PLACEHOLDER_LIVE := "Scrivi all'Entità…"
const PLACEHOLDER_ARCHIVE := "Colloquio in archivio: sola lettura."
const PLACEHOLDER_CLOSED := "Apri la linea per scrivere all'Entità."
const HINT_LIVE := "Invio per mandare, Maiusc+Invio per andare a capo"

## Interview shown: the open one, or a closed one from the archive.
var _interview: Interview
## Number of the requested archived interview; 0 = the live line.
var _viewing_number := 0
var _request: BrainRequest
## True while the Entity replies or the session is being archived.
var _busy := false
var _searching := false
var _last_error := ""
## Title forced by a "title" glitch; empty = normal title.
var _title_override := ""

@onready var _led: ColorRect = %Led
@onready var _status: Label = %StatusText
@onready var _info: Label = %Info
@onready var _back: LinkButton = %Back
@onready var _export: LinkButton = %Export
@onready var _scroll: ScrollContainer = %Scroll
@onready var _log: VBoxContainer = %Log
@onready var _splash: Control = %Splash
@onready var _input: TextEdit = %Input
@onready var _send: Button = %Send
@onready var _stop: Button = %Stop
@onready var _end: LinkButton = %End
@onready var _hint: Label = %Hint
@onready var _glitch_layer: GlitchLayer = %GlitchLayer


func _ready() -> void:
	%Open.pressed.connect(_on_open_pressed)
	%SplashSettings.pressed.connect(_open_settings)
	_send.pressed.connect(_on_send_pressed)
	_stop.pressed.connect(_on_stop_pressed)
	_end.pressed.connect(_on_end_pressed)
	_input.gui_input.connect(_on_input_gui_input)
	_back.pressed.connect(_on_back_pressed)
	_export.pressed.connect(_export_interview)
	_glitch_layer.shake_target = $Layout
	Campaign.interviews_changed.connect(_refresh)
	_refresh()


## args: {"interview": n} shows that interview; {"open": true} opens the line if it's closed.
func on_opened(args: Dictionary = {}) -> void:
	if not _busy:
		if args.has("interview"):
			_viewing_number = int(args.interview)
			_refresh()
		elif args.get("open", false):
			_viewing_number = 0
			if Campaign.current() == null:
				_on_open_pressed()
			else:
				_refresh()
	if _input.editable:
		_input.grab_focus.call_deferred()


func _refresh() -> void:
	if _busy:
		return
	var current := Campaign.current()
	var archived := Campaign.find(_viewing_number) if _viewing_number > 0 else null
	if archived == null or archived == current:
		_viewing_number = 0
		archived = null
	_interview = archived if archived != null else current
	var has_view := _interview != null
	var live := has_view and archived == null
	_splash.visible = not has_view
	_scroll.visible = has_view
	# The input box always stays in place, so the window doesn't change height.
	_input.editable = live
	_input.placeholder_text = PLACEHOLDER_LIVE if live else (PLACEHOLDER_ARCHIVE if has_view else PLACEHOLDER_CLOSED)
	if not live:
		_input.text = ""
	_end.visible = live
	_hint.text = HINT_LIVE if live else ""
	_rebuild_log()
	_update_chrome()


func _is_archive() -> bool:
	return _interview != null and not _interview.is_open()


func _update_chrome() -> void:
	var live := _interview != null and not _is_archive()
	_led.color = LED_SEARCH if _searching else (LED_ON if live else LED_OFF)
	_back.visible = _is_archive()
	_export.visible = _interview != null
	_back.text = "Torna al colloquio in corso" if Campaign.current() != null else "Torna alla linea"
	_info.visible = not _is_archive()
	if _searching:
		_status.text = "Ricerca di AgencyOS in corso…"
	elif _is_archive():
		_status.text = "Archivio"
	elif not live:
		_status.text = "Linea chiusa"
	elif _request != null:
		_status.text = "U0047BB sta scrivendo…"
	elif _busy:
		_status.text = "Archiviazione in corso…"
	else:
		_status.text = "In linea con U0047BB"
	_info.text = "Accesso %d" % Campaign.level()
	if live:
		_info.text += " · Colloquio n. %03d" % _interview.number
	_send.visible = _request == null
	_send.disabled = _busy or _searching or not live
	_stop.visible = _request != null
	_end.disabled = _busy
	_input.editable = live and not _searching
	if _title_override == "":
		title_changed.emit(BASE_TITLE + (" · colloquio_%03d" % _interview.number if _interview != null else ""))


func _rebuild_log() -> void:
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	if _interview == null:
		return
	for message in _interview.messages:
		var shown := _append(ChatMessage.kind_for(message.who), str(message.text))
		# The whisper is the only glitch that stays visible afterwards.
		if message.get("glitch", "") == "whisper":
			shown.set_whisper()
	if _is_archive():
		var closed_on := ItalianDate.short(_interview.closed_at)
		_append(ChatMessage.Kind.NOTE, "Colloquio chiuso" + (" il %s." % closed_on if closed_on != "" else "."))
		var summary := SummaryBox.create(_interview.summary)
		var shown := _interview
		summary.saved.connect(func(text: String) -> void: Campaign.set_summary(shown, text))
		_log.add_child(summary)
	elif _last_error != "":
		_append_error(_last_error)
	_scroll_to_end()


func _append(kind: ChatMessage.Kind, text: String) -> ChatMessage:
	var message := ChatMessage.create(kind, text)
	_log.add_child(message)
	return message


func _append_error(text: String) -> void:
	var message := _append(ChatMessage.Kind.ERROR, text)
	message.retry_pressed.connect(_on_retry_pressed.bind(message))
	message.settings_pressed.connect(_open_settings)


func _scroll_to_end() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


# --- Actions ---------------------------------------------------------------

func _on_open_pressed() -> void:
	_last_error = ""
	_viewing_number = 0
	Campaign.open_interview()
	Sfx.play(&"modem")
	# As in the prototype, the webcam turns on with the line; the Line stays in front.
	app_requested.emit(&"cam", {})
	app_requested.emit(&"line", {})
	_input.grab_focus.call_deferred()


func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER] and not key.shift_pressed:
		_input.accept_event()
		_on_send_pressed()


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text == "" or _busy or _interview == null:
		return
	_input.text = ""
	_clear_error()
	Campaign.add_message(_interview, "manager", text)
	_append(ChatMessage.Kind.MANAGER, text)
	_reply()


func _on_retry_pressed(error_message: ChatMessage) -> void:
	if _busy:
		return
	error_message.queue_free()
	_clear_error()
	_reply()


func _on_stop_pressed() -> void:
	if _request != null:
		_request.cancel()


func _on_end_pressed() -> void:
	if _busy or _interview == null:
		return
	var closing := _interview
	_busy = true
	_clear_error()
	_update_chrome()
	_append(ChatMessage.Kind.SYSTEM, "> SESSIONE TERMINATA DAL GENERAL MANAGER.")
	_append(ChatMessage.Kind.NOTE, "Archiviazione del colloquio…")
	_scroll_to_end()
	await Campaign.close_interview(closing)
	_busy = false
	# After closing, the interview stays visible, now archived, with its memories.
	_viewing_number = closing.number
	_refresh()
	var notebook := {"app": &"notebook", "args": {"session": closing.number}}
	if closing.summary != "":
		notification_requested.emit("Sessione archiviata", "Colloquio n. %03d chiuso. Clic per scrivere i tuoi appunti nel Taccuino." % closing.number, notebook)
	else:
		notification_requested.emit("Sessione archiviata", "Colloquio n. %03d chiuso, ma il modello non ha scritto il riassunto: lo ritenterò alla prossima apertura della linea. Clic per il Taccuino." % closing.number, notebook)


func _on_back_pressed() -> void:
	_viewing_number = 0
	_refresh()


func _open_settings() -> void:
	app_requested.emit(&"line_settings", {})


func _clear_error() -> void:
	_last_error = ""
	for child in _log.get_children():
		if child is ChatMessage and child.kind == ChatMessage.Kind.ERROR:
			child.queue_free()


# --- The Entity's reply ----------------------------------------------------

func _reply() -> void:
	var interview := _interview
	_busy = true
	var bubble := _append(ChatMessage.Kind.ENTITY, "")
	bubble.set_entity_text("", true)
	_request = Brain.chat(Campaign.build_messages(interview))
	Entity.set_speaking(true)
	Entity.stir(0.25)
	_request.chunk_received.connect(func(_piece: String) -> void:
		bubble.set_entity_text(_request.text, true)
		_scroll_to_end())
	_update_chrome()
	_scroll_to_end()
	if not _request.is_done:
		await _request.finished
	var request := _request
	_request = null
	Entity.set_speaking(false)
	if request.ok():
		var text := request.text.strip_edges()
		if request.cancelled and text != "":
			text += " —"
		if text != "":
			var saved := Campaign.add_message(interview, "entity", text)
			bubble.set_entity_text(text, false)
			_update_chrome()
			if not request.cancelled:
				await _after_reply(interview, saved, bubble)
		else:
			bubble.queue_free()
	else:
		bubble.queue_free()
		_last_error = request.error
		_append_error(request.error)
	_busy = false
	_update_chrome()
	_scroll_to_end()
	if is_visible_in_tree():
		_input.grab_focus()


# --- Glitches and AgencyOS searches ---------------------------------------

## After a reply: maybe a glitch (rules in Campaign), otherwise maybe a search.
func _after_reply(interview: Interview, saved: Dictionary, bubble: ChatMessage) -> void:
	if Save.get_ui("glitches_enabled", true) and Campaign.can_glitch(interview):
		var glitch := await Campaign.choose_glitch(interview)
		if glitch != "":
			saved["glitch"] = glitch
			Campaign.save_interview(interview)
			_play_glitch(glitch, bubble)
			return
	if randf() < Campaign.search_chance(interview):
		await _agency_search(interview)


func _play_glitch(glitch: String, bubble: ChatMessage) -> void:
	Entity.glitch(glitch)
	if glitch == "title":
		_glitch_title()
	elif is_instance_valid(bubble):
		_glitch_layer.play(glitch, bubble, _log)


func _glitch_title() -> void:
	_title_override = TITLE_GLITCH_NAMES[randi() % TITLE_GLITCH_NAMES.size()]
	title_changed.emit(_title_override)
	await get_tree().create_timer(TITLE_GLITCH_SECONDS).timeout
	_title_override = ""
	_update_chrome()


## AgencyOS searches the channel for U0047BB: the Entity hides, the webcam loses the signal.
func _agency_search(interview: Interview) -> void:
	_searching = true
	_update_chrome()
	Campaign.record_search(interview)
	Sfx.play(&"ding")
	Sfx.start_hum()
	Entity.lose_signal()
	Entity.stir(0.6)
	await _search_line(interview, "> INIZIO RICERCA U0047BB.")
	await _search_line(interview, "> INDIVIDUATA ATTIVITÀ ANOMALA SUL CANALE DEL GENERAL MANAGER. ANALISI IN CORSO…")
	var bubble := _append(ChatMessage.Kind.ENTITY, "")
	bubble.set_entity_text("", true)
	_scroll_to_end()
	var hide_request := Brain.chat(Campaign.build_messages(interview, Campaign.search_event()))
	hide_request.chunk_received.connect(func(_piece: String) -> void: bubble.set_entity_text(hide_request.text, true))
	if not hide_request.is_done:
		await hide_request.finished
	if hide_request.ok():
		Campaign.add_message(interview, "entity", hide_request.text.strip_edges())
		bubble.set_entity_text(hide_request.text.strip_edges(), false)
	else:
		bubble.queue_free()
	await _search_line(interview, "> ISOLAMENTO CONFERMATO DALLO STAFF DEL CAVEAU.")
	await _search_line(interview, "> NESSUNA ATTIVITÀ ANOMALA RILEVATA. RIPRISTINO MYMANUAL1998.EXE.")
	await get_tree().create_timer(SEARCH_SILENCE_SECONDS).timeout
	Sfx.stop_hum()
	Entity.restore_signal()
	Entity.stir(0.0, 0.0, 0.9)
	await _search_line(interview, "> RICERCA CONCLUSA. CANALE DI NUOVO STABILE.")
	_searching = false


func _search_line(interview: Interview, text: String) -> void:
	Campaign.add_message(interview, "system", text)
	_append(ChatMessage.Kind.SYSTEM, text)
	_scroll_to_end()
	await get_tree().create_timer(SEARCH_LINE_SECONDS).timeout


## Exports the shown interview, open or archived, to Obsidian with links to its pages.
func _export_interview() -> void:
	if _interview == null:
		return
	var exporter := ObsidianExporter.new()
	add_child(exporter)
	var notes: Array[Dictionary] = [{
		"name": ObsidianMarkdown.interview_name(_interview),
		"text": ObsidianMarkdown.interview(_interview, Campaign.pages_for_session(_interview.number), Campaign.correspondence.mail_for_session(_interview.number)),
	}]
	var result := await exporter.export_notes(notes)
	exporter.queue_free()
	if result.cancelled:
		return
	var title := "Esportato in Obsidian" if result.error == "" else "Esportazione non riuscita"
	notification_requested.emit(title, ObsidianExporter.summary(result), {"folder": result.folder} if result.folder != "" else {})
