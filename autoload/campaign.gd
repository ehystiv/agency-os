extends Node
## Logica di gioco pura, senza interfaccia: colloqui, livello di accesso,
## prompt dell'Entità, riassunti e memoria cumulativa.
## Memo, file sulla scrivania e bozze stanno in correspondence (nodo figlio).

signal colloqui_changed
## Un colloquio ha ricevuto messaggi o ha cambiato stato.
signal colloquio_updated(colloquio: Colloquio)
signal level_changed(level: int)
signal memory_changed
## Le pagine del Taccuino sono cambiate (aggiunte, rinominate, spostate nel cestino).
signal pages_changed
signal trash_changed
signal caos_changed(caos: int)
signal agenda_changed

const PER_LEVEL := 3
const MAX_LEVEL := 5
const STATE_FILE := "stato.json"
const PAGES_FILE := "appunti.json"
const TRASH_FILE := "cestino.json"
const AGENDA_FILE := "agenda.json"
const DEFAULT_SESSION_TIME := "21:00"
const DEFAULT_CHECKLIST: Array[String] = ["Preparare l'Incarico", "Leggere il memo dell'Agenzia", "Parlare con l'Entità", "Aggiornare le note del Fascicolo"]
const STATE_VERSION := 1
const CANONE_PATH := "res://data/canone.json"
const EXAMPLES_PATH := "res://data/esempi_voce.json"
const PROMPT_ENTITY := "res://data/prompt/entita.txt"
const PROMPT_SUMMARY := "res://data/prompt/riassunto.txt"
const PROMPT_MEMORY := "res://data/prompt/memoria.txt"
const PROMPT_GLITCH := "res://data/prompt/glitch.txt"
const PROMPT_SEARCH := "res://data/prompt/ricerca.txt"
const GLITCH_PATH := "res://data/glitch.json"
const NO_GLITCH := "nessuno"
## Risposte senza glitch richieste tra un glitch e il successivo: al massimo uno ogni quattro.
const GLITCH_GAP := 3
## Probabilità di una ricerca di AgencyOS: parte dal terzo scambio e cresce fino al massimo.
const SEARCH_FROM := 3
const SEARCH_BASE := 0.08
const SEARCH_STEP := 0.05
const SEARCH_MAX := 0.4
const SILENCE := "[il Manager resta in silenzio, in attesa]"
## Stima grossolana valida per i modelli locali: un token ogni 4 caratteri.
const CHARS_PER_TOKEN := 4.0
## Margine per i token che il server aggiunge da sé (ruoli, separatori).
const TOKEN_MARGIN := 128
const RECENT_SUMMARIES := 2

var colloqui: Array[Colloquio] = []
## Note del Manager sulla campagna: l'Entità le legge.
var note: String = ""
## Ricordi cumulativi e compatti dell'Entità, aggiornati a ogni chiusura.
var memoria: String = ""
var caos: int = 0
## Pagine del Taccuino: {id, titolo, sessione (0 = nessuna), testo, creato, modificato}.
var pages: Array[Dictionary] = []
## Elementi eliminati: {id, tipo, nome, dati, eliminato}.
var trash: Array[Dictionary] = []
## Sessioni programmate: {id, data (AAAA-MM-GG), ora, titolo, checklist: [{t, ok}]}.
var agenda: Array[Dictionary] = []
## Cartella del vault Obsidian per gli export di questa campagna; vuota = da scegliere.
var obsidian_folder: String = ""

## Memo dell'Agenzia, file dell'Entità e bozze nel cestino.
var correspondence: Correspondence

var _current_numero: int = 0
var _retrying := false
var _glitch_table: Dictionary = {}


func _ready() -> void:
	correspondence = Correspondence.new()
	correspondence.name = "Correspondence"
	add_child(correspondence)
	_load()


# --- Livello ---------------------------------------------------------------

func closed_count() -> int:
	return colloqui.filter(func(c: Colloquio) -> bool: return not c.is_open()).size()


func level() -> int:
	return mini(MAX_LEVEL, 1 + closed_count() / PER_LEVEL)


## Colloqui da chiudere per salire di livello; 0 se il livello è già massimo.
func colloqui_to_next_level() -> int:
	if level() >= MAX_LEVEL:
		return 0
	return PER_LEVEL - closed_count() % PER_LEVEL


