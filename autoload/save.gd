extends Node
## Persistenza in file JSON leggibili sotto user://.
## config/ vale per tutte le campagne; campagne/<id>/ contiene i dati di una sola campagna.

const CONFIG_DIR := "user://config"
const UI_PATH := CONFIG_DIR + "/interfaccia.json"
const CAMPAIGNS_DIR := "user://campagne"
const INDEX_PATH := CAMPAIGNS_DIR + "/indice.json"
const DEFAULT_CAMPAIGN := "filiale"
## Raggruppa le scritture ravvicinate (es. più finestre spostate di fila).
const WRITE_DELAY := 0.4

## Un'impostazione dell'interfaccia è cambiata: chi la usa si aggiorna subito.
signal ui_changed(key: String)

## Id della campagna attiva, che è anche il nome della sua cartella.
var campaign_id: String = ""

var _ui: Dictionary = {}
var _ui_timer: Timer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CONFIG_DIR)
	var data: Variant = read_json(UI_PATH, {})
	_ui = data if data is Dictionary else {}
	_open_campaign_index()
	_ui_timer = Timer.new()
	_ui_timer.one_shot = true
	_ui_timer.wait_time = WRITE_DELAY
	_ui_timer.timeout.connect(_write_ui)
	add_child(_ui_timer)


func _exit_tree() -> void:
	flush()


func has_ui(key: String) -> bool:
	return _ui.has(key)


func get_ui(key: String, default: Variant = null) -> Variant:
	return _ui.get(key, default)


func set_ui(key: String, value: Variant) -> void:
	var changed: bool = not _ui.has(key) or _ui[key] != value
	_ui[key] = value
	_ui_timer.start()
	if changed:
		ui_changed.emit(key)


## Scrive subito ciò che è in attesa. Da chiamare prima di riavviare o uscire.
func flush() -> void:
	if _ui_timer != null and not _ui_timer.is_stopped():
		_ui_timer.stop()
		_write_ui()


## Percorso di un file dentro la cartella della campagna attiva, es. "colloqui/001.json".
func campaign_path(relative: String) -> String:
	return "%s/%s/%s" % [CAMPAIGNS_DIR, campaign_id, relative]


func read_campaign(relative: String, default: Variant) -> Variant:
	return read_json(campaign_path(relative), default)


func write_campaign(relative: String, data: Variant) -> Error:
	DirAccess.make_dir_recursive_absolute(campaign_path(relative).get_base_dir())
	return write_json(campaign_path(relative), data)


func delete_campaign(relative: String) -> void:
	var path := campaign_path(relative)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Nomi dei file .json in una sottocartella della campagna, in ordine alfabetico.
func list_campaign(subdir: String) -> PackedStringArray:
	var names: PackedStringArray = []
	for file_name in DirAccess.get_files_at(campaign_path(subdir)):
		if file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	return names


func read_json(path: String, default: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return default
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("Save: %s non è un JSON valido (riga %d), uso i valori predefiniti." % [path, json.get_error_line()])
		return default
	return json.data


## Scrittura atomica: prima un file temporaneo, poi la rinomina sopra l'originale.
func write_json(path: String, data: Variant) -> Error:
	return write_text(path, JSON.stringify(data, "\t"))


## Come write_json, per testo qualsiasi (es. note Markdown nel vault).
func write_text(path: String, text: String) -> Error:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("Save: impossibile scrivere %s (%s)." % [tmp_path, error_string(open_error)])
		return open_error
	file.store_string(text)
	file.close()
	var rename_error := DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		push_error("Save: impossibile sostituire %s (%s)." % [path, error_string(rename_error)])
	return rename_error


func _write_ui() -> void:
	write_json(UI_PATH, _ui)


## Legge l'indice delle campagne; al primo avvio crea la campagna predefinita.
func _open_campaign_index() -> void:
	DirAccess.make_dir_recursive_absolute(CAMPAIGNS_DIR)
	var index: Variant = read_json(INDEX_PATH, null)
	if not index is Dictionary or str(index.get("attiva", "")) == "":
		index = {
			"versione": 1,
			"attiva": DEFAULT_CAMPAIGN,
			"campagne": [{"id": DEFAULT_CAMPAIGN, "nome": "Filiale", "creata": Time.get_datetime_string_from_system()}],
		}
		write_json(INDEX_PATH, index)
	campaign_id = str(index.attiva)
	DirAccess.make_dir_recursive_absolute(campaign_path("colloqui"))
