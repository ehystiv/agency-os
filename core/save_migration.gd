class_name SaveMigration
extends RefCounted
## One-time conversion of the saves written by version 0.1 (Italian file names and keys)
## to the current layout. Runs from Save before anything is read. The old files are
## moved to user://legacy_0.1/ as a backup, so nothing is lost if something goes wrong.

const LEGACY_DIR := "user://legacy_0.1"
const OLD_UI := "user://config/interfaccia.json"
const NEW_UI := "user://config/ui.json"
const OLD_MODEL := "user://config/modello.cfg"
const NEW_MODEL := "user://config/model.cfg"
const OLD_CAMPAIGNS := "user://campagne"
const NEW_CAMPAIGNS := "user://campaigns"
## The campaigns are converted here and renamed to NEW_CAMPAIGNS only at the end:
## a conversion cut halfway (a crash) is simply done again at the next start.
const PARTIAL_CAMPAIGNS := "user://campaigns.migrating"

const APP_IDS := {"linea": "line", "fascicolo": "dossier", "taccuino": "notebook", "canone": "canon", "cestino": "trash", "registro": "event_viewer", "note": "notepad", "impostazioni_linea": "line_settings"}
const CAMPAIGN_IDS := {"filiale": "branch"}
const GLITCHES := {"tremito": "tremor", "inchiostro": "ink", "occhi": "eyes", "inversione": "inversion", "triangolo": "triangle", "urlo": "scream", "corruzione": "corruption", "eco": "echo", "gocciolamento": "drip", "errore": "error", "sabotaggio": "sabotage", "titolo": "title", "sussurro": "whisper", "reticolo": "lattice", "fantasma": "ghost", "statico": "static", "battito": "heartbeat"}
const WALLPAPERS := {"reticolo": "lattice", "caveau": "vault", "tinta": "solid"}
const LEVELS := {"facile": "easy", "medio": "medium", "esperto": "expert"}
const SPEAKERS := {"sistema": "system", "entita": "entity", "manager": "manager"}
const UI_KEYS := {
	"finestre": "windows", "ordine_finestre": "window_order", "icone": "icons", "sfondo": "wallpaper",
	"audio": "audio", "glitch_attivi": "glitches_enabled", "crt_attivo": "crt_enabled",
	"animazioni_ridotte": "reduced_motion", "schermo_intero": "fullscreen",
	"salvaschermo_minuti": "screensaver_minutes", "mostra_avvio": "show_boot",
	"lettore_volume": "player_volume", "contenimento_livello": "containment_level",
	"contenimento_record": "containment_records",
}
const PROVIDERS := {"locale": "local", "huggingface": "huggingface", "claude": "claude"}
const MODEL_KEYS := {"server": "server", "url": "url", "modello": "model", "chiave": "api_key", "temperatura": "temperature", "contesto": "context", "max_risposta": "max_reply", "salta_ragionamento": "skip_reasoning"}


static func run() -> void:
	var migrated := false
	if FileAccess.file_exists(OLD_UI) and not FileAccess.file_exists(NEW_UI):
		_migrate_ui()
		migrated = true
	if FileAccess.file_exists(OLD_MODEL) and not FileAccess.file_exists(NEW_MODEL):
		_migrate_model()
		migrated = true
	if DirAccess.dir_exists_absolute(OLD_CAMPAIGNS) and not DirAccess.dir_exists_absolute(NEW_CAMPAIGNS):
		_migrate_campaigns()
		migrated = true
	if migrated:
		print("SaveMigration: 0.1 saves converted; originals kept in %s." % LEGACY_DIR)


# --- Interface settings ----------------------------------------------------