# --- Colloqui --------------------------------------------------------------

func current() -> Colloquio:
	return find(_current_numero) if _current_numero > 0 else null


func find(numero: int) -> Colloquio:
	for c in colloqui:
		if c.numero == numero:
			return c
	return null


func open_colloquio() -> Colloquio:
	if current() != null:
		return current()
	var previous: Colloquio = colloqui.back() if not colloqui.is_empty() else null
	var c := Colloquio.new()
	c.numero = 1 if previous == null else previous.numero + 1
	c.livello = level()
	c.aperto = Time.get_datetime_string_from_system()
	c.add("sistema", "> CONNESSIONE STABILITA. CANALE NON REGISTRATO.")
	if previous != null and previous.livello < c.livello:
		c.add("sistema", "> LIVELLO DI ACCESSO DEL GENERAL MANAGER AGGIORNATO: %d." % c.livello)
	colloqui.append(c)
	_current_numero = c.numero
	save_colloquio(c)
	_save_state()
	colloqui_changed.emit()
	correspondence.on_session_opened(c, level())
	_retry_missing_summaries()
	return c


func add_message(c: Colloquio, chi: String, testo: String) -> Dictionary:
	var message := c.add(chi, testo)
	save_colloquio(c)
	colloquio_updated.emit(c)
	return message


func save_colloquio(c: Colloquio) -> void:
	Save.write_campaign(Colloquio.file_name_for(c.numero), c.to_dict())


## Chiude il colloquio: riassunto dal punto di vista dell'Entità e memoria aggiornata.
## Se il modello non risponde il colloquio si chiude comunque; il riassunto si ritenta più avanti.
func close_colloquio(c: Colloquio) -> void:
	var old_level := level()
	add_message(c, "sistema", "> SESSIONE TERMINATA DAL GENERAL MANAGER.")
	c.riassunto = await summarize(c)
	c.stato = "chiuso"
	c.chiuso = Time.get_datetime_string_from_system()
	if _current_numero == c.numero:
		_current_numero = 0
	save_colloquio(c)
	_save_state()
	if c.riassunto != "":
		await _merge_memory(c)
	colloquio_updated.emit(c)
	colloqui_changed.emit()
	if level() != old_level:
		level_changed.emit(level())
	# Bozza, memo del prossimo turno ed eventuale file: in sottofondo, senza far aspettare.
	correspondence.on_session_closed(c, old_level, level())


## Riserva di Caos della Filiale; non scende sotto zero.
func set_caos(value: int) -> void:
	caos = maxi(0, value)
	_save_state()
	caos_changed.emit(caos)


func add_caos(amount: int) -> void:
	set_caos(caos + amount)


## Protocollo di azzeramento: cancella colloqui, ricordi, posta, file, cestino e Caos;
## il livello torna a 1. Restano impostazioni, cartella del vault e agenda;
## keep_notes conserva anche le note del Manager e il Taccuino.
func reset_filiale(keep_notes: bool) -> void:
	for file_name in Save.list_campaign("colloqui"):
		Save.delete_campaign("colloqui/" + file_name)
	for relative in [Correspondence.MAIL_FILE, Correspondence.FILES_FILE, TRASH_FILE]:
		Save.delete_campaign(relative)
	if not keep_notes:
		Save.delete_campaign(PAGES_FILE)
		note = ""
		pages.clear()
	colloqui.clear()
	trash.clear()
	memoria = ""
	caos = 0
	_current_numero = 0
	_save_state()
	correspondence.load_data()
	colloqui_changed.emit()
	memory_changed.emit()
	trash_changed.emit()
	pages_changed.emit()
	caos_changed.emit(caos)


func set_note(text: String) -> void:
	note = text
	_save_state()


## Correzione del Manager ai ricordi di un colloquio: da qui in poi vale come verità.
func set_riassunto(c: Colloquio, text: String) -> void:
	c.riassunto = text.strip_edges()
	save_colloquio(c)
	colloquio_updated.emit(c)


## Correzione del Manager alla memoria cumulativa.
func set_memoria(text: String) -> void:
	memoria = text.strip_edges()
	_save_state()
	memory_changed.emit()


