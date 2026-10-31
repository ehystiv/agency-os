class_name BranchBackup
extends RefCounted
## Backup of the active campaign as a single .zip: backup.json plus the campaign's folder
## under campaign/. Restoring extracts to a temporary folder first and swaps it in only
## when every entry was valid; the replaced campaign is kept in user://backup_previous/.

const FORMAT := "agencyos-campaign"
const VERSION := 1
const MANIFEST := "backup.json"
const DATA_DIR := "campaign/"
const PREVIOUS_DIR := "user://backup_previous"
## Nothing a campaign would hold: refuses zips that would fill the disk.
const MAX_TOTAL_BYTES := 512 * 1024 * 1024
const SAFE_NAME := "^[A-Za-z0-9 _.,()+-]+$"


## Writes the active campaign to zip_path; "" on success, otherwise the error to show.
static func export_to(zip_path: String) -> String:
	var root := Save.campaign_path("").trim_suffix("/")
	var packer := ZIPPacker.new()
	if packer.open(zip_path) != OK:
		return _t("Non riesco a scrivere «%s».") % zip_path.get_file()
	var manifest := {
		"format": FORMAT,
		"version": VERSION,
		"app_version": BootPatch.version(),
		"campaign": Save.campaign_id,
		"created": Time.get_datetime_string_from_system(),
	}
	var ok := _add(packer, MANIFEST, JSON.stringify(manifest, "\t").to_utf8_buffer())
	for relative in _files_under(root, ""):
		ok = ok and _add(packer, DATA_DIR + relative, FileAccess.get_file_as_bytes(root + "/" + relative))
	packer.close()
	if not ok:
		DirAccess.remove_absolute(zip_path)
		return _t("Errore durante la scrittura del backup.")
	return ""


## Reads a backup without touching anything: {error, created, app_version, interviews}.
static func inspect(zip_path: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"error": _t("Il file non è un archivio .zip valido.")}
	var result := _check(reader)
	reader.close()
	return result


## Replaces the active campaign with the backup's. "" on success: the app must restart
## right away, because the autoloads still hold the old campaign in memory.
static func restore_from(zip_path: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return _t("Il file non è un archivio .zip valido.")
	var info := _check(reader)
	if info.has("error"):
		reader.close()
		return info.error
	var target := Save.campaign_path("").trim_suffix("/")
	var staging := target + ".restore"
	_remove_tree(staging)
	for entry: String in reader.get_files():
		if not entry.begins_with(DATA_DIR) or entry.ends_with("/"):
			continue
		var path := staging + "/" + entry.trim_prefix(DATA_DIR)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			reader.close()
			_remove_tree(staging)
			return _t("Non riesco a estrarre il backup.")
		file.store_buffer(reader.read_file(entry))
		file.close()
	reader.close()
	DirAccess.make_dir_recursive_absolute(staging + "/interviews")
	# From here on nothing may write the old campaign over the restored one.
	Save.lock_campaign()
	_remove_tree(PREVIOUS_DIR)
	DirAccess.make_dir_recursive_absolute(PREVIOUS_DIR)
	var kept := PREVIOUS_DIR + "/" + Save.campaign_id
	if DirAccess.rename_absolute(target, kept) != OK or DirAccess.rename_absolute(staging, target) != OK:
		# Put back whatever was moved, so the campaign is never left missing.
		if not DirAccess.dir_exists_absolute(target) and DirAccess.dir_exists_absolute(kept):
			DirAccess.rename_absolute(kept, target)
		_remove_tree(staging)
		return _t("Non riesco a sostituire i dati della Filiale.")
	return ""


static func default_name() -> String:
	var date := Time.get_date_string_from_system()
	return "AgencyOS-%s-%s.zip" % [_t("Filiale"), date]


static func _t(text: String) -> String:
	return String(TranslationServer.translate(text))


static func _check(reader: ZIPReader) -> Dictionary:
	var entries := reader.get_files()
	if not entries.has(MANIFEST):
		return {"error": _t("Questo archivio non è un backup di AgencyOS.")}
	var manifest: Variant = JSON.parse_string(reader.read_file(MANIFEST).get_string_from_utf8())
	if not manifest is Dictionary or manifest.get("format", "") != FORMAT:
		return {"error": _t("Questo archivio non è un backup di AgencyOS.")}
	if int(manifest.get("version", 0)) > VERSION:
		return {"error": _t("Il backup viene da una versione più recente di AgencyOS.")}
	var safe := RegEx.create_from_string(SAFE_NAME)
	var total := 0
	var interviews := 0
	for entry in entries:
		if entry == MANIFEST or entry.ends_with("/"):
			continue
		if not entry.begins_with(DATA_DIR):
			return {"error": _t("Il backup contiene file inattesi.")}
		for part in entry.trim_prefix(DATA_DIR).split("/"):
			if part == "" or part == "." or part == ".." or not safe.search(part):
				return {"error": _t("Il backup contiene file inattesi.")}
		total += reader.read_file(entry).size()
		if total > MAX_TOTAL_BYTES:
			return {"error": _t("Il backup è troppo grande.")}
		if entry.begins_with(DATA_DIR + "interviews/") and entry.ends_with(".json"):
			interviews += 1
	return {"created": str(manifest.get("created", "")), "app_version": str(manifest.get("app_version", "")), "interviews": interviews}


static func _add(packer: ZIPPacker, name: String, bytes: PackedByteArray) -> bool:
	if packer.start_file(name) != OK:
		return false
	var ok := packer.write_file(bytes) == OK
	return packer.close_file() == OK and ok


## Relative paths of the files under root, temporary writes left out.
static func _files_under(root: String, prefix: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var folder := root + ("/" + prefix if prefix != "" else "")
	for file_name in DirAccess.get_files_at(folder):
		if not file_name.ends_with(".tmp"):
			result.append(prefix + file_name)
	for dir_name in DirAccess.get_directories_at(folder):
		result.append_array(_files_under(root, prefix + dir_name + "/"))
	return result


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file_name)
	for dir_name in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + dir_name)
	DirAccess.remove_absolute(path)
