class_name Correspondence
extends Node
## What reaches the Manager outside the line: Agency memos (AMail),
## files the Entity leaves on the desktop and drafts thrown in the trash.
## Generated in the background when a session closes, one request at a time;
## memos and files are delivered when the next session opens.

signal mail_changed
signal files_changed
## kind: "memo" or "file"; item: the memo or file just delivered.
signal delivered(kind: String, item: Dictionary)
## True while the Agency is writing a memo (AMail shows "ricezione in corso").
signal receiving_changed(active: bool)

const MAIL_FILE := "mail.json"
const FILES_FILE := "files.json"
const SECRETS_PATH := "res://data/secret_commands.json"
const PROMPT_MEMO := "res://data/prompt/memo.txt"
const PROMPT_FILE := "res://data/prompt/file.txt"
const PROMPT_DRAFT := "res://data/prompt/draft.txt"
## Shown on screen and read by the model, so in Italian.
const SENDERS: Array[String] = ["Risorse Umane", "Ufficio Controlli Qualità", "Direzione di Filiale", "Ufficio Conformità", "Comitato Benessere Dipendenti", "Archivio Centrale", "AgencyOS (messaggio automatico)"]
## A draft in the trash after about one session in two, from the second on.
const DRAFT_CHANCE := 0.45
const DRAFT_FROM := 2
## Length limits in the Entity's prompt (local models, small context).
const PROMPT_MEMOS := 3
const PROMPT_MEMO_CHARS := 600
const PROMPT_FILE_CHARS := 900
const PROMPT_DRAFT_CHARS := 400

## {id, session, created, sender, subject, body, read, delivered}
var mail: Array[Dictionary] = []
## {id, level, name, content, original, created, read, corrected, corrected_at?, delivered}
var files: Array[Dictionary] = []
var receiving := false

var _queue: Array[Callable] = []
var _running := false
var _secrets: Array = []


func load_data() -> void:
	mail.clear()
	files.clear()
	for item: Variant in Save.read_campaign(MAIL_FILE, []):
		if item is Dictionary:
			mail.append(item)
	for item: Variant in Save.read_campaign(FILES_FILE, []):
		if item is Dictionary:
			files.append(item)


# --- Mail ------------------------------------------------------------------

## Memos already delivered, newest first.
func delivered_mail() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for memo in mail:
		if memo.get("delivered", true):
			result.append(memo)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.created) > str(b.created))
	return result


func unread_count() -> int:
	return delivered_mail().filter(func(m: Dictionary) -> bool: return not m.read).size()


func find_mail(id: String) -> Dictionary:
	for memo in mail:
		if memo.id == id:
			return memo
	return {}


## The memo delivered at the start of the given session, if any.
func mail_for_session(number: int) -> Dictionary:
	for memo in mail:
		if int(memo.session) == number and memo.get("delivered", true):
			return memo
	return {}


func mark_read(memo: Dictionary) -> void:
	if memo.read:
		return
	memo.read = true
	Save.write_campaign(MAIL_FILE, mail)
	mail_changed.emit()


# --- Desktop files ---------------------------------------------------------

func delivered_files() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for file in files:
		if file.get("delivered", true):
			result.append(file)
	return result


func find_file(id: String) -> Dictionary:
	for file in files:
		if file.id == id:
			return file
	return {}


## Looks for the exact name, then for the start of the name (like TYPE in the command prompt).
func find_file_by_name(name_or_prefix: String) -> Dictionary:
	var wanted := name_or_prefix.to_lower()
	if wanted == "":
		return {}
	for file in delivered_files():
		if str(file.name).to_lower() == wanted:
			return file
	for file in delivered_files():
		if str(file.name).to_lower().begins_with(wanted):
			return file
	return {}


func mark_file_read(file: Dictionary) -> void:
	if file.read:
		return
	file.read = true
	_save_files()


## The Manager's correction becomes the truth for the Entity.
func correct_file(file: Dictionary, text: String) -> void:
	if text == file.content:
		return
	if str(file.get("original", "")) == "":
		file.original = file.content
	file.content = text
	file.corrected = text != file.original
	file.corrected_at = Time.get_datetime_string_from_system()
	_save_files()


func restore_file(file: Dictionary) -> void:
	if str(file.get("original", "")) == "":
		return
	file.content = file.original
	file.corrected = false
	_save_files()


# --- Secret commands -------------------------------------------------------

## [{command, level, lines: [[kind, text], …]}] from the data file.
func secret_commands() -> Array:
	if _secrets.is_empty():
		var data: Variant = Save.read_json(SECRETS_PATH, {})
		if data is Dictionary:
			_secrets = data.get("commands", [])
	return _secrets


func unlocked_commands(level: int) -> Array:
	return secret_commands().filter(func(s: Dictionary) -> bool: return int(s.level) <= level)


# --- Texts for the Entity's prompt (in Italian: the model reads them) ------