static func _migrate_ui() -> void:
	var old := _dict(_read(OLD_UI, {}))
	var new := {}
	for key: String in old:
		var value: Variant = old[key]
		match key:
			"finestre":
				var windows := {}
				for id: String in _dict(value):
					var state := _dict(value[id])
					windows[_app(id)] = {"x": state.get("x", 0), "y": state.get("y", 0), "minimized": state.get("ridotta", false)}
				value = windows
			"ordine_finestre":
				value = _list(value).map(func(id: Variant) -> String: return _app(str(id)))
			"icone":
				var icons := {}
				for icon_key: String in _dict(value):
					icons[icon_key if icon_key.begins_with("file:") else _app(icon_key)] = value[icon_key]
				value = icons
			"sfondo":
				value = WALLPAPERS.get(value, "lattice")
			"audio":
				var audio := _dict(value)
				value = {"enabled": audio.get("attivo", true), "volume": audio.get("volume", 0.8)}
			"contenimento_livello":
				value = LEVELS.get(value, "easy")
			"contenimento_record":
				var records := {}
				for level: String in _dict(value):
					records[LEVELS.get(level, level)] = value[level]
				value = records
		new[UI_KEYS.get(key, key)] = value
	_write(NEW_UI, new)
	_backup(OLD_UI, "config/interfaccia.json")


# --- Model settings --------------------------------------------------------

static func _migrate_model() -> void:
	var old := ConfigFile.new()
	if old.load(OLD_MODEL) != OK:
		return
	var new := ConfigFile.new()
	new.set_value("line", "provider", PROVIDERS.get(str(old.get_value("linea", "provider", "locale")), "local"))
	for section in old.get_sections():
		if not PROVIDERS.has(section):
			continue
		for key in old.get_section_keys(section):
			var value: Variant = old.get_value(section, key)
			if key == "server" and value == "personalizzato":
				value = "custom"
			new.set_value(PROVIDERS[section], MODEL_KEYS.get(key, key), value)
	new.save(NEW_MODEL)
	_backup(OLD_MODEL, "config/modello.cfg")


# --- Campaigns -------------------------------------------------------------

static func _migrate_campaigns() -> void:
	_remove_tree(PARTIAL_CAMPAIGNS)
	DirAccess.make_dir_recursive_absolute(PARTIAL_CAMPAIGNS)
	var index := _dict(_read(OLD_CAMPAIGNS + "/indice.json", {}))
	var campaigns: Array = []
	for entry: Dictionary in _dicts(index.get("campagne", [])):
		campaigns.append({"id": _campaign(str(entry.get("id", "filiale"))), "name": entry.get("nome", "Filiale"), "created": entry.get("creata", "")})
	_write(PARTIAL_CAMPAIGNS + "/index.json", {"version": 1, "active": _campaign(str(index.get("attiva", "filiale"))), "campaigns": campaigns})
	for folder in DirAccess.get_directories_at(OLD_CAMPAIGNS):
		_migrate_campaign(OLD_CAMPAIGNS + "/" + folder, PARTIAL_CAMPAIGNS + "/" + _campaign(folder))
	var err := DirAccess.rename_absolute(PARTIAL_CAMPAIGNS, NEW_CAMPAIGNS)
	if err != OK:
		push_error("SaveMigration: can't move the converted campaigns into place (%s)." % error_string(err))
		return
	_backup(OLD_CAMPAIGNS, "campagne")


