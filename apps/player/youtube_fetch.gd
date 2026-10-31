class_name YouTubeFetch
extends Node
## Downloads the audio of a YouTube video (or of anything else yt-dlp knows) as mp3,
## with yt-dlp and ffmpeg (see YouTubeTools). Godot can't decode YouTube's own
## formats, so the audio is converted and kept, not streamed.
## yt-dlp runs in a thread; its progress lines come back as signals.

signal progress(fraction: float)
## ok: path is the mp3 written and title the video's; otherwise error says why (Italian).
signal finished(ok: bool, path: String, title: String, error: String)

var busy := false

var _thread: Thread
var _pid := -1
var _cancelled := false


## Starts the download; out_base is the path of the file to write, without extension.
func start(url: String, out_base: String) -> void:
	if busy:
		return
	var yt_dlp := YouTubeTools.find("yt-dlp")
	var ffmpeg := YouTubeTools.find("ffmpeg")
	if yt_dlp == "" or ffmpeg == "":
		finished.emit(false, "", "", "Mancano i componenti per YouTube (yt-dlp, ffmpeg).")
		return
	busy = true
	_cancelled = false
	var args: PackedStringArray = [
		"--no-playlist", "--no-update", "-x", "--audio-format", "mp3", "--audio-quality", "5",
		"--ffmpeg-location", ffmpeg.get_base_dir(), "--newline", "--progress", "--no-simulate",
		"--print", "before_dl:TITLE %(title)s", "--print", "after_move:FILE %(filepath)s",
		"-o", out_base + ".%(ext)s", "--", url,
	]
	_thread = Thread.new()
	_thread.start(_run.bind(yt_dlp, args))


func cancel() -> void:
	_cancelled = true
	if _pid > 0:
		OS.kill(_pid)


## In the thread. stderr is merged into stdout by the shell, so a single pipe is read
## and neither can fill up and block yt-dlp.
func _run(yt_dlp: String, args: PackedStringArray) -> void:
	var command: PackedStringArray = ["-c", "exec \"$@\" 2>&1", "sh", yt_dlp]
	command.append_array(args)
	var process := OS.execute_with_pipe("/bin/sh", command)
	if process.is_empty():
		_done.call_deferred(false, "", "", "Impossibile avviare yt-dlp.")
		return
	_pid = int(process.pid)
	var pipe: FileAccess = process.stdio
	var title := ""
	var path := ""
	var last_error := ""
	var percent := RegEx.create_from_string("\\[download\\]\\s+([\\d.]+)%")
	while true:
		var line := pipe.get_line()
		if line == "" and (pipe.eof_reached() or pipe.get_error() != OK):
			if not OS.is_process_running(_pid):
				break
			OS.delay_msec(20)
			continue
		if line.begins_with("TITLE "):
			title = line.substr(6).strip_edges()
		elif line.begins_with("FILE "):
			path = line.substr(5).strip_edges()
		elif line.begins_with("ERROR:"):
			last_error = line.substr(6).strip_edges()
		else:
			var found := percent.search(line)
			if found != null:
				_report.call_deferred(float(found.get_string(1)) / 100.0)
	var code := OS.get_process_exit_code(_pid)
	_pid = -1
	if _cancelled:
		_done.call_deferred(false, "", "", "Download annullato.")
	elif code != 0 or path == "" or not FileAccess.file_exists(path):
		var reason := last_error.left(200) if last_error != "" else "codice %d" % code
		_done.call_deferred(false, "", "", "yt-dlp non è riuscito a scaricare l'audio (%s). Controlla il link e riprova." % reason)
	else:
		_done.call_deferred(true, path, title, "")


func _report(fraction: float) -> void:
	progress.emit(fraction)


func _done(ok: bool, path: String, title: String, error: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	busy = false
	finished.emit(ok, path, title, error)


func _exit_tree() -> void:
	if _thread != null:
		cancel()
		_thread.wait_to_finish()
		_thread = null