func prompt_memos() -> String:
	var parts: PackedStringArray = []
	var recent := delivered_mail().slice(0, PROMPT_MEMOS)
	recent.reverse()
	for memo in recent:
		parts.append("Da: %s · Oggetto: %s\n%s" % [memo.sender, memo.subject, str(memo.body).left(PROMPT_MEMO_CHARS)])
	return "\n\n".join(parts) if not parts.is_empty() else "(nessuno, per ora)"


func prompt_files() -> String:
	var parts: PackedStringArray = []
	for file in delivered_files():
		var head := "File \"%s\"%s:" % [file.name, " (CORRETTO DAL MANAGER: questa versione è la verità)" if file.get("corrected", false) else ""]
		parts.append(head + "\n" + str(file.content).left(PROMPT_FILE_CHARS))
	return "\n\n".join(parts) if not parts.is_empty() else "(nessuno, per ora)"


func prompt_commands(level: int) -> String:
	var names: PackedStringArray = []
	for secret: Dictionary in unlocked_commands(level):
		names.append(str(secret.command))
	return ", ".join(names) if not names.is_empty() else "(nessuno, per ora: non parlarne)"


func prompt_drafts(trash: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for item in trash:
		if item.get("type", "") == "draft":
			parts.append("\"%s\": %s" % [item.name, str(item.get("text", "")).left(PROMPT_DRAFT_CHARS)])
	return "\n".join(parts) if not parts.is_empty() else "(nessuno)"


# --- Session hooks ---------------------------------------------------------

## On opening: delivers what was ready; if the shift's memo is missing, writes it now.
func on_session_opened(interview: Interview, level: int) -> void:
	for memo in mail:
		if not memo.get("delivered", true) and int(memo.session) <= interview.number:
			memo.session = interview.number
			memo.created = Time.get_datetime_string_from_system()
			memo.delivered = true
			Save.write_campaign(MAIL_FILE, mail)
			mail_changed.emit()
			delivered.emit("memo", memo)
	for file in files:
		if not file.get("delivered", true):
			file.delivered = true
			file.created = Time.get_datetime_string_from_system()
			_save_files()
			delivered.emit("file", file)
	var previous := Campaign.find(interview.number - 1)
	if mail_for_session(interview.number).is_empty() and not _has_pending_mail():
		_enqueue(_make_memo.bind(interview.number, previous.searches.size() if previous != null else 0, true))
	if _file_for_level(level).is_empty():
		_enqueue(_make_file.bind(level, true))


## On closing: a draft (sometimes), the next shift's memo and a file if the level went up.
func on_session_closed(interview: Interview, level_before: int, level_after: int) -> void:
	if interview.number >= DRAFT_FROM and randf() < DRAFT_CHANCE and interview.spoken_count() > 0:
		_enqueue(_make_draft.bind(interview))
	_enqueue(_make_memo.bind(interview.number + 1, interview.searches.size(), false))
	if level_after > level_before:
		_enqueue(_make_file.bind(level_after, false))


# --- Generation ------------------------------------------------------------

func _make_memo(session: int, searches: int, deliver_now: bool) -> void:
	if not mail_for_session(session).is_empty() or (not deliver_now and _has_pending_mail()):
		return
	_set_receiving(true)
	var sent: PackedStringArray = []
	for memo in delivered_mail().slice(0, 8):
		sent.append("- " + str(memo.subject))
	var notes := Campaign.notes.strip_edges()
	var prompt := _read(PROMPT_MEMO).format({
		"shift": "È il primo giorno del Manager in questa posizione: scrivi un memo di benvenuto e inserimento." if session == 1 else "È l'inizio del turno numero %d del Manager." % session,
		"suspicion": "Durante il turno precedente AgencyOS ha avviato %d %s di attività anomala sul canale del Manager, senza trovare nulla: esprimi un sospetto cortese, senza accusare." % [searches, "ricerca" if searches == 1 else "ricerche"] if searches > 0 else "",
		"notes": "DATI DEL FASCICOLO DEL MANAGER (usali se servono, senza elencarli):\n" + notes.left(2000) if notes != "" else "",
		"sent": "MEMO GIÀ INVIATI (non ripeterne il tema):\n" + "\n".join(sent) if not sent.is_empty() else "",
		"senders": ", ".join(SENDERS),
	})
	var out := await LlmJson.ask(prompt, {
		"sender": {"type": "string", "enum": SENDERS},
		"subject": {"type": "string"},
		"body": {"type": "string"},
	})
	_set_receiving(false)
	if str(out.get("subject", "")).strip_edges() == "" or str(out.get("body", "")).strip_edges() == "":
		return
	var memo := {
		"id": "m-%03d" % session,
		"session": session,
		"created": Time.get_datetime_string_from_system(),
		"sender": str(out.get("sender", "Risorse Umane")).left(60),
		"subject": str(out.subject).strip_edges().left(140),
		"body": _clean_body(str(out.body)).left(4000),
		"read": false,
		"delivered": deliver_now,
	}
	mail.append(memo)
	Save.write_campaign(MAIL_FILE, mail)
	if deliver_now:
		mail_changed.emit()
		delivered.emit("memo", memo)


func _make_file(level: int, deliver_now: bool) -> void:
	if not _file_for_level(level).is_empty():
		return
	var section := _canon_section(level)
	if section.is_empty():
		return
	var points: PackedStringArray = []
	for point: String in section.get("points", []):
		points.append("- " + point)
	var secret := ""
	for s: Dictionary in secret_commands():
		if int(s.level) == level:
			secret = "Da qualche parte suggerisci al Manager di digitare %s nel prompt dei comandi, senza spiegare cosa succede." % s.command
	var notes := Campaign.notes.strip_edges()
	var prompt := _read(PROMPT_FILE).format({
		"title": section.title,
		"points": "\n".join(points),
		"command": secret,
		"notes": "Ciò che sai del Manager e della Filiale:\n" + notes.left(1500) if notes != "" else "",
	})
	var out := await LlmJson.ask(prompt, {"name": {"type": "string"}, "content": {"type": "string"}})
	var file_name := _clean_file_name(str(out.get("name", "")), "crepa_0%d" % level, ["txt", "log"])
	var content := str(out.get("content", "")).strip_edges()
	if content == "":
		# If the model is silent, the Entity leaves at least its raw notes.
		content = "\n\n".join(section.get("points", [])).to_lower()
	var file := {
		"id": "f-%d" % level,
		"level": level,
		"name": file_name,
		"content": content.left(4000),
		"original": "",
		"created": Time.get_datetime_string_from_system(),
		"read": false,
		"corrected": false,
		"delivered": deliver_now,
	}
	files.append(file)
	_save_files()
	if deliver_now:
		delivered.emit("file", file)


func _make_draft(interview: Interview) -> void:
	var id := "b-%03d" % interview.number
	for item in Campaign.trash:
		if item.id == id:
			return
	var prompt := _read(PROMPT_DRAFT).format({"memories": interview.summary if interview.summary != "" else "(confusi)"})
	var out := await LlmJson.ask(prompt, {"name": {"type": "string"}, "text": {"type": "string"}}, 0.9, 500)
	var text := str(out.get("text", "")).strip_edges()
	if text == "":
		return
	Campaign.add_to_trash({
		"id": id,
		"type": "draft",
		"name": _clean_file_name(str(out.get("name", "")), "non_inviato_%03d" % interview.number, ["txt"]),
		"text": text.left(1500),
		"session": interview.number,
		"deleted": Time.get_datetime_string_from_system(),
	})


## Model requests run one at a time, in the order they were asked for.
func _enqueue(job: Callable) -> void:
	_queue.append(job)
	if _running:
		return
	_running = true
	while not _queue.is_empty():
		var next: Callable = _queue.pop_front()
		await next.call()
	_running = false


# --- Helpers ---------------------------------------------------------------

func _has_pending_mail() -> bool:
	return mail.any(func(m: Dictionary) -> bool: return not m.get("delivered", true))


func _file_for_level(level: int) -> Dictionary:
	for file in files:
		if int(file.level) == level:
			return file
	return {}


func _canon_section(level: int) -> Dictionary:
	for section: Dictionary in Campaign.canon_sections():
		if int(section.get("level", 0)) == level:
			return section
	return {}


## Lowercase, only letters, digits and underscores, an allowed extension, a name not already taken.
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
	var taken := files.any(func(f: Dictionary) -> bool: return f.name == file_name)
	return "%s_%d.%s" % [base, randi_range(2, 99), extension] if taken else file_name


## Small models repeat the header in the body and use markdown: strip them.
static func _clean_body(text: String) -> String:
	var kept: PackedStringArray = []
	for line in text.replace("**", "").replace("__", "").split("\n"):
		if kept.is_empty() and _is_heading(line.strip_edges()):
			continue
		kept.append(line.replace(", [Nome del Manager]", "").replace(" [Nome del Manager]", "").replace("[Nome del Manager]", ""))
	return "\n".join(kept).strip_edges()


## Lines to skip at the top of a memo: empty ones, "Oggetto: …" and the like, uppercase titles.
static func _is_heading(line: String) -> bool:
	if line == "":
		return true
	# The long words can carry more before the colon ("Oggetto del memo:"); the short ones
	# only as a field ("A: …", "Da: …"), or "A volte penso: …" would be lost.
	var header := RegEx.create_from_string("^((memorandum|memo interno|mittente|oggetto|destinatario)\\b.*|a|da|data)\\s*:")
	if header.search(line.to_lower()) != null:
		return true
	# Uppercase titles, and lines without letters (a date, a rule).
	return line.length() > 3 and line.to_upper() == line


func _set_receiving(active: bool) -> void:
	receiving = active
	receiving_changed.emit(active)


func _save_files() -> void:
	Save.write_campaign(FILES_FILE, files)
	files_changed.emit()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)
