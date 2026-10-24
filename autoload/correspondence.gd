class_name Correspondence
extends Node
## Ciò che arriva al Manager fuori dalla linea: memo dell'Agenzia (AMail),
## file lasciati dall'Entità sulla scrivania e bozze buttate nel cestino.
## Si genera in sottofondo alla chiusura di una sessione, una richiesta alla volta,
## e memo e file si consegnano all'apertura della sessione successiva.

signal mail_changed
signal files_changed
## kind: "memo" oppure "file"; item: il memo o il file appena consegnato.
signal delivered(kind: String, item: Dictionary)
## Vero mentre l'Agenzia sta scrivendo un memo (AMail mostra "ricezione in corso").
signal receiving_changed(active: bool)

const MAIL_FILE := "posta.json"
const FILES_FILE := "file.json"
const SECRETS_PATH := "res://data/comandi_segreti.json"
const PROMPT_MEMO := "res://data/prompt/memo.txt"
const PROMPT_FILE := "res://data/prompt/file.txt"
const PROMPT_DRAFT := "res://data/prompt/bozza.txt"
const SENDERS: Array[String] = ["Risorse Umane", "Ufficio Controlli Qualità", "Direzione di Filiale", "Ufficio Conformità", "Comitato Benessere Dipendenti", "Archivio Centrale", "AgencyOS (messaggio automatico)"]
## Una bozza nel cestino dopo una sessione su due circa, dalla seconda in poi.
const DRAFT_CHANCE := 0.45
const DRAFT_FROM := 2
## Limiti di lunghezza nel prompt dell'Entità (modelli locali, contesto piccolo).
const PROMPT_MEMOS := 3
const PROMPT_MEMO_CHARS := 600
const PROMPT_FILE_CHARS := 900
const PROMPT_DRAFT_CHARS := 400

## {id, sessione, creato, mittente, oggetto, corpo, letta, consegnata}
var posta: Array[Dictionary] = []
## {id, livello, nome, contenuto, originale, creato, letto, corretto, consegnato}
var files: Array[Dictionary] = []
var receiving := false

var _queue: Array[Callable] = []
var _running := false
var _secrets: Array = []


func load_data() -> void:
	posta.clear()
	files.clear()
	for item: Variant in Save.read_campaign(MAIL_FILE, []):
		if item is Dictionary:
			posta.append(item)
	for item: Variant in Save.read_campaign(FILES_FILE, []):
		if item is Dictionary:
			files.append(item)


# --- Posta -----------------------------------------------------------------

## Memo già consegnati, dal più recente.
func delivered_mail() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for memo in posta:
		if memo.get("consegnata", true):
			result.append(memo)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.creato) > str(b.creato))
	return result


func unread_count() -> int:
	return delivered_mail().filter(func(m: Dictionary) -> bool: return not m.letta).size()


func find_mail(id: String) -> Dictionary:
	for memo in posta:
		if memo.id == id:
			return memo
	return {}


## Il memo recapitato all'inizio della sessione indicata, se c'è.
func mail_for_session(numero: int) -> Dictionary:
	for memo in posta:
		if int(memo.sessione) == numero and memo.get("consegnata", true):
			return memo
	return {}


func mark_read(memo: Dictionary) -> void:
	if memo.letta:
		return
	memo.letta = true
	Save.write_campaign(MAIL_FILE, posta)
	mail_changed.emit()


# --- File sulla scrivania --------------------------------------------------

func delivered_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file in files:
		if file.get("consegnato", true):
			result.append(file)
	return result


func find_file(id: String) -> Dictionary:
	for file in files:
		if file.id == id:
			return file
	return {}


## Cerca per nome esatto, poi per inizio del nome (come TYPE nel prompt dei comandi).
func find_file_by_name(name_or_prefix: String) -> Dictionary:
	var wanted := name_or_prefix.to_lower()
	if wanted == "":
		return {}
	for file in delivered_files():
		if str(file.nome).to_lower() == wanted:
			return file
	for file in delivered_files():
		if str(file.nome).to_lower().begins_with(wanted):
			return file
	return {}


