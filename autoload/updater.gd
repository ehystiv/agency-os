extends Node
## Looks for a newer patch on GitHub, downloads it and verifies it, then hands it to BootPatch
## (user://updates/current.json), which loads it at the next start. See "Updates" in CLAUDE.md.

signal state_changed(state: State)

enum State { IDLE, CHECKING, UP_TO_DATE, AVAILABLE, NEEDS_INSTALLER, DOWNLOADING, READY, ERROR }

const MANIFEST_URL := "https://github.com/ehystiv/agency-os/releases/latest/download/update.json"
const RELEASES_PAGE := "https://github.com/ehystiv/agency-os/releases/latest"
## Automatic checks happen at most once in this many seconds.
const CHECK_INTERVAL := 24 * 3600
const TIMEOUT := 30.0

var state: State = State.IDLE
## The update.json of the latest release (version, base, file, url, sha256, size, notes, page).
var manifest: Dictionary = {}
## Italian, shown as is when state is ERROR.
var error: String = ""
## Overridable for tests.
var manifest_url: String = MANIFEST_URL
## Whether the last check was started by check_daily() rather than by the user.
var automatic: bool = false

var _http: HTTPRequest
var _part_path: String = ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	add_child(_http)


## Checks for an update, unless the last check was less than CHECK_INTERVAL ago.
func check_daily() -> void:
	var now := int(Time.get_unix_time_from_system())
	if now - int(Save.get_ui("update_checked_at", 0)) < CHECK_INTERVAL:
		return
	check(true)


func check(is_automatic: bool = false) -> void:
	if _busy():
		return
	automatic = is_automatic
	_set_state(State.CHECKING)
	_http.download_file = ""
	if _http.request(manifest_url) != OK:
		_fail("Impossibile contattare il server degli aggiornamenti.")
		return
	var result: Array = await _http.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_fail("Server degli aggiornamenti non raggiungibile (%s)." % _describe(result))
		return
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not data is Dictionary or not data.has("version"):
		_fail("Risposta del server degli aggiornamenti non valida.")
		return
	Save.set_ui("update_checked_at", int(Time.get_unix_time_from_system()))
	manifest = data
	var version := str(manifest.version)
	if compare(version, BootPatch.version()) <= 0 or version == BootPatch.failed_version:
		_set_state(State.UP_TO_DATE)
	elif str(manifest.get("base", "")) != BootPatch.base_version:
		_set_state(State.NEEDS_INSTALLER)
	else:
		_set_state(State.AVAILABLE)


## Downloads the patch in manifest. Read progress() while DOWNLOADING.
func download() -> void:
	if state != State.AVAILABLE:
		return
	_set_state(State.DOWNLOADING)
	DirAccess.make_dir_recursive_absolute(BootPatch.DIR)
	var file := str(manifest.get("file", "")).get_file()
	var path := BootPatch.DIR.path_join(file)
	_part_path = path + ".part"
	_http.download_file = _part_path
	if file == "" or _http.request(str(manifest.get("url", ""))) != OK:
		_fail("Impossibile avviare il download dell'aggiornamento.")
		return
	var result: Array = await _http.request_completed
	_http.download_file = ""
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_discard_part()
		_fail("Download dell'aggiornamento non riuscito (%s)." % _describe(result))
		return
	if FileAccess.get_size(_part_path) != int(manifest.get("size", -1)) \
			or FileAccess.get_sha256(_part_path) != str(manifest.get("sha256", "")).to_lower():
		_discard_part()
		_fail("L'aggiornamento scaricato è danneggiato. Riprovare più tardi.")
		return
	var previous := BootPatch.read_current()
	DirAccess.rename_absolute(_part_path, path)
	_part_path = ""
	var current := {"version": str(manifest.version), "base": BootPatch.base_version, "file": file, "sha256": manifest.sha256}
	var out := FileAccess.open(BootPatch.CURRENT, FileAccess.WRITE)
	if out == null:
		_fail("Impossibile salvare l'aggiornamento.")
		return
	out.store_string(JSON.stringify(current, "\t"))
	out.close()
	var old_file := str(previous.get("file", ""))
	if old_file != "" and old_file != file:
		DirAccess.remove_absolute(BootPatch.DIR.path_join(old_file))
	_set_state(State.READY)


## 0..1 while DOWNLOADING.
func progress() -> float:
	var size := int(manifest.get("size", 0))
	return clampf(float(_http.get_downloaded_bytes()) / size, 0.0, 1.0) if size > 0 else 0.0


## Restarts the app, so the downloaded patch is loaded.
func restart() -> void:
	Save.flush()
	OS.set_restart_on_exit(true)
	get_tree().quit()


func release_page() -> String:
	return str(manifest.get("page", RELEASES_PAGE))


## -1, 0 or 1 comparing two "x.y.z" versions.
static func compare(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


func _busy() -> bool:
	return state == State.CHECKING or state == State.DOWNLOADING


func _set_state(new_state: State) -> void:
	state = new_state
	state_changed.emit(state)


func _fail(message: String) -> void:
	error = message
	_set_state(State.ERROR)


func _discard_part() -> void:
	if _part_path != "" and FileAccess.file_exists(_part_path):
		DirAccess.remove_absolute(_part_path)
	_part_path = ""


func _describe(result: Array) -> String:
	return "HTTP %d" % result[1] if result[0] == HTTPRequest.RESULT_SUCCESS else "errore %d" % result[0]
