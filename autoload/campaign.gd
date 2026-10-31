extends Node
## Pure game logic, no interface: interviews, access level, the Entity's prompt,
## summaries and cumulative memory, Notebook, trash and agenda.
## Memos, desktop files and drafts live in correspondence (a child node).

signal interviews_changed
## An interview received messages or changed status.
signal interview_updated(interview: Interview)
signal level_changed(level: int)
signal memory_changed
## The Notebook pages changed (added, renamed, moved to the trash).
signal pages_changed
signal trash_changed
signal chaos_changed(chaos: int)
signal agenda_changed

const PER_LEVEL := 3
const MAX_LEVEL := 5
const STATE_FILE := "state.json"
const PAGES_FILE := "notebook.json"
const TRASH_FILE := "trash.json"
const AGENDA_FILE := "agenda.json"
const INTERVIEWS_DIR := "interviews"
const DEFAULT_SESSION_TIME := "21:00"
## Default preparation checklist (shown on screen, so in Italian).
const DEFAULT_CHECKLIST: Array[String] = ["Preparare l'Incarico", "Leggere il memo dell'Agenzia", "Parlare con l'Entità", "Aggiornare le note del Fascicolo"]
const STATE_VERSION := 1
const CANON_PATH := "res://data/canon.json"
const EXAMPLES_PATH := "res://data/voice_examples.json"
const PROMPT_ENTITY := "res://data/prompt/entity.txt"
const PROMPT_SUMMARY := "res://data/prompt/summary.txt"
const PROMPT_MEMORY := "res://data/prompt/memory.txt"
const PROMPT_GLITCH := "res://data/prompt/glitch.txt"
const PROMPT_SEARCH := "res://data/prompt/search.txt"
const GLITCH_PATH := "res://data/glitch.json"
const NO_GLITCH := "none"
## Replies without a glitch required between one glitch and the next: at most one in four.
const GLITCH_GAP := 3
## Chance of an AgencyOS search: starts at the third exchange and grows up to the maximum.
const SEARCH_FROM := 3
const SEARCH_BASE := 0.08
const SEARCH_STEP := 0.05
const SEARCH_MAX := 0.4
## Stage direction sent when the Manager says nothing (the model reads it in Italian).
const SILENCE := "[il Manager resta in silenzio, in attesa]"
## Rough estimate that works for local models: one token every 4 characters.
const CHARS_PER_TOKEN := 4.0
## Margin for the tokens the server adds by itself (roles, separators).
const TOKEN_MARGIN := 128
const RECENT_SUMMARIES := 2

var interviews: Array[Interview] = []
## The Manager's notes about the campaign: the Entity reads them.
var notes: String = ""
## The Entity's compact cumulative memories, updated at every closing.
var memory: String = ""
var chaos: int = 0
## Notebook pages: {id, title, session (0 = none), text, created, modified}.
var pages: Array[Dictionary] = []
## Deleted items: {id, type ("page"|"draft"), name, data?, text?, session?, deleted}.
var trash: Array[Dictionary] = []
## Scheduled sessions: {id, date (YYYY-MM-DD), time, title, checklist: [{text, done}]}.
var agenda: Array[Dictionary] = []
## Obsidian vault folder for this campaign's exports; empty = to be chosen.
var obsidian_folder: String = ""

## Agency memos, the Entity's files and the drafts in the trash.
var correspondence: Correspondence
## Goes up at every reset: a model request started before it finds a different value
## after its await and throws its result away, instead of writing into the new branch.
var generation: int = 0

var _current_number: int = 0
var _retrying := false
var _glitch_table: Dictionary = {}


func _ready() -> void:
	correspondence = Correspondence.new()
	correspondence.name = "Correspondence"
	add_child(correspondence)
	_load()


# --- Level -----------------------------------------------------------------

func closed_count() -> int:
	return interviews.filter(func(i: Interview) -> bool: return not i.is_open()).size()


func level() -> int:
	return mini(MAX_LEVEL, 1 + closed_count() / PER_LEVEL)


## Interviews to close to reach the next level; 0 if the level is already the maximum.
func interviews_to_next_level() -> int:
	if level() >= MAX_LEVEL:
		return 0
	return PER_LEVEL - closed_count() % PER_LEVEL


# --- Interviews ------------------------------------------------------------

func current() -> Interview:
	return find(_current_number) if _current_number > 0 else null


func find(number: int) -> Interview:
	for interview in interviews:
		if interview.number == number:
			return interview
	return null