func mark_file_read(file: Dictionary) -> void:
	if file.letto:
		return
	file.letto = true
	_save_files()


## La correzione del Manager diventa la verità per l'Entità.
func correct_file(file: Dictionary, text: String) -> void:
	if text == file.contenuto:
		return
	if str(file.get("originale", "")) == "":
		file.originale = file.contenuto
	file.contenuto = text
	file.corretto = text != file.originale
	file.corretto_il = Time.get_datetime_string_from_system()
	_save_files()


func restore_file(file: Dictionary) -> void:
	if str(file.get("originale", "")) == "":
		return
	file.contenuto = file.originale
	file.corretto = false
	_save_files()


# --- Comandi segreti -------------------------------------------------------

## [{comando, livello, righe: [[tipo, testo], …]}] dal file dati.
func secret_commands() -> Array:
	if _secrets.is_empty():
		var data: Variant = Save.read_json(SECRETS_PATH, {})
		if data is Dictionary:
			_secrets = data.get("comandi", [])
	return _secrets


func unlocked_commands(level: int) -> Array:
	return secret_commands().filter(func(s: Dictionary) -> bool: return int(s.livello) <= level)


# --- Testi per il prompt dell'Entità ---------------------------------------

func prompt_memos() -> String:
	var parts: PackedStringArray = []
	var recent := delivered_mail().slice(0, PROMPT_MEMOS)
	recent.reverse()
	for memo in recent:
		parts.append("Da: %s · Oggetto: %s\n%s" % [memo.mittente, memo.oggetto, str(memo.corpo).left(PROMPT_MEMO_CHARS)])
	return "\n\n".join(parts) if not parts.is_empty() else "(nessuno, per ora)"


func prompt_files() -> String:
	var parts: PackedStringArray = []
	for file in delivered_files():
		var head := "File \"%s\"%s:" % [file.nome, " (CORRETTO DAL MANAGER: questa versione è la verità)" if file.get("corretto", false) else ""]
		parts.append(head + "\n" + str(file.contenuto).left(PROMPT_FILE_CHARS))
	return "\n\n".join(parts) if not parts.is_empty() else "(nessuno, per ora)"


func prompt_commands(level: int) -> String:
	var names: PackedStringArray = []
	for secret: Dictionary in unlocked_commands(level):
		names.append(str(secret.comando))
	return ", ".join(names) if not names.is_empty() else "(nessuno, per ora: non parlarne)"


