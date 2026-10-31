extends Node
## Persistence in human-readable JSON files under user://.
## config/ applies to every campaign; campaigns/<id>/ holds the data of a single campaign.

## An interface setting changed: whoever uses it updates right away.
signal ui_changed(key: String)

const CONFIG_DIR := "user://config"
const UI_PATH := CONFIG_DIR + "/ui.json"
const CAMPAIGNS_DIR := "user://campaigns"
const INDEX_PATH := CAMPAIGNS_DIR + "/index.json"
const DEFAULT_CAMPAIGN := "branch"
## Groups writes that happen close together (e.g. several windows moved in a row).
const WRITE_DELAY := 0.4

## Id of the active campaign, which is also the name of its folder.
var campaign_id: String = ""

var _ui: Dictionary = {}
var _ui_timer: Timer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CONFIG_DIR)
	SaveMigration.run()
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


## Writes whatever is pending right away. Call before restarting or quitting.
func flush() -> void:
	if _ui_timer != null and not _ui_timer.is_stopped():
		_ui_timer.stop()
		_write_ui()


## Path of a file inside the active campaign's folder, e.g. "interviews/001.json".
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


## Names of the .json files in a campaign subfolder, in alphabetical order.
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
		push_warning("Save: %s is not valid JSON (line %d), using defaults." % [path, json.get_error_line()])
		_set_aside(path)
		return default
	return json.data


## Renames an unreadable save to <name>.corrupt-<time>, so the next write
## (made from the defaults) doesn't destroy what could still be recovered by hand.
func _set_aside(path: String) -> void:
	if not path.begins_with("user://"):
		return
	var aside := "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())]
	if DirAccess.rename_absolute(path, aside) == OK:
		push_warning("Save: the unreadable file was kept as %s." % aside)


## Atomic write: first a temporary file, then a rename over the original.
func write_json(path: String, data: Variant) -> Error:
	return write_text(path, JSON.stringify(data, "\t"))


## Like write_json, for any text (e.g. Markdown notes in the vault).
func write_text(path: String, text: String) -> Error:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("Save: can't write %s (%s)." % [tmp_path, error_string(open_error)])
		return open_error
	file.store_string(text)
	file.close()
	var rename_error := DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		push_error("Save: can't replace %s (%s)." % [path, error_string(rename_error)])
	return rename_error


func _write_ui() -> void:
	write_json(UI_PATH, _ui)


## Reads the campaign index; on first start creates the default campaign.
func _open_campaign_index() -> void:
	DirAccess.make_dir_recursive_absolute(CAMPAIGNS_DIR)
	var index: Variant = read_json(INDEX_PATH, null)
	if not index is Dictionary or str(index.get("active", "")) == "":
		index = {
			"version": 1,
			"active": DEFAULT_CAMPAIGN,
			"campaigns": [{"id": DEFAULT_CAMPAIGN, "name": "Filiale", "created": Time.get_datetime_string_from_system()}],
		}
		write_json(INDEX_PATH, index)
	campaign_id = str(index.active)
	DirAccess.make_dir_recursive_absolute(campaign_path("interviews"))
