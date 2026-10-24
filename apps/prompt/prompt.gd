extends AppContent
## AgencyOS command prompt: system commands, branch files
## and the Entity's secret commands, unlocked by the access level.

const PROMPT := "C:\\FILIALE>"
const MAX_LINES := 400
const ENTITY_FONT := "res://ui/fonts/ShantellSans.ttf"
## The prototype's colors: command echo, green, red, white, the Entity's voice.
const COLORS := {"echo": "#c8d0c8", "ok": "#3fd27a", "error": "#ff6b70", "text": "#ffffff", "entity": "#7fe1ee"}
const ENTITY_LINE_SECONDS := 0.65
const LINE_SECONDS := 0.28
const SCAN_STEPS := 10
const SCAN_STEP_SECONDS := 0.14
const SCAN_WHISPERS: PackedStringArray = ["(non qui.)", "(sto trattenendo il respiro.)", "(fai finta di niente.)", "(brava. bravo. scusa, non so cosa sei.)"]
## Branch programs: name, app id, size shown by DIR.
const SYSTEM_FILES: Array[Array] = [
	["LINEA.EXE", &"line", "24.576"], ["FASCICOLO.DAT", &"dossier", "8.192"], ["CAM03.AVI", &"cam", "1.048.576"],
	["AMAIL.EXE", &"amail", "65.536"], ["TACCUINO.EXE", &"notebook", "20.480"], ["CALC.EXE", &"calc", "12.288"],
	["AGENDA.EXE", &"agenda", "18.432"], ["CONTEN.EXE", &"mine", "28.672"], ["LETTORE.EXE", &"player", "40.960"],
	["PANNELLO.CPL", &"ctrl", "9.216"], ["CANONE.HLP", &"canon", "32.768"], ["REGISTRO.EVT", &"event_viewer", "16.384"],
]
const WEEKDAYS: PackedStringArray = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"]
const MONTHS: PackedStringArray = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
const HELP := "Comandi disponibili:\n  DIR            elenca i file\n  TYPE <file>    mostra il contenuto di un file\n  APRI <nome>    apre un programma o un file\n  STATO          stato del General Manager\n  COLLOQUI       elenca i colloqui registrati\n  SCAN           cerca attività anomale\n  SUONI ON|OFF   attiva o disattiva i suoni\n  VER, DATA, ORA, CLS, ESCI"

## Printed lines: [text, kind].
var _lines: Array[Array] = []
var _history: PackedStringArray = []
var _history_index := 0
var _busy := false

@onready var _output: RichTextLabel = %Output
@onready var _input: LineEdit = %Input


func _ready() -> void:
	_input.text_submitted.connect(_on_submitted)
	_input.gui_input.connect(_on_input_key)
	_input.text_changed.connect(func(_t: String) -> void: Sfx.play(&"key"))
	%Screen.gui_input.connect(_on_screen_input)
	_print("AgencyOS 98 [Versione 4.98.0047]\n(C) Copyright 1998 Triangle Agency.\n\nDigita AIUTO per l'elenco dei comandi.\n", "text")


func on_opened(_args: Dictionary = {}) -> void:
	_input.grab_focus.call_deferred()


# --- Output ----------------------------------------------------------------

func _print(text: String, kind: String) -> void:
	_lines.append([text, kind])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(-MAX_LINES)
	_render()


func _replace_last(text: String, kind: String) -> void:
	_lines[-1] = [text, kind]
	_render()


func _render() -> void:
	var bbcode := ""
	for line in _lines:
		var text := str(line[0]).replace("[", "[lb]")
		if line[1] == "entity":
			bbcode += "[font=%s][font_size=15][color=%s]%s[/color][/font_size][/font]\n" % [ENTITY_FONT, COLORS.entity, text]
		else:
			bbcode += "[color=%s]%s[/color]\n" % [COLORS.get(line[1], COLORS.text), text]
	_output.text = bbcode


# --- Input -----------------------------------------------------------------

func _on_submitted(raw: String) -> void:
	if _busy:
		return
	_input.text = ""
	_busy = true
	_input.editable = false
	await _run(raw)
	_busy = false
	_input.editable = true
	if is_visible_in_tree():
		_input.grab_focus()


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_UP and _history_index > 0:
		_history_index -= 1
		_input.text = _history[_history_index]
	elif key.keycode == KEY_DOWN and _history_index < _history.size():
		_history_index += 1
		_input.text = _history[_history_index] if _history_index < _history.size() else ""
	else:
		return
	_input.caret_column = _input.text.length()
	_input.accept_event()


func _on_screen_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and _output.get_selected_text() == "":
		_input.grab_focus()


# --- Commands --------------------------------------------------------------