func open_interview() -> Interview:
	if current() != null:
		return current()
	var previous: Interview = interviews.back() if not interviews.is_empty() else null
	var interview := Interview.new()
	interview.number = 1 if previous == null else previous.number + 1
	interview.level = level()
	interview.opened_at = Time.get_datetime_string_from_system()
	interview.add("system", "> CONNESSIONE STABILITA. CANALE NON REGISTRATO.")
	if previous != null and previous.level < interview.level:
		interview.add("system", "> LIVELLO DI ACCESSO DEL GENERAL MANAGER AGGIORNATO: %d." % interview.level)
	interviews.append(interview)
	_current_number = interview.number
	save_interview(interview)
	_save_state()
	interviews_changed.emit()
	correspondence.on_session_opened(interview, level())
	_retry_missing_summaries()
	return interview


func add_message(interview: Interview, who: String, text: String) -> Dictionary:
	var message := interview.add(who, text)
	save_interview(interview)
	interview_updated.emit(interview)
	return message


func save_interview(interview: Interview) -> void:
	Save.write_campaign(Interview.file_name_for(interview.number), interview.to_dict())


## Closes the interview: summary from the Entity's point of view and updated memory.
## If the model doesn't answer the interview is closed anyway; the summary is retried later.
func close_interview(interview: Interview) -> void:
	var old_level := level()
	var started := generation
	add_message(interview, "system", "> SESSIONE TERMINATA DAL GENERAL MANAGER.")
	interview.summary = await summarize(interview)
	if generation != started:
		return
	interview.status = Interview.CLOSED
	interview.closed_at = Time.get_datetime_string_from_system()
	if _current_number == interview.number:
		_current_number = 0
	save_interview(interview)
	_save_state()
	if interview.summary != "":
		await _merge_memory(interview)
		if generation != started:
			return
	interview_updated.emit(interview)
	interviews_changed.emit()
	if level() != old_level:
		level_changed.emit(level())
	# Draft, next shift's memo and maybe a file: in the background, without making anyone wait.
	correspondence.on_session_closed(interview, old_level, level())


## The branch's Chaos pool; never below zero.
func set_chaos(value: int) -> void:
	chaos = maxi(0, value)
	_save_state()
	chaos_changed.emit(chaos)


func add_chaos(amount: int) -> void:
	set_chaos(chaos + amount)


## Reset protocol: deletes interviews, memories, mail, files, trash and Chaos;
## the level goes back to 1. Settings, vault folder and agenda stay;
## keep_notes also keeps the Manager's notes and the Notebook.
func reset_branch(keep_notes: bool) -> void:
	generation += 1
	correspondence.cancel_pending()
	for file_name in Save.list_campaign(INTERVIEWS_DIR):
		Save.delete_campaign(INTERVIEWS_DIR + "/" + file_name)
	for relative in [Correspondence.MAIL_FILE, Correspondence.FILES_FILE, TRASH_FILE]:
		Save.delete_campaign(relative)
	if not keep_notes:
		Save.delete_campaign(PAGES_FILE)
		notes = ""
		pages.clear()
	interviews.clear()
	trash.clear()
	memory = ""
	chaos = 0
	_current_number = 0
	_save_state()
	correspondence.load_data()
	interviews_changed.emit()
	memory_changed.emit()
	trash_changed.emit()
	pages_changed.emit()
	chaos_changed.emit(chaos)


func set_notes(text: String) -> void:
	notes = text
	_save_state()


## The Manager's correction to an interview's memories: from now on it is the truth.
func set_summary(interview: Interview, text: String) -> void:
	interview.summary = text.strip_edges()
	save_interview(interview)
	interview_updated.emit(interview)


## The Manager's correction to the cumulative memory.
func set_memory(text: String) -> void:
	memory = text.strip_edges()
	_save_state()
	memory_changed.emit()


## Canon sections as they are in the data file.
func canon_sections() -> Array:
	var data: Variant = Save.read_json(CANON_PATH, {})
	return (data as Dictionary).get("sections", []) if data is Dictionary else []


# --- Notebook --------------------------------------------------------------

## Pages, most recently modified first.
func pages_by_modified() -> Array[Dictionary]:
	var sorted := pages.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.modified) > str(b.modified))
	return sorted


func find_page(id: String) -> Dictionary:
	for page in pages:
		if page.id == id:
			return page
	return {}


