class_name YouTubeTools
extends Node
## The programs the Raccolta needs to save audio from YouTube: yt-dlp, ffmpeg and ffprobe.
## On a Mac without them the Player downloads them once into user://tools/ (about 75 MB):
## yt-dlp from its official releases, checked against the release's SHA2-256SUMS;
## ffmpeg and ffprobe from a pinned static build, checked against the hashes below.
## yt-dlp must follow YouTube's changes, so the managed copy updates itself once a day.
## Files downloaded by the app itself get no quarantine flag, so macOS lets them run.

signal progress(fraction: float, label: String)
## error is empty on success (Italian otherwise).
signal install_finished(error: String)
signal update_finished

const DIR := "user://tools"
const YT_DLP_URL := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
const YT_DLP_SUMS_URL := "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"
const FFMPEG_BASE := "https://github.com/eugeneware/ffmpeg-static/releases/download/b6.1.1/"
## Static builds by architecture: tool -> [file in the release, sha256 of the .gz].
const FFMPEG_BUILDS := {
	"arm64": {
		"ffmpeg": ["ffmpeg-darwin-arm64.gz", "8923876afa8db5585022d7860ec7e589af192f441c56793971276d450ed3bbfa"],
		"ffprobe": ["ffprobe-darwin-arm64.gz", "d986a8ec7b030899fe66a8a288ed809a3543338705a3ce178cfb85869c5d80be"],
	},
	"x86_64": {
		"ffmpeg": ["ffmpeg-darwin-x64.gz", "929b375c1182d956c51f7ac25e0b2b0411fb01f6f407aa15c9758efeb4242106"],
		"ffprobe": ["ffprobe-darwin-x64.gz", "d4da574d6e2e197bd259b47d69cf262df9e312af24ad960444f6d806d3d4c186"],
	},
}
## Where installed programs may already be: an app opened from the Finder has no shell PATH.
const SYSTEM_DIRS: PackedStringArray = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
const UPDATE_INTERVAL := 24 * 3600
const UPDATED_PREF := "yt_dlp_updated_at"
## Rough sizes, for the progress bar.
const YT_DLP_BYTES := 37_000_000
const GZ_BYTES := 20_000_000
const DOWNLOAD_TIMEOUT := 600.0

var installing := false
## Off only in tests, to see the Mac as one without Homebrew.
static var use_system := true
var updating := false

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = DOWNLOAD_TIMEOUT
	add_child(_http)


## The program to run: the copy managed by AgencyOS first, then one installed on the Mac.
static func find(tool_name: String) -> String:
	var managed := ProjectSettings.globalize_path(DIR).path_join(tool_name)
	if FileAccess.file_exists(managed):
		return managed
	if not use_system:
		return ""
	for dir in SYSTEM_DIRS:
		if FileAccess.file_exists(dir.path_join(tool_name)):
			return dir.path_join(tool_name)
	var home := OS.get_environment("HOME")
	if home != "" and FileAccess.file_exists(home.path_join(".local/bin").path_join(tool_name)):
		return home.path_join(".local/bin").path_join(tool_name)
	return ""


static func ready_to_use() -> bool:
	return find("yt-dlp") != "" and find("ffmpeg") != ""


static func is_managed(tool_name: String) -> bool:
	return find(tool_name).begins_with(ProjectSettings.globalize_path(DIR))