static func _migrate_campaign(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to + "/interviews")
	var state := _dict(_read(from + "/stato.json", {}))
	_write(to + "/state.json", {
		"version": 1, "notes": state.get("note", ""), "current": state.get("corrente", 0),
		"chaos": state.get("caos", 0), "memory": state.get("memoria", ""),
		"obsidian_folder": state.get("cartella_obsidian", ""),
	})
	for file_name in DirAccess.get_files_at(from + "/colloqui"):
		if file_name.ends_with(".json"):
			_write(to + "/interviews/" + file_name, _interview(_dict(_read(from + "/colloqui/" + file_name, {}))))
	_write(to + "/notebook.json", _dicts(_read(from + "/appunti.json", [])).map(func(p: Dictionary) -> Dictionary: return _page(p)))
	_write(to + "/trash.json", _dicts(_read(from + "/cestino.json", [])).map(func(t: Dictionary) -> Dictionary: return _trash_item(t)))
	_write(to + "/mail.json", _dicts(_read(from + "/posta.json", [])).map(func(m: Dictionary) -> Dictionary: return {
		"id": m.get("id", ""), "session": m.get("sessione", 0), "created": m.get("creato", ""),
		"sender": m.get("mittente", ""), "subject": m.get("oggetto", ""), "body": m.get("corpo", ""),
		"read": m.get("letta", false), "delivered": m.get("consegnata", true),
	}))
	_write(to + "/files.json", _dicts(_read(from + "/file.json", [])).map(func(f: Dictionary) -> Dictionary: return {
		"id": f.get("id", ""), "level": f.get("livello", 1), "name": f.get("nome", ""),
		"content": f.get("contenuto", ""), "original": f.get("originale", ""), "created": f.get("creato", ""),
		"read": f.get("letto", false), "corrected": f.get("corretto", false),
		"corrected_at": f.get("corretto_il", ""), "delivered": f.get("consegnato", true),
	}))
	_write(to + "/agenda.json", _dicts(_read(from + "/agenda.json", [])).map(func(s: Dictionary) -> Dictionary: return {
		"id": s.get("id", ""), "date": s.get("data", ""), "time": s.get("ora", ""), "title": s.get("titolo", ""),
		"checklist": _dicts(s.get("checklist", [])).map(func(c: Dictionary) -> Dictionary: return {"text": c.get("t", ""), "done": c.get("ok", false)}),
	}))


static func _interview(old: Dictionary) -> Dictionary:
	var messages: Array = []
	for m: Dictionary in _dicts(old.get("messaggi", [])):
		var message := {"who": SPEAKERS.get(m.get("chi", ""), "system"), "text": m.get("testo", ""), "time": m.get("ora", "")}
		if str(m.get("glitch", "")) != "":
			message["glitch"] = GLITCHES.get(m.glitch, m.glitch)
		messages.append(message)
	return {
		"version": 1, "number": old.get("numero", 0), "level": old.get("livello", 1),
		"status": "open" if old.get("stato", "") == "aperto" else "closed",
		"opened_at": old.get("aperto", ""), "closed_at": old.get("chiuso", ""),
		"summary": old.get("riassunto", ""), "searches": old.get("ricerche", []), "messages": messages,
	}


static func _page(p: Dictionary) -> Dictionary:
	return {"id": p.get("id", ""), "title": p.get("titolo", ""), "session": p.get("sessione", 0), "text": p.get("testo", ""), "created": p.get("creato", ""), "modified": p.get("modificato", "")}


static func _trash_item(item: Dictionary) -> Dictionary:
	var new := {"id": item.get("id", ""), "type": "draft" if item.get("tipo", "") == "bozza" else "page", "name": item.get("nome", ""), "deleted": item.get("eliminato", "")}
	if item.has("dati"):
		new["data"] = _page(_dict(item.dati))
	if item.has("testo"):
		new["text"] = item.testo
	if item.has("sessione"):
		new["session"] = item.sessione
	return new


# --- Helpers ---------------------------------------------------------------

static func _app(id: String) -> String:
	return APP_IDS.get(id, id)


static func _campaign(id: String) -> String:
	return CAMPAIGN_IDS.get(id, id)


static func _read(path: String, default: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return default
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data != null else default


## Like Save.write_json: a temporary file, then a rename, so a cut write leaves no half file.
static func _write(path: String, data: Variant) -> void:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("SaveMigration: can't write %s." % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


## The old files were written by hand-editable JSON: anything of the wrong type becomes empty.
static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _list(value: Variant) -> Array:
	return value if value is Array else []


static func _dicts(value: Variant) -> Array:
	return _list(value).filter(func(item: Variant) -> bool: return item is Dictionary)


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + folder)
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file_name)
	DirAccess.remove_absolute(path)


## Moves the old file or folder into LEGACY_DIR, keeping its relative path.
static func _backup(path: String, relative: String) -> void:
	var target := LEGACY_DIR + "/" + relative
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var err := DirAccess.rename_absolute(path, target)
	if err != OK:
		push_warning("SaveMigration: can't move %s to %s (%s)." % [path, target, error_string(err)])
