extends Node
## Loads the update downloaded by the Updater (a Godot .pck in user://updates/) on top of the
## app's own files. It's the first autoload, so everything loaded after it (the other autoloads,
## the desktop, data/) already sees the patched files.
## This script can't be patched: keep it small, and change it only with a new installer.

const DIR := "user://updates"
const CURRENT := DIR + "/current.json"
## Written before loading a patch, removed by confirm(): if it's still there at the next start,
## the patch broke the startup and gets disabled.
const BOOTING := DIR + "/booting"

## Version of the installed app, i.e. of the installer (a pack's project.godot is never applied).
var base_version: String = ""
## Version of the loaded patch, empty when running the base.
var patch_version: String = ""
## Version of a patch disabled because it broke the startup.
var failed_version: String = ""


func _init() -> void:
	base_version = str(ProjectSettings.get_setting("application/config/version", ""))
	# In the editor a patch would shadow the files being edited.
	if OS.has_feature("editor") and not OS.get_cmdline_user_args().has("--with-patch"):
		return
	var current := read_current()
	if current.is_empty():
		return
	if str(current.get("base", "")) != base_version:
		# A new installer replaced the base the patch was built on.
		clear()
		return
	if bool(current.get("failed", false)):
		failed_version = str(current.get("version", ""))
		return
	var path := DIR.path_join(str(current.get("file", "")))
	if FileAccess.file_exists(BOOTING) or not FileAccess.file_exists(path):
		current["failed"] = true
		failed_version = str(current.get("version", ""))
		_write_current(current)
		DirAccess.remove_absolute(BOOTING)
		DirAccess.remove_absolute(path)
		return
	FileAccess.open(BOOTING, FileAccess.WRITE)
	if ProjectSettings.load_resource_pack(path, true):
		patch_version = str(current.get("version", ""))
	else:
		DirAccess.remove_absolute(BOOTING)


## The version actually running.
func version() -> String:
	return patch_version if patch_version != "" else base_version


## The desktop is up: the loaded patch works.
func confirm() -> void:
	if FileAccess.file_exists(BOOTING):
		DirAccess.remove_absolute(BOOTING)


func read_current() -> Dictionary:
	if not FileAccess.file_exists(CURRENT):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CURRENT))
	return data if data is Dictionary else {}


## Removes every downloaded patch (the running one stays loaded until the app quits).
func clear() -> void:
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))


func _write_current(current: Dictionary) -> void:
	var file := FileAccess.open(CURRENT, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(current, "\t"))