## Sezioni del Canone così come sono nel file dati.
func canone_sections() -> Array:
	var data: Variant = Save.read_json(CANONE_PATH, {})
	return (data as Dictionary).get("sezioni", []) if data is Dictionary else []


# --- Taccuino --------------------------------------------------------------

## Pagine dalla più modificata.
func pages_by_modified() -> Array[Dictionary]:
	var sorted := pages.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.modificato) > str(b.modificato))
	return sorted


func find_page(id: String) -> Dictionary:
	for page in pages:
		if page.id == id:
			return page
	return {}


func pages_for_session(numero: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for page in pages:
		if int(page.sessione) == numero:
			result.append(page)
	return result


## Nuova pagina collegata alla sessione indicata; -1 = il colloquio aperto o l'ultimo.
func new_page(sessione: int = -1) -> Dictionary:
	if sessione < 0:
		var open := current()
		sessione = open.numero if open != null else (colloqui.back().numero if not colloqui.is_empty() else 0)
	var now := Time.get_datetime_string_from_system()
	var title := "Sessione %03d · appunti" % sessione if sessione > 0 else "Appunti del %s" % ItalianDate.numeric(now)
	var same := pages.filter(func(p: Dictionary) -> bool: return p.titolo == title or str(p.titolo).begins_with(title + " (")).size()
	if same > 0:
		title += " (%d)" % (same + 1)
	var page := {"id": "a-%d" % Time.get_unix_time_from_system() + "-%d" % randi_range(100, 999), "titolo": title, "sessione": sessione, "testo": "", "creato": now, "modificato": now}
	pages.append(page)
	_save_pages()
	pages_changed.emit()
	return page


## Da chiamare dopo aver modificato una pagina; quiet evita di ridisegnare l'elenco.
func save_page(page: Dictionary, quiet: bool = false) -> void:
	page.modificato = Time.get_datetime_string_from_system()
	_save_pages()
	if not quiet:
		pages_changed.emit()


func trash_page(page: Dictionary) -> void:
	pages.erase(page)
	_save_pages()
	add_to_trash({"id": "x-" + str(page.id), "tipo": "appunti", "nome": page.titolo, "dati": page, "eliminato": Time.get_datetime_string_from_system()})
	pages_changed.emit()


## Elementi del cestino: pagine del Taccuino, bozze dell'Entità.
func add_to_trash(item: Dictionary) -> void:
	trash.append(item)
	_save_trash()


## Solo le pagine del Taccuino si ripristinano; le bozze dell'Entità no.
func restore_from_trash(item: Dictionary) -> void:
	if item.get("tipo", "") != "appunti":
		return
	var page: Dictionary = item.dati.duplicate()
	page.modificato = Time.get_datetime_string_from_system()
	pages.append(page)
	trash.erase(item)
	_save_pages()
	_save_trash()
	pages_changed.emit()


func delete_from_trash(item: Dictionary) -> void:
	trash.erase(item)
	_save_trash()


func empty_trash() -> void:
	trash.clear()
	_save_trash()


func _save_trash() -> void:
	Save.write_campaign(TRASH_FILE, trash)
	trash_changed.emit()


func set_obsidian_folder(path: String) -> void:
	obsidian_folder = path
	_save_state()


# --- Agenda ----------------------------------------------------------------

func session_on(day: String) -> Dictionary:
	for session in agenda:
		if session.data == day:
			return session
	return {}


func schedule_session(day: String) -> Dictionary:
	var existing := session_on(day)
	if not existing.is_empty():
		return existing
	var checklist: Array = []
	for item in DEFAULT_CHECKLIST:
		checklist.append({"t": item, "ok": false})
	var session := {"id": "d-" + day, "data": day, "ora": DEFAULT_SESSION_TIME, "titolo": "", "checklist": checklist}
	agenda.append(session)
	save_agenda()
	return session


func cancel_session(session: Dictionary) -> void:
	agenda.erase(session)
	save_agenda()


func save_agenda() -> void:
	Save.write_campaign(AGENDA_FILE, agenda)
	agenda_changed.emit()


## La prossima sessione da oggi in poi, oppure {}.
func next_session() -> Dictionary:
	var today := ItalianDate.today()
	var best := {}
	for session in agenda:
		var key := str(session.data) + str(session.get("ora", ""))
		if str(session.data) >= today and (best.is_empty() or key < str(best.data) + str(best.get("ora", ""))):
			best = session
	return best


# --- Glitch e ricerche -----------------------------------------------------

## Effetti della linea dal file dati: nome -> {descrizione, momento, webcam, movimento}.
func glitch_table() -> Dictionary:
	if _glitch_table.is_empty():
		var data: Variant = Save.read_json(GLITCH_PATH, {})
		if data is Dictionary:
			_glitch_table = data.get("glitch", {})
	return _glitch_table


## Vero se l'ultima risposta dell'Entità può avere un glitch: mai due di fila,
## al massimo uno ogni quattro risposte. Va chiamata dopo aver salvato la risposta.
func can_glitch(c: Colloquio) -> bool:
	var since_last := 0
	var skipped_current := false
	for i in range(c.messaggi.size() - 1, -1, -1):
		var m: Dictionary = c.messaggi[i]
		if m.chi != "entita":
			continue
		if not skipped_current:
			skipped_current = true
			continue
		if str(m.get("glitch", "")) != "":
			return since_last >= GLITCH_GAP
		since_last += 1
	return true


## Seconda chiamata breve: sceglie un effetto per l'ultima risposta, "" se nessuno.
## Usa uno schema JSON; se il server non lo accetta riprova senza e cerca il nome nel testo.
func choose_glitch(c: Colloquio) -> String:
	var table := glitch_table()
	if table.is_empty():
		return ""
	var entity_text := ""
	var manager_text := ""
	for i in range(c.messaggi.size() - 1, -1, -1):
		var m: Dictionary = c.messaggi[i]
		if entity_text == "" and m.chi == "entita":
			entity_text = str(m.testo)
		elif entity_text != "" and m.chi == "manager":
			manager_text = str(m.testo)
			break
	var lines: PackedStringArray = []
	for glitch_name: String in table:
		lines.append("- %s: %s" % [glitch_name, table[glitch_name].get("descrizione", "")])
	var prompt := _read_text(PROMPT_GLITCH).format({
		"elenco": "\n".join(lines),
		"manager": manager_text if manager_text != "" else "(niente)",
		"entita": entity_text,
	})
	var names: Array = [NO_GLITCH]
	names.append_array(table.keys())
	var schema := {
		"type": "json_schema",
		"json_schema": {
			"name": "glitch",
			"strict": true,
			"schema": {
				"type": "object",
				"properties": {"glitch": {"type": "string", "enum": names}},
				"required": ["glitch"],
				"additionalProperties": false,
			},
		},
	}
	var messages: Array[Dictionary] = [{"role": "user", "content": prompt}]
	var options := {"stream": false, "temperature": 0.2, "max_tokens": 80, "extra": {"response_format": schema}}
	var request := Brain.chat(messages, options)
	if not request.is_done:
		await request.finished
	if not request.ok() and request.http_status >= 400 and request.http_status < 500:
		options.erase("extra")
		request = Brain.chat(messages, options)
		if not request.is_done:
			await request.finished
	if not request.ok():
		push_warning("Campaign: scelta del glitch fallita: %s" % request.error)
		return ""
	return _parse_glitch(request.text, table)


func search_chance(c: Colloquio) -> float:
	var replies := c.messaggi.filter(func(m: Dictionary) -> bool: return m.chi == "entita").size()
	if replies < SEARCH_FROM:
		return 0.0
	return minf(SEARCH_BASE + (replies - SEARCH_FROM) * SEARCH_STEP, SEARCH_MAX)


## Battuta di regia che chiede all'Entità di nascondersi durante una ricerca.
func search_event() -> String:
	return _read_text(PROMPT_SEARCH).strip_edges()


func record_search(c: Colloquio) -> void:
	c.ricerche.append(Time.get_datetime_string_from_system())
	save_colloquio(c)


func _parse_glitch(text: String, table: Dictionary) -> String:
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary:
		var chosen := str(data.get("glitch", "")).to_lower()
		return chosen if table.has(chosen) else ""
	# Senza schema: il primo nome di effetto che compare nel testo.
	var lower := text.to_lower()
	var best := ""
	var best_at := -1
	for glitch_name: String in table:
		var at := lower.find(glitch_name)
		if at >= 0 and (best_at < 0 or at < best_at):
			best = glitch_name
			best_at = at
	return best


# --- Prompt ----------------------------------------------------------------

## Messaggi per il modello: prompt di sistema e la parte più recente del colloquio
## che entra nel contesto. extra_user è un'eventuale battuta aggiunta in fondo.
func build_messages(c: Colloquio, extra_user: String = "") -> Array[Dictionary]:
	var system := entity_prompt(c)
	var budget := Brain.context_tokens() - int(Brain.get_setting("max_risposta")) - _tokens(system) - TOKEN_MARGIN
	budget -= _tokens(extra_user)
	var history: Array[Dictionary] = []
	for i in range(c.messaggi.size() - 1, -1, -1):
		var m: Dictionary = c.messaggi[i]
		if m.chi == "sistema":
			continue
		var cost := _tokens(m.testo) + 4
		if cost > budget and not history.is_empty():
			break
		budget -= cost
		history.push_front({"role": "user" if m.chi == "manager" else "assistant", "content": str(m.testo)})
	if extra_user != "":
		history.append({"role": "user", "content": extra_user})
	if history.is_empty() or history.back().role != "user":
		history.append({"role": "user", "content": SILENCE})
	var messages: Array[Dictionary] = [{"role": "system", "content": system}]
	# Alcuni modelli rifiutano due messaggi di fila con lo stesso ruolo: li unisco.
	for entry in history:
		if messages.size() > 1 and messages.back().role == entry.role:
			messages.back().content += "\n\n" + entry.content
		else:
			messages.append(entry)
	return messages


func entity_prompt(c: Colloquio) -> String:
	return _read_text(PROMPT_ENTITY).format({
		"livello": level(),
		"canone": _canone_text(level()),
		"note": note.strip_edges() if note.strip_edges() != "" else "(quasi niente: non sai ancora bene chi sia questo Manager. sei curiosa, e un po' diffidente.)",
		"memoria": memoria.strip_edges() if memoria.strip_edges() != "" else "(nessuno: è la prima volta che riesci a raggiungerlo)",
		"riassunti": _recent_summaries(c),
		"esempi": _examples_text(),
		"numero": c.numero,
		"memo": correspondence.prompt_memos(),
		"file": correspondence.prompt_files(),
		"comandi": correspondence.prompt_commands(level()),
		"bozze": correspondence.prompt_drafts(trash),
		"incarico": _next_session_text(),
	})


# --- Riassunti e memoria ---------------------------------------------------

func summarize(c: Colloquio) -> String:
	var lines: PackedStringArray = []
	for m in c.messaggi:
		if m.chi != "sistema":
			lines.append(("MANAGER: " if m.chi == "manager" else "ENTITÀ: ") + str(m.testo))
	if lines.is_empty():
		return ""
	var max_chars := int((Brain.context_tokens() - int(Brain.get_setting("max_risposta")) - 600) * CHARS_PER_TOKEN)
	var transcript := "\n".join(lines).right(maxi(max_chars, 2000))
	var prompt := _read_text(PROMPT_SUMMARY).format({"numero": c.numero, "trascrizione": transcript})
	return await _ask(prompt)


func _merge_memory(c: Colloquio) -> void:
	if memoria.strip_edges() == "":
		memoria = c.riassunto
	else:
		var prompt := _read_text(PROMPT_MEMORY).format({"memoria": memoria, "numero": c.numero, "riassunto": c.riassunto})
		var merged := await _ask(prompt)
		# Se la fusione fallisce accodo, così il ricordo non va perso.
		memoria = merged if merged != "" else memoria + "\n" + c.riassunto
	_save_state()
	memory_changed.emit()


func _retry_missing_summaries() -> void:
	if _retrying:
		return
	_retrying = true
	for c in colloqui.duplicate():
		if c.is_open() or c.riassunto != "" or c.spoken_count() == 0:
			continue
		var summary := await summarize(c)
		if summary == "":
			break
		c.riassunto = summary
		save_colloquio(c)
		await _merge_memory(c)
	_retrying = false


## Chiamata breve senza streaming; "" se il modello non risponde.
func _ask(prompt: String) -> String:
	var request := Brain.chat([{"role": "user", "content": prompt}], {"stream": false, "temperature": 0.4})
	if not request.is_done:
		await request.finished
	if not request.ok():
		push_warning("Campaign: chiamata al modello fallita: %s" % request.error)
		return ""
	return request.text.strip_edges()


# --- Testi di supporto -----------------------------------------------------

func _canone_text(current_level: int) -> String:
	var blocks: PackedStringArray = []
	for section: Dictionary in canone_sections():
		var lv := int(section.get("livello", 0))
		var head: String
		if lv == 0:
			head = "## %s (sempre valido)" % section.titolo
		elif lv <= current_level:
			head = "## %s (livello %d: puoi parlarne apertamente)" % [section.titolo, lv]
		else:
			head = "## %s (livello %d: lo sai, ma il Manager NON ha ancora questo accesso. Non rivelarlo: al massimo un'allusione, una frase troncata, un \"non ancora\")" % [section.titolo, lv]
		var points: PackedStringArray = []
		for point: String in section.get("punti", []):
			points.append("- " + point)
		blocks.append(head + "\n" + "\n".join(points))
	return "\n\n".join(blocks)


func _recent_summaries(c: Colloquio) -> String:
	var parts: PackedStringArray = []
	for other in colloqui:
		if other != c and other.riassunto != "":
			parts.append("Colloquio %d:\n%s" % [other.numero, other.riassunto])
	if parts.is_empty():
		return "(nessuno)"
	return "\n\n".join(parts.slice(-RECENT_SUMMARIES))


func _next_session_text() -> String:
	var session := next_session()
	if session.is_empty():
		return "(non lo sai)"
	var text := ItalianDate.weekday_short(str(session.data)) + " " + ItalianDate.numeric(str(session.data))
	if str(session.get("ora", "")) != "":
		text += " alle " + str(session.ora)
	if str(session.get("titolo", "")) != "":
		text += " · " + str(session.titolo)
	return text


func _examples_text() -> String:
	var data: Variant = Save.read_json(EXAMPLES_PATH, {})
	var parts: PackedStringArray = []
	for example: Dictionary in (data as Dictionary).get("esempi", []):
		parts.append("MANAGER: %s\nTU: %s" % [example.get("manager", ""), example.get("entita", "")])
	return "\n\n".join(parts) if not parts.is_empty() else "(nessuno)"


func _read_text(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Campaign: non riesco a leggere %s." % path)
	return text


func _tokens(text: String) -> int:
	return ceili(text.length() / CHARS_PER_TOKEN)


# --- Persistenza -----------------------------------------------------------

func _load() -> void:
	var state: Variant = Save.read_campaign(STATE_FILE, {})
	if state is Dictionary:
		note = str(state.get("note", ""))
		memoria = str(state.get("memoria", ""))
		caos = int(state.get("caos", 0))
		_current_numero = int(state.get("corrente", 0))
		obsidian_folder = str(state.get("cartella_obsidian", ""))
	for page: Variant in Save.read_campaign(PAGES_FILE, []):
		if page is Dictionary:
			pages.append(page)
	for item: Variant in Save.read_campaign(TRASH_FILE, []):
		if item is Dictionary:
			trash.append(item)
	correspondence.load_data()
	for session: Variant in Save.read_campaign(AGENDA_FILE, []):
		if session is Dictionary:
			agenda.append(session)
	for file_name in Save.list_campaign("colloqui"):
		var data: Variant = Save.read_campaign("colloqui/" + file_name, null)
		if data is Dictionary:
			colloqui.append(Colloquio.from_dict(data))
	colloqui.sort_custom(func(a: Colloquio, b: Colloquio) -> bool: return a.numero < b.numero)
	var open := current()
	if open == null or not open.is_open():
		_current_numero = 0
		# Un colloquio rimasto aperto senza essere il corrente (es. crash) torna attivo.
		for c in colloqui:
			if c.is_open():
				_current_numero = c.numero


func _save_state() -> void:
	Save.write_campaign(STATE_FILE, {
		"versione": STATE_VERSION,
		"note": note,
		"corrente": _current_numero,
		"caos": caos,
		"memoria": memoria,
		"cartella_obsidian": obsidian_folder,
	})


func _save_pages() -> void:
	Save.write_campaign(PAGES_FILE, pages)