func pages_for_session(number: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for page in pages:
		if int(page.session) == number:
			result.append(page)
	return result


## New page linked to the given session; -1 = the open interview or the last one.
func new_page(session: int = -1) -> Dictionary:
	if session < 0:
		var open := current()
		session = open.number if open != null else (interviews.back().number if not interviews.is_empty() else 0)
	var now := Time.get_datetime_string_from_system()
	var title := "Sessione %03d · appunti" % session if session > 0 else "Appunti del %s" % ItalianDate.numeric(now)
	var same := pages.filter(func(p: Dictionary) -> bool: return p.title == title or str(p.title).begins_with(title + " (")).size()
	if same > 0:
		title += " (%d)" % (same + 1)
	var page := {"id": "a-%d" % Time.get_unix_time_from_system() + "-%d" % randi_range(100, 999), "title": title, "session": session, "text": "", "created": now, "modified": now}
	pages.append(page)
	_save_pages()
	pages_changed.emit()
	return page


## Call after editing a page; quiet avoids redrawing the list.
func save_page(page: Dictionary, quiet: bool = false) -> void:
	page.modified = Time.get_datetime_string_from_system()
	_save_pages()
	if not quiet:
		pages_changed.emit()


func trash_page(page: Dictionary) -> void:
	pages.erase(page)
	_save_pages()
	add_to_trash({"id": "x-" + str(page.id), "type": "page", "name": page.title, "data": page, "deleted": Time.get_datetime_string_from_system()})
	pages_changed.emit()


## Trash items: Notebook pages and the Entity's drafts.
func add_to_trash(item: Dictionary) -> void:
	trash.append(item)
	_save_trash()


## Only Notebook pages can be restored; the Entity's drafts can't.
func restore_from_trash(item: Dictionary) -> void:
	if item.get("type", "") != "page":
		return
	var page: Dictionary = item.data.duplicate()
	page.modified = Time.get_datetime_string_from_system()
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


func set_obsidian_folder(path: String) -> void:
	obsidian_folder = path
	_save_state()


# --- Agenda ----------------------------------------------------------------

func session_on(day: String) -> Dictionary:
	for session in agenda:
		if session.date == day:
			return session
	return {}


func schedule_session(day: String) -> Dictionary:
	var existing := session_on(day)
	if not existing.is_empty():
		return existing
	var checklist: Array = []
	for item in DEFAULT_CHECKLIST:
		checklist.append({"text": item, "done": false})
	var session := {"id": "d-" + day, "date": day, "time": DEFAULT_SESSION_TIME, "title": "", "checklist": checklist}
	agenda.append(session)
	save_agenda()
	return session


func cancel_session(session: Dictionary) -> void:
	agenda.erase(session)
	save_agenda()


func save_agenda() -> void:
	Save.write_campaign(AGENDA_FILE, agenda)
	agenda_changed.emit()


## The next session from today on, or {}.
func next_session() -> Dictionary:
	var today := ItalianDate.today()
	var best := {}
	for session in agenda:
		var key := str(session.date) + str(session.get("time", ""))
		if str(session.date) >= today and (best.is_empty() or key < str(best.date) + str(best.get("time", ""))):
			best = session
	return best


# --- Glitches and searches -------------------------------------------------

## Line effects from the data file: name -> {description, timing, webcam, motion}.
func glitch_table() -> Dictionary:
	if _glitch_table.is_empty():
		var data: Variant = Save.read_json(GLITCH_PATH, {})
		if data is Dictionary:
			_glitch_table = data.get("glitches", {})
	return _glitch_table


## True if the Entity's last reply may have a glitch: never two in a row,
## at most one every four replies. Call it after saving the reply.
func can_glitch(interview: Interview) -> bool:
	var since_last := 0
	var skipped_current := false
	for i in range(interview.messages.size() - 1, -1, -1):
		var m: Dictionary = interview.messages[i]
		if m.who != "entity":
			continue
		if not skipped_current:
			skipped_current = true
			continue
		if str(m.get("glitch", "")) != "":
			return since_last >= GLITCH_GAP
		since_last += 1
	return true


## Second short request: picks an effect for the last reply, "" if none.
## Uses a JSON schema; if the server doesn't accept it, retries without and looks for the name in the text.
func choose_glitch(interview: Interview) -> String:
	var table := glitch_table()
	if table.is_empty():
		return ""
	var entity_text := ""
	var manager_text := ""
	for i in range(interview.messages.size() - 1, -1, -1):
		var m: Dictionary = interview.messages[i]
		if entity_text == "" and m.who == "entity":
			entity_text = str(m.text)
		elif entity_text != "" and m.who == "manager":
			manager_text = str(m.text)
			break
	var lines: PackedStringArray = []
	for glitch_name: String in table:
		lines.append("- %s: %s" % [glitch_name, table[glitch_name].get("description", "")])
	var prompt := _read_text(PROMPT_GLITCH).format({
		"list": "\n".join(lines),
		"manager": manager_text if manager_text != "" else "(niente)",
		"entity": entity_text,
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
		push_warning("Campaign: glitch choice failed: %s" % request.error)
		return ""
	return _parse_glitch(request.text, table)


func search_chance(interview: Interview) -> float:
	var replies := interview.messages.filter(func(m: Dictionary) -> bool: return m.who == "entity").size()
	if replies < SEARCH_FROM:
		return 0.0
	return minf(SEARCH_BASE + (replies - SEARCH_FROM) * SEARCH_STEP, SEARCH_MAX)


## Stage direction that asks the Entity to hide during a search.
func search_event() -> String:
	return _read_text(PROMPT_SEARCH).strip_edges()


func record_search(interview: Interview) -> void:
	interview.searches.append(Time.get_datetime_string_from_system())
	save_interview(interview)


func _parse_glitch(text: String, table: Dictionary) -> String:
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary:
		var chosen := str(data.get("glitch", "")).to_lower()
		return chosen if table.has(chosen) else ""
	# Without a schema: the first effect name that appears in the text.
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

## Messages for the model: system prompt plus the most recent part of the interview
## that fits in the context. extra_user is an optional line added at the end.
func build_messages(interview: Interview, extra_user: String = "") -> Array[Dictionary]:
	var system := entity_prompt(interview)
	var budget := Brain.context_tokens() - int(Brain.get_setting("max_reply")) - _tokens(system) - TOKEN_MARGIN
	budget -= _tokens(extra_user)
	var history: Array[Dictionary] = []
	for i in range(interview.messages.size() - 1, -1, -1):
		var m: Dictionary = interview.messages[i]
		if m.who == "system":
			continue
		var cost := _tokens(m.text) + 4
		if cost > budget and not history.is_empty():
			break
		budget -= cost
		history.push_front({"role": "user" if m.who == "manager" else "assistant", "content": str(m.text)})
	if extra_user != "":
		history.append({"role": "user", "content": extra_user})
	if history.is_empty() or history.back().role != "user":
		history.append({"role": "user", "content": SILENCE})
	var messages: Array[Dictionary] = [{"role": "system", "content": system}]
	# Some models reject two messages in a row with the same role: merge them.
	for entry in history:
		if messages.size() > 1 and messages.back().role == entry.role:
			messages.back().content += "\n\n" + entry.content
		else:
			messages.append(entry)
	return messages


## The Entity's system prompt (written in Italian, like everything the model reads).
func entity_prompt(interview: Interview) -> String:
	return _read_text(PROMPT_ENTITY).format({
		"level": level(),
		"canon": _canon_text(level()),
		"notes": notes.strip_edges() if notes.strip_edges() != "" else "(quasi niente: non sai ancora bene chi sia questo Manager. sei curiosa, e un po' diffidente.)",
		"memory": memory.strip_edges() if memory.strip_edges() != "" else "(nessuno: è la prima volta che riesci a raggiungerlo)",
		"summaries": _recent_summaries(interview),
		"examples": _examples_text(),
		"number": interview.number,
		"memos": correspondence.prompt_memos(),
		"files": correspondence.prompt_files(),
		"commands": correspondence.prompt_commands(level()),
		"drafts": correspondence.prompt_drafts(trash),
		"assignment": _next_session_text(),
	})


# --- Summaries and memory --------------------------------------------------

func summarize(interview: Interview) -> String:
	var lines: PackedStringArray = []
	for m in interview.messages:
		if m.who != "system":
			lines.append(("MANAGER: " if m.who == "manager" else "ENTITÀ: ") + str(m.text))
	if lines.is_empty():
		return ""
	var max_chars := int((Brain.context_tokens() - int(Brain.get_setting("max_reply")) - 600) * CHARS_PER_TOKEN)
	var transcript := "\n".join(lines).right(maxi(max_chars, 2000))
	var prompt := _read_text(PROMPT_SUMMARY).format({"number": interview.number, "transcript": transcript})
	return await _ask(prompt)


func _merge_memory(interview: Interview) -> void:
	if memory.strip_edges() == "":
		memory = interview.summary
	else:
		var prompt := _read_text(PROMPT_MEMORY).format({"memory": memory, "number": interview.number, "summary": interview.summary})
		var started := generation
		var merged := await _ask(prompt)
		if generation != started:
			return
		# If merging fails, append instead, so the memory isn't lost.
		memory = merged if merged != "" else memory + "\n" + interview.summary
	_save_state()
	memory_changed.emit()


func _retry_missing_summaries() -> void:
	if _retrying:
		return
	_retrying = true
	var started := generation
	for interview in interviews.duplicate():
		if interview.is_open() or interview.summary != "" or interview.spoken_count() == 0:
			continue
		var summary := await summarize(interview)
		if summary == "" or generation != started:
			break
		interview.summary = summary
		save_interview(interview)
		await _merge_memory(interview)
		if generation != started:
			break
	_retrying = false


## Short non-streaming request; "" if the model doesn't answer.
func _ask(prompt: String) -> String:
	var request := Brain.chat([{"role": "user", "content": prompt}], {"stream": false, "temperature": 0.4})
	if not request.is_done:
		await request.finished
	if not request.ok():
		push_warning("Campaign: model request failed: %s" % request.error)
		return ""
	return request.text.strip_edges()


# --- Prompt pieces (in Italian: the model reads them) ----------------------

func _canon_text(current_level: int) -> String:
	var blocks: PackedStringArray = []
	for section: Dictionary in canon_sections():
		var section_level := int(section.get("level", 0))
		var head: String
		if section_level == 0:
			head = "## %s (sempre valido)" % section.title
		elif section_level <= current_level:
			head = "## %s (livello %d: puoi parlarne apertamente)" % [section.title, section_level]
		else:
			head = "## %s (livello %d: lo sai, ma il Manager NON ha ancora questo accesso. Non rivelarlo: al massimo un'allusione, una frase troncata, un \"non ancora\")" % [section.title, section_level]
		var points: PackedStringArray = []
		for point: String in section.get("points", []):
			points.append("- " + point)
		blocks.append(head + "\n" + "\n".join(points))
	return "\n\n".join(blocks)


func _recent_summaries(interview: Interview) -> String:
	var parts: PackedStringArray = []
	for other in interviews:
		if other != interview and other.summary != "":
			parts.append("Colloquio %d:\n%s" % [other.number, other.summary])
	if parts.is_empty():
		return "(nessuno)"
	return "\n\n".join(parts.slice(-RECENT_SUMMARIES))


func _next_session_text() -> String:
	var session := next_session()
	if session.is_empty():
		return "(non lo sai)"
	var text := ItalianDate.weekday_short(str(session.date)) + " " + ItalianDate.numeric(str(session.date))
	if str(session.get("time", "")) != "":
		text += " alle " + str(session.time)
	if str(session.get("title", "")) != "":
		text += " · " + str(session.title)
	return text


func _examples_text() -> String:
	var data: Variant = Save.read_json(EXAMPLES_PATH, {})
	var parts: PackedStringArray = []
	for example: Dictionary in (data as Dictionary).get("examples", []):
		parts.append("MANAGER: %s\nTU: %s" % [example.get("manager", ""), example.get("entity", "")])
	return "\n\n".join(parts) if not parts.is_empty() else "(nessuno)"


func _read_text(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Campaign: can't read %s." % path)
	return text


func _tokens(text: String) -> int:
	return ceili(text.length() / CHARS_PER_TOKEN)


# --- Persistence -----------------------------------------------------------

func _load() -> void:
	var state: Variant = Save.read_campaign(STATE_FILE, {})
	if state is Dictionary:
		notes = str(state.get("notes", ""))
		memory = str(state.get("memory", ""))
		chaos = int(state.get("chaos", 0))
		_current_number = int(state.get("current", 0))
		obsidian_folder = str(state.get("obsidian_folder", ""))
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
	for file_name in Save.list_campaign(INTERVIEWS_DIR):
		var data: Variant = Save.read_campaign(INTERVIEWS_DIR + "/" + file_name, null)
		if data is Dictionary:
			interviews.append(Interview.from_dict(data))
	interviews.sort_custom(func(a: Interview, b: Interview) -> bool: return a.number < b.number)
	var open := current()
	if open == null or not open.is_open():
		_current_number = 0
		# An interview left open without being the current one (e.g. after a crash) becomes active again.
		for interview in interviews:
			if interview.is_open():
				_current_number = interview.number


func _save_state() -> void:
	Save.write_campaign(STATE_FILE, {
		"version": STATE_VERSION,
		"notes": notes,
		"current": _current_number,
		"chaos": chaos,
		"memory": memory,
		"obsidian_folder": obsidian_folder,
	})


func _save_pages() -> void:
	Save.write_campaign(PAGES_FILE, pages)


func _save_trash() -> void:
	Save.write_campaign(TRASH_FILE, trash)
	trash_changed.emit()