## Downloads what is missing. Ends with install_finished.
func install() -> void:
	if installing:
		return
	installing = true
	DirAccess.make_dir_recursive_absolute(DIR)
	var arch := Engine.get_architecture_name()
	if not FFMPEG_BUILDS.has(arch):
		_finish_install("Architettura non supportata (%s)." % arch)
		return
	var steps: Array[Dictionary] = []
	if find("yt-dlp") == "":
		steps.append({"tool": "yt-dlp", "bytes": YT_DLP_BYTES})
	for tool: String in ["ffmpeg", "ffprobe"]:
		if find(tool) == "":
			steps.append({"tool": tool, "bytes": GZ_BYTES})
	var total := 0.0
	for step in steps:
		total += step.bytes
	var done := 0.0
	for step in steps:
		var tool: String = step.tool
		var error := ""
		var label := "Scarico %s…" % tool
		var tick := func() -> void: progress.emit((done + minf(_http.get_downloaded_bytes(), step.bytes)) / total, label)
		var timer := Timer.new()
		timer.wait_time = 0.2
		timer.timeout.connect(tick)
		add_child(timer)
		timer.start()
		if tool == "yt-dlp":
			error = await _install_yt_dlp()
		else:
			var build: Array = FFMPEG_BUILDS[arch][tool]
			error = await _install_gz(tool, FFMPEG_BASE + str(build[0]), str(build[1]))
		timer.queue_free()
		if error != "":
			_finish_install(error)
			return
		done += step.bytes
	if find("yt-dlp") != "" and is_managed("yt-dlp"):
		Save.set_ui(UPDATED_PREF, int(Time.get_unix_time_from_system()))
	_finish_install("")


## Updates the managed yt-dlp if the last update is older than a day (yt-dlp -U).
## A system copy (Homebrew, pip) is left to its owner.
func update_if_due() -> void:
	if updating or installing or not is_managed("yt-dlp"):
		return
	var now := int(Time.get_unix_time_from_system())
	if now - int(Save.get_ui(UPDATED_PREF, 0)) < UPDATE_INTERVAL:
		return
	updating = true
	var path := find("yt-dlp")
	var task := WorkerThreadPool.add_task(func() -> void: OS.execute(path, PackedStringArray(["--update"])))
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().create_timer(0.2).timeout
	WorkerThreadPool.wait_for_task_completion(task)
	Save.set_ui(UPDATED_PREF, now)
	updating = false
	update_finished.emit()


func _install_yt_dlp() -> String:
	var sums := await _fetch_text(YT_DLP_SUMS_URL)
	var expected := ""
	for line in sums.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[1] == "yt-dlp_macos":
			expected = parts[0].to_lower()
	if expected == "":
		return "Non riesco a verificare yt-dlp: controlla la connessione."
	var target := DIR.path_join("yt-dlp")
	var error := await _download(YT_DLP_URL, target + ".part", expected)
	if error != "":
		return error
	DirAccess.rename_absolute(target + ".part", target)
	return _make_executable(target)


func _install_gz(tool: String, url: String, expected: String) -> String:
	var target := DIR.path_join(tool)
	var error := await _download(url, target + ".gz", expected)
	if error != "":
		return error
	# gunzip ships with macOS: it turns tool.gz into tool.
	var output := []
	if OS.execute("/usr/bin/gunzip", PackedStringArray(["-f", ProjectSettings.globalize_path(target + ".gz")]), output, true) != 0:
		return "Non riesco a estrarre %s." % tool
	return _make_executable(target)


func _download(url: String, path: String, sha256: String) -> String:
	_http.download_file = path
	if _http.request(url) != OK:
		_http.download_file = ""
		return "Non riesco a contattare GitHub."
	var result: Array = await _http.request_completed
	_http.download_file = ""
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_remove(path)
		return "Download non riuscito (%s). Controlla la connessione e riprova." % ("HTTP %d" % result[1] if result[0] == HTTPRequest.RESULT_SUCCESS else "errore %d" % result[0])
	if FileAccess.get_sha256(path) != sha256:
		_remove(path)
		return "Il file scaricato non corrisponde a quello atteso: non lo installo."
	return ""


func _fetch_text(url: String) -> String:
	_http.download_file = ""
	if _http.request(url) != OK:
		return ""
	var result: Array = await _http.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return ""
	return (result[3] as PackedByteArray).get_string_from_utf8()


func _make_executable(path: String) -> String:
	var global := ProjectSettings.globalize_path(path)
	if OS.execute("/bin/chmod", PackedStringArray(["755", global])) != 0:
		return "Non riesco a rendere eseguibile %s." % path.get_file()
	return ""


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Deferred: with nothing to download, install() would otherwise end before its caller listens.
func _finish_install(error: String) -> void:
	installing = false
	install_finished.emit.call_deferred(error)