func _run(raw: String) -> void:
	_print(PROMPT + raw, "echo")
	var line := raw.strip_edges()
	if line == "":
		return
	_history.append(line)
	_history_index = _history.size()
	var parts := line.split(" ", false)
	var command := parts[0].to_upper()
	var argument := " ".join(parts.slice(1))
	var level := Campaign.level()
	match command:
		"AIUTO", "HELP", "?":
			_print(HELP, "text")
		"DIR":
			_dir()
		"TYPE":
			_type(argument)
		"APRI", "START":
			_open(argument)
		"STATO":
			_status(level)
		"COLLOQUI":
			_list_interviews()
		"SCAN":
			await _scan(level)
		"SUONI":
			var value := argument.to_upper()
			if value == "ON" or value == "OFF":
				Sfx.enabled = value == "ON"
				_print("Suoni " + ("attivati." if value == "ON" else "disattivati."), "ok")
			else:
				_print("Uso: SUONI ON oppure SUONI OFF", "error")
		"VER":
			_print("AgencyOS 98 [Versione 4.98.0047] · Modalità Sicura", "text")
		"DATA":
			var d := Time.get_datetime_dict_from_system()
			_print("La data corrente è: %s %d %s %d" % [WEEKDAYS[d.weekday], d.day, MONTHS[d.month - 1], d.year], "text")
		"ORA":
			_print("L'ora corrente è: " + Time.get_time_string_from_system(), "text")
		"CLS":
			_lines.clear()
			_render()
		"ESCI", "EXIT":
			close_requested.emit()
		_:
			await _secret_or_unknown(command, level)


func _dir() -> void:
	var listing := " Volume nell'unità C: FILIALE\n Directory di C:\\FILIALE\n\n"
	for entry in SYSTEM_FILES:
		listing += "%s%s  01/01/98\n" % [str(entry[0]).rpad(18), str(entry[2]).lpad(12)]
	_print(listing, "text")
	var files := Campaign.correspondence.delivered_files()
	if not files.is_empty():
		var unregistered := ""
		for file in files:
			unregistered += "%s%s  %s  [NON REGISTRATO]\n" % [str(file.name).to_upper().rpad(18), str(str(file.content).length()).lpad(12), ItalianDate.numeric(str(file.created))]
		_print(unregistered, "error")
	_print("      %d file" % (SYSTEM_FILES.size() + files.size()), "text")


func _type(argument: String) -> void:
	if argument == "":
		_print("Specifica un file. Esempio: TYPE nome_file.txt", "error")
		return
	var file := Campaign.correspondence.find_file_by_name(argument)
	if not file.is_empty():
		_print(str(file.content), "entity")
		Campaign.correspondence.mark_file_read(file)
	elif SYSTEM_FILES.any(func(entry: Array) -> bool: return entry[0] == argument.to_upper()):
		_print("Impossibile visualizzare un file binario.", "error")
	else:
		_print("File non trovato.", "error")


func _open(argument: String) -> void:
	var wanted := argument.to_upper()
	if wanted != "":
		for entry in SYSTEM_FILES:
			if entry[0] == wanted or str(entry[0]).begins_with(wanted) or String(entry[1]).to_upper() == wanted:
				app_requested.emit(entry[1], {})
				_print("Avvio di %s…" % entry[0], "ok")
				return
	var file := Campaign.correspondence.find_file_by_name(argument)
	if not file.is_empty():
		app_requested.emit(&"notepad", {"file": file.id})
		_print("Apertura di %s…" % file.name, "ok")
		return
	_print("Programma o file non trovato.", "error")


func _status(level: int) -> void:
	var missing := Campaign.interviews_to_next_level()
	_print("GENERAL MANAGER · STATO\n  Livello di accesso ....... %d/5\n  Colloqui conclusi ........ %d\n  Prossimo livello ......... %s\n  Memo ricevuti ............ %d\n  File non registrati ...... %d\n  Canale ................... %s" % [
		level, Campaign.closed_count(), "—" if missing == 0 else "tra %d" % missing,
		Campaign.correspondence.delivered_mail().size(), Campaign.correspondence.delivered_files().size(),
		"APERTO" if Campaign.current() != null else "CHIUSO"], "text")


func _list_interviews() -> void:
	if Campaign.interviews.is_empty():
		_print("Nessun colloquio registrato.", "text")
		return
	var rows: PackedStringArray = []
	for interview in Campaign.interviews:
		rows.append("  #%03d  %s  %s  %d messaggi" % [interview.number, ItalianDate.numeric(interview.opened_at), "IN CORSO" if interview.is_open() else "CHIUSO  ", interview.spoken_count()])
	_print("\n".join(rows), "text")


func _scan(level: int) -> void:
	_print("Scansione del canale in corso…", "text")
	for i in range(1, SCAN_STEPS + 1):
		await get_tree().create_timer(SCAN_STEP_SECONDS).timeout
		_replace_last("Scansione del canale in corso… [%s%s] %d%%" % ["█".repeat(i), "░".repeat(SCAN_STEPS - i), i * 10], "text")
	_print("Nessuna attività anomala rilevata.", "ok")
	if level >= 2 and randf() < 0.6:
		await get_tree().create_timer(0.9).timeout
		_print(SCAN_WHISPERS[randi() % SCAN_WHISPERS.size()], "entity")
		Entity.stir(0.4)


func _secret_or_unknown(command: String, level: int) -> void:
	for secret: Dictionary in Campaign.correspondence.unlocked_commands(level):
		if str(secret.command) == command:
			Entity.stir(0.6)
			if command == "CAVEAU":
				Entity.widen_eyes(5.0)
				Entity.glitch("lattice")
			for row: Array in secret.get("lines", []):
				var kind := {"system": "error", "entity": "entity", "graphic": "ok"}.get(str(row[0]), "text") as String
				_print(str(row[1]), kind)
				await get_tree().create_timer(ENTITY_LINE_SECONDS if kind == "entity" else LINE_SECONDS).timeout
			return
	_print("Comando o nome file non riconosciuto.", "error")
