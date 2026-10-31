class_name PlayerLibrary
extends RefCounted
## The Player's own music: audio files from a folder, and the saved collection (pieces
## downloaded from YouTube, with the name the Manager chose). The collection belongs to
## the Manager, not to a campaign: user://player/library.json, the audio in user://player/cache/.

const DIR := "user://player"
const LIBRARY_PATH := DIR + "/library.json"
const CACHE_DIR := DIR + "/cache"
## What Godot can decode by itself.
const EXTENSIONS: PackedStringArray = ["mp3", "ogg", "wav"]

## {id, name, url, file (name inside CACHE_DIR), added}
var items: Array[Dictionary] = []


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for item: Variant in Save.read_json(LIBRARY_PATH, []):
		if item is Dictionary and str(item.get("file", "")) != "":
			items.append(item)


func add(display_name: String, url: String, file: String) -> Dictionary:
	var item := {
		"id": "y-%d-%d" % [Time.get_unix_time_from_system(), randi() % 1000],
		"name": display_name,
		"url": url,
		"file": file,
		"added": Time.get_datetime_string_from_system(),
	}
	items.append(item)
	_save()
	return item


func rename(item: Dictionary, display_name: String) -> void:
	item.name = display_name
	_save()


## Removes the piece and its audio file.
func remove(item: Dictionary) -> void:
	var path := path_of(item)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	items.erase(item)
	_save()


func find(id: String) -> Dictionary:
	for item in items:
		if item.id == id:
			return item
	return {}


static func path_of(item: Dictionary) -> String:
	return CACHE_DIR.path_join(str(item.file))


## The audio files of a folder (not its subfolders), by name.
static func folder_files(folder: String) -> PackedStringArray:
	var found: PackedStringArray = []
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return found
	for file_name in DirAccess.get_files_at(folder):
		if file_name.get_extension().to_lower() in EXTENSIONS and not file_name.begins_with("."):
			found.append(folder.path_join(file_name))
	found.sort()
	return found


## Loads an mp3, ogg or wav file; null if it can't be read.
static func load_audio(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


func _save() -> void:
	Save.write_json(LIBRARY_PATH, items)
