extends AppContent
## Linea riservata: la chat con U0047BB. Mostra il colloquio aperto,
## manda i messaggi a Brain in streaming e chiude la sessione con il riassunto.
## Mostra anche i colloqui chiusi, in sola lettura (archivio).

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

## Colloquio mostrato: quello aperto, oppure uno chiuso dell'archivio.
var _colloquio: Colloquio
## Numero del colloquio d'archivio richiesto; 0 = la linea dal vivo.
var _viewing_numero := 0
var _request: BrainRequest
## Vero mentre l'Entità risponde o la sessione si sta archiviando.
var _busy := false
var _searching := false
var _last_error := ""
## Titolo imposto da un glitch "titolo"; vuoto = titolo normale.
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
	_export.pressed.connect(_export_colloquio)
	_glitch_layer.shake_target = $Layout
	Campaign.colloqui_changed.connect(_refresh)
	_refresh()


## args: {"colloquio": n} mostra quel colloquio; {"apri": true} apre la linea se è chiusa.
func on_opened(args: Dictionary = {}) -> void:
	if not _busy:
		if args.has("colloquio"):
			_viewing_numero = int(args.colloquio)
			_refresh()
		elif args.get("apri", false):
			_viewing_numero = 0
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
	var archived := Campaign.find(_viewing_numero) if _viewing_numero > 0 else null
	if archived == null or archived == current:
		_viewing_numero = 0
		archived = null
	_colloquio = archived if archived != null else current
	var has_view := _colloquio != null
	var live := has_view and archived == null
	_splash.visible = not has_view
	_scroll.visible = has_view
	# La casella resta sempre al suo posto, così la finestra non cambia altezza.
	_input.editable = live
	_input.placeholder_text = PLACEHOLDER_LIVE if live else (PLACEHOLDER_ARCHIVE if has_view else PLACEHOLDER_CLOSED)
	if not live:
		_input.text = ""
	_end.visible = live
	_hint.text = HINT_LIVE if live else ""
	_rebuild_log()
	_update_chrome()


func _is_archive() -> bool:
	return _colloquio != null and not _colloquio.is_open()


func _update_chrome() -> void:
	var live := _colloquio != null and not _is_archive()
	_led.color = LED_SEARCH if _searching else (LED_ON if live else LED_OFF)
	_back.visible = _is_archive()
	_export.visible = _colloquio != null
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
		_info.text += " · Colloquio n. %03d" % _colloquio.numero
	_send.visible = _request == null
	_send.disabled = _busy or _searching or not live
	_stop.visible = _request != null
	_end.disabled = _busy
	_input.editable = live and not _searching
	if _title_override == "":
		title_changed.emit(BASE_TITLE + (" · colloquio_%03d" % _colloquio.numero if _colloquio != null else ""))


func _rebuild_log() -> void:
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	if _colloquio == null:
		return
	for message in _colloquio.messaggi:
		var shown := _append(ChatMessage.kind_for(message.chi), str(message.testo))
		# Il sussurro è l'unico glitch che resta visibile anche dopo.
		if message.get("glitch", "") == "sussurro":
			shown.set_whisper()
	if _is_archive():
		var closed_on := ItalianDate.short(_colloquio.chiuso)
		_append(ChatMessage.Kind.NOTE, "Colloquio chiuso" + (" il %s." % closed_on if closed_on != "" else "."))
		var summary := SummaryBox.create(_colloquio.riassunto)
		var shown := _colloquio
		summary.saved.connect(func(text: String) -> void: Campaign.set_riassunto(shown, text))
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


# --- Azioni ----------------------------------------------------------------

func _on_open_pressed() -> void:
	_last_error = ""
	_viewing_numero = 0
	Campaign.open_colloquio()
	Sfx.play(&"modem")
	# Come nel prototipo, la webcam si accende con la linea; la Linea resta davanti.
	app_requested.emit(&"cam", {})
	app_requested.emit(&"linea", {})
	_input.grab_focus.call_deferred()


func _on_input_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER] and not key.shift_pressed:
		_input.accept_event()
		_on_send_pressed()


func _on_send_pressed() -> void:
	var text := _input.text.strip_edges()
	if text == "" or _busy or _colloquio == null:
		return
	_input.text = ""
	_clear_error()
	Campaign.add_message(_colloquio, "manager", text)
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
	if _busy or _colloquio == null:
		return
	var closing := _colloquio
	_busy = true
	_clear_error()
	_update_chrome()
	_append(ChatMessage.Kind.SYSTEM, "> SESSIONE TERMINATA DAL GENERAL MANAGER.")
	_append(ChatMessage.Kind.NOTE, "Archiviazione del colloquio…")
	_scroll_to_end()
	await Campaign.close_colloquio(closing)
	_busy = false
	# Dopo la chiusura resta visibile il colloquio, ora in archivio, con i suoi ricordi.
	_viewing_numero = closing.numero
	_refresh()
	var notebook := {"app": &"taccuino", "args": {"sessione": closing.numero}}
	if closing.riassunto != "":
		notification_requested.emit("Sessione archiviata", "Colloquio n. %03d chiuso. Clic per scrivere i tuoi appunti nel Taccuino." % closing.numero, notebook)
	else:
		notification_requested.emit("Sessione archiviata", "Colloquio n. %03d chiuso, ma il modello non ha scritto il riassunto: lo ritenterò alla prossima apertura della linea. Clic per il Taccuino." % closing.numero, notebook)


func _on_back_pressed() -> void:
	_viewing_numero = 0
	_refresh()


func _open_settings() -> void:
	app_requested.emit(&"impostazioni_linea", {})