func prompt_drafts(trash: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for item in trash:
		if item.get("tipo", "") == "bozza":
			parts.append("\"%s\": %s" % [item.nome, str(item.get("testo", "")).left(PROMPT_DRAFT_CHARS)])
	return "\n".join(parts) if not parts.is_empty() else "(nessuno)"


# --- Ganci delle sessioni --------------------------------------------------

## All'apertura: consegna ciò che era pronto; se manca il memo del turno, lo scrive ora.
func on_session_opened(c: Colloquio, level: int) -> void:
	for memo in posta:
		if not memo.get("consegnata", true) and int(memo.sessione) <= c.numero:
			memo.sessione = c.numero
			memo.creato = Time.get_datetime_string_from_system()
			memo.consegnata = true
			Save.write_campaign(MAIL_FILE, posta)
			mail_changed.emit()
			delivered.emit("memo", memo)
	for file in files:
		if not file.get("consegnato", true):
			file.consegnato = true
			file.creato = Time.get_datetime_string_from_system()
			_save_files()
			delivered.emit("file", file)
	var previous := Campaign.find(c.numero - 1)
	if mail_for_session(c.numero).is_empty() and not _has_pending_mail():
		_enqueue(_make_memo.bind(c.numero, previous.ricerche.size() if previous != null else 0, true))
	if _file_for_level(level).is_empty():
		_enqueue(_make_file.bind(level, true))


## Alla chiusura: bozza (a volte), memo del prossimo turno e file se il livello è salito.
func on_session_closed(c: Colloquio, level_before: int, level_after: int) -> void:
	if c.numero >= DRAFT_FROM and randf() < DRAFT_CHANCE and c.spoken_count() > 0:
		_enqueue(_make_draft.bind(c))
	_enqueue(_make_memo.bind(c.numero + 1, c.ricerche.size(), false))
	if level_after > level_before:
		_enqueue(_make_file.bind(level_after, false))


# --- Generazione -----------------------------------------------------------

func _make_memo(sessione: int, searches: int, deliver_now: bool) -> void:
	if not mail_for_session(sessione).is_empty() or (not deliver_now and _has_pending_mail()):
		return
	_set_receiving(true)
	var sent: PackedStringArray = []
	for memo in delivered_mail().slice(0, 8):
		sent.append("- " + str(memo.oggetto))
	var prompt := _read(PROMPT_MEMO).format({
		"turno": "È il primo giorno del Manager in questa posizione: scrivi un memo di benvenuto e inserimento." if sessione == 1 else "È l'inizio del turno numero %d del Manager." % sessione,
		"sospetto": "Durante il turno precedente AgencyOS ha avviato %d %s di attività anomala sul canale del Manager, senza trovare nulla: esprimi un sospetto cortese, senza accusare." % [searches, "ricerca" if searches == 1 else "ricerche"] if searches > 0 else "",
		"note": "DATI DEL FASCICOLO DEL MANAGER (usali se servono, senza elencarli):\n" + Campaign.note.strip_edges().left(2000) if Campaign.note.strip_edges() != "" else "",
		"inviati": "MEMO GIÀ INVIATI (non ripeterne il tema):\n" + "\n".join(sent) if not sent.is_empty() else "",
		"mittenti": ", ".join(SENDERS),
	})
	var out := await LlmJson.ask(prompt, {
		"mittente": {"type": "string", "enum": SENDERS},
		"oggetto": {"type": "string"},
		"corpo": {"type": "string"},
	})
	_set_receiving(false)
	if str(out.get("oggetto", "")).strip_edges() == "" or str(out.get("corpo", "")).strip_edges() == "":
		return
	var memo := {
		"id": "m-%03d" % sessione,
		"sessione": sessione,
		"creato": Time.get_datetime_string_from_system(),
		"mittente": str(out.get("mittente", "Risorse Umane")).left(60),
		"oggetto": str(out.oggetto).strip_edges().left(140),
		"corpo": _clean_body(str(out.corpo)).left(4000),
		"letta": false,
		"consegnata": deliver_now,
	}
	posta.append(memo)
	Save.write_campaign(MAIL_FILE, posta)
	if deliver_now:
		mail_changed.emit()
		delivered.emit("memo", memo)


func _make_file(level: int, deliver_now: bool) -> void:
	if not _file_for_level(level).is_empty():
		return
	var section := _canone_section(level)
	if section.is_empty():
		return
	var points: PackedStringArray = []
	for point: String in section.get("punti", []):
		points.append("- " + point)
	var secret := ""
	for s: Dictionary in secret_commands():
		if int(s.livello) == level:
			secret = "Da qualche parte suggerisci al Manager di digitare %s nel prompt dei comandi, senza spiegare cosa succede." % s.comando
	var prompt := _read(PROMPT_FILE).format({
		"titolo": section.titolo,
		"punti": "\n".join(points),
		"comando": secret,
		"note": "Ciò che sai del Manager e della Filiale:\n" + Campaign.note.strip_edges().left(1500) if Campaign.note.strip_edges() != "" else "",
	})
	var out := await LlmJson.ask(prompt, {"nome": {"type": "string"}, "contenuto": {"type": "string"}})
	var file_name := _clean_file_name(str(out.get("nome", "")), "crepa_0%d" % level, ["txt", "log"])
	var content := str(out.get("contenuto", "")).strip_edges()
	if content == "":
		# Se il modello tace, l'Entità lascia almeno i suoi appunti grezzi.
		content = "\n\n".join(section.get("punti", [])).to_lower()
	var file := {
		"id": "f-%d" % level,
		"livello": level,
		"nome": file_name,
		"contenuto": content.left(4000),
		"originale": "",
		"creato": Time.get_datetime_string_from_system(),
		"letto": false,
		"corretto": false,
		"consegnato": deliver_now,
	}
	files.append(file)
	_save_files()
	if deliver_now:
		delivered.emit("file", file)


func _make_draft(c: Colloquio) -> void:
	var id := "b-%03d" % c.numero
	for item in Campaign.trash:
		if item.id == id:
			return
	var prompt := _read(PROMPT_DRAFT).format({"ricordi": c.riassunto if c.riassunto != "" else "(confusi)"})
	var out := await LlmJson.ask(prompt, {"nome": {"type": "string"}, "testo": {"type": "string"}}, 0.9, 500)
	var text := str(out.get("testo", "")).strip_edges()
	if text == "":
		return
	Campaign.add_to_trash({
		"id": id,
		"tipo": "bozza",
		"nome": _clean_file_name(str(out.get("nome", "")), "non_inviato_%03d" % c.numero, ["txt"]),
		"testo": text.left(1500),
		"sessione": c.numero,
		"eliminato": Time.get_datetime_string_from_system(),
	})


## Le richieste al modello partono una alla volta, nell'ordine in cui sono state chieste.
func _enqueue(job: Callable) -> void:
	_queue.append(job)
	if _running:
		return
	_running = true
	while not _queue.is_empty():
		var next: Callable = _queue.pop_front()
		await next.call()
	_running = false


# --- Utilità ---------------------------------------------------------------

func _has_pending_mail() -> bool:
	return posta.any(func(m: Dictionary) -> bool: return not m.get("consegnata", true))


func _file_for_level(level: int) -> Dictionary:
	for file in files:
		if int(file.livello) == level:
			return file
	return {}


func _canone_section(level: int) -> Dictionary:
	for section: Dictionary in Campaign.canone_sections():
		if int(section.get("livello", 0)) == level:
			return section
	return {}


## Minuscolo, solo lettere, numeri e trattini bassi, estensione ammessa, nome non ripetuto.
func _clean_file_name(raw: String, fallback: String, extensions: Array[String]) -> String:
	var regex := RegEx.create_from_string("[^a-z0-9_.]")
	var cleaned := regex.sub(raw.to_lower(), "_", true).left(24)
	var dot := cleaned.rfind(".")
	var extension := cleaned.substr(dot + 1) if dot >= 0 else ""
	var base := cleaned.left(dot) if dot >= 0 else cleaned
	if base == "":
		base = fallback
	if not extension in extensions:
		extension = extensions[0]
	var file_name := "%s.%s" % [base, extension]
	var taken := files.any(func(f: Dictionary) -> bool: return f.nome == file_name)
	return "%s_%d.%s" % [base, randi_range(2, 99), extension] if taken else file_name


## I modelli piccoli ripetono l'intestazione nel corpo e usano il markdown: li tolgo.
static func _clean_body(text: String) -> String:
	var kept: PackedStringArray = []
	for line in text.replace("**", "").replace("__", "").split("\n"):
		if kept.is_empty() and _is_heading(line.strip_edges()):
			continue
		kept.append(line.replace(", [Nome del Manager]", "").replace(" [Nome del Manager]", "").replace("[Nome del Manager]", ""))
	return "\n".join(kept).strip_edges()


## Righe da saltare in testa al memo: vuote, "Oggetto: …" e simili, titoli in maiuscolo.
static func _is_heading(line: String) -> bool:
	if line == "":
		return true
	var header := RegEx.create_from_string("^(memorandum|memo interno|mittente|oggetto|data|a|da|destinatario)\\b.*:")
	if header.search(line.to_lower()) != null:
		return true
	return line.length() > 3 and line.to_upper() == line


func _set_receiving(active: bool) -> void:
	receiving = active
	receiving_changed.emit(active)


func _save_files() -> void:
	Save.write_campaign(FILES_FILE, files)
	files_changed.emit()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)