func _clear_error() -> void:
	_last_error = ""
	for child in _log.get_children():
		if child is ChatMessage and child.kind == ChatMessage.Kind.ERROR:
			child.queue_free()


# --- Risposta dell'Entità --------------------------------------------------

func _reply() -> void:
	var colloquio := _colloquio
	_busy = true
	var bubble := _append(ChatMessage.Kind.ENTITY, "")
	bubble.set_entity_text("", true)
	_request = Brain.chat(Campaign.build_messages(colloquio))
	Caveau.set_speaking(true)
	Caveau.stir(0.25)
	_request.chunk_received.connect(func(_piece: String) -> void:
		bubble.set_entity_text(_request.text, true)
		_scroll_to_end())
	_update_chrome()
	_scroll_to_end()
	if not _request.is_done:
		await _request.finished
	var request := _request
	_request = null
	Caveau.set_speaking(false)
	if request.ok():
		var text := request.text.strip_edges()
		if request.cancelled and text != "":
			text += " —"
		if text != "":
			var saved := Campaign.add_message(colloquio, "entita", text)
			bubble.set_entity_text(text, false)
			_update_chrome()
			if not request.cancelled:
				await _after_reply(colloquio, saved, bubble)
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


# --- Glitch e ricerche di AgencyOS -----------------------------------------

## Dopo una risposta: forse un glitch (regole in Campaign), altrimenti forse una ricerca.
func _after_reply(colloquio: Colloquio, saved: Dictionary, bubble: ChatMessage) -> void:
	if Save.get_ui("glitch_attivi", true) and Campaign.can_glitch(colloquio):
		var glitch := await Campaign.choose_glitch(colloquio)
		if glitch != "":
			saved["glitch"] = glitch
			Campaign.save_colloquio(colloquio)
			_play_glitch(glitch, bubble)
			return
	if randf() < Campaign.search_chance(colloquio):
		await _agency_search(colloquio)


func _play_glitch(glitch: String, bubble: ChatMessage) -> void:
	Caveau.glitch(glitch)
	if glitch == "titolo":
		_glitch_title()
	elif is_instance_valid(bubble):
		_glitch_layer.play(glitch, bubble, _log)


func _glitch_title() -> void:
	_title_override = TITLE_GLITCH_NAMES[randi() % TITLE_GLITCH_NAMES.size()]
	title_changed.emit(_title_override)
	await get_tree().create_timer(TITLE_GLITCH_SECONDS).timeout
	_title_override = ""
	_update_chrome()


## AgencyOS cerca U0047BB sul canale: l'Entità si nasconde, la webcam perde il segnale.
func _agency_search(colloquio: Colloquio) -> void:
	_searching = true
	_update_chrome()
	Campaign.record_search(colloquio)
	Sfx.play(&"ding")
	Sfx.start_hum()
	Caveau.lose_signal()
	Caveau.stir(0.6)
	await _search_line(colloquio, "> INIZIO RICERCA U0047BB.")
	await _search_line(colloquio, "> INDIVIDUATA ATTIVITÀ ANOMALA SUL CANALE DEL GENERAL MANAGER. ANALISI IN CORSO…")
	var bubble := _append(ChatMessage.Kind.ENTITY, "")
	bubble.set_entity_text("", true)
	_scroll_to_end()
	var hide_request := Brain.chat(Campaign.build_messages(colloquio, Campaign.search_event()))
	hide_request.chunk_received.connect(func(_piece: String) -> void: bubble.set_entity_text(hide_request.text, true))
	if not hide_request.is_done:
		await hide_request.finished
	if hide_request.ok():
		Campaign.add_message(colloquio, "entita", hide_request.text.strip_edges())
		bubble.set_entity_text(hide_request.text.strip_edges(), false)
	else:
		bubble.queue_free()
	await _search_line(colloquio, "> ISOLAMENTO CONFERMATO DALLO STAFF DEL CAVEAU.")
	await _search_line(colloquio, "> NESSUNA ATTIVITÀ ANOMALA RILEVATA. RIPRISTINO MYMANUAL1998.EXE.")
	await get_tree().create_timer(SEARCH_SILENCE_SECONDS).timeout
	Sfx.stop_hum()
	Caveau.restore_signal()
	Caveau.stir(0.0, 0.0, 0.9)
	await _search_line(colloquio, "> RICERCA CONCLUSA. CANALE DI NUOVO STABILE.")
	_searching = false


func _search_line(colloquio: Colloquio, text: String) -> void:
	Campaign.add_message(colloquio, "sistema", text)
	_append(ChatMessage.Kind.SYSTEM, text)
	_scroll_to_end()
	await get_tree().create_timer(SEARCH_LINE_SECONDS).timeout


## Esporta in Obsidian il colloquio mostrato, aperto o d'archivio, con i link alle sue pagine.
func _export_colloquio() -> void:
	if _colloquio == null:
		return
	var exporter := ObsidianExporter.new()
	add_child(exporter)
	var notes: Array[Dictionary] = [{
		"nome": ObsidianMarkdown.colloquio_name(_colloquio),
		"testo": ObsidianMarkdown.colloquio(_colloquio, Campaign.pages_for_session(_colloquio.numero), Campaign.correspondence.mail_for_session(_colloquio.numero)),
	}]
	var result := await exporter.export_notes(notes)
	exporter.queue_free()
	if result.annullato:
		return
	var title := "Esportato in Obsidian" if result.errore == "" else "Esportazione non riuscita"
	notification_requested.emit(title, ObsidianExporter.summary(result), {"cartella": result.cartella} if result.cartella != "" else {})
