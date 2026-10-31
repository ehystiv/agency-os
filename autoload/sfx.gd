extends Node
## System sounds and master volume (applied to the main output).
## enabled only concerns system sounds; the Player's music follows the master volume.
## The sounds are the prototype's, synthesized with Synth and prepared in the background at startup.

signal settings_changed

const BUS := "System"
const VOICES := 6
const SQUARE := Synth.Wave.SQUARE
const SINE := Synth.Wave.SINE
const TRIANGLE := Synth.Wave.TRIANGLE
## Attack of the system sounds (sharper than the music's).
const ATTACK := 0.01
const HUM_FADE_SECONDS := 0.6
## Dice hits: variants of Synth.knock(), and voices of their own (six dice can hit together).
const DICE_VARIANTS := 8
const DICE_VOICES := 8

var enabled: bool = true:
	set(value):
		if value == enabled:
			return
		enabled = value
		if not enabled:
			stop_hum()
		_store()

var volume: float = 0.8:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(value, volume):
			return
		volume = value
		_store()

var _sounds: Dictionary = {}
var _sounds_lock := Mutex.new()
var _build_task := -1
var _voices: Array[AudioStreamPlayer] = []
var _hum: AudioStreamPlayer
var _dice_voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	var audio: Dictionary = Save.get_ui("audio", {})
	enabled = bool(audio.get("enabled", true))
	volume = float(audio.get("volume", 0.8))
	_apply_volume()
	_ensure_bus()
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		_voices.append(voice)
	_hum = AudioStreamPlayer.new()
	_hum.bus = BUS
	add_child(_hum)
	for i in DICE_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		_dice_voices.append(voice)
	_build_task = WorkerThreadPool.add_task(_build_all)


func _exit_tree() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)


func toggle() -> void:
	enabled = not enabled


## Plays a system sound: modem, ding, mail, pop, chime, key, heartbeat (dice: dice_hit()).
func play(sound: StringName) -> void:
	if not enabled:
		return
	_sounds_lock.lock()
	var stream: AudioStreamWAV = _sounds.get(sound)
	_sounds_lock.unlock()
	if stream == null:
		stream = _build(sound)
	var voice: AudioStreamPlayer = null
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		voice = _voices[0]
	voice.stream = stream
	voice.play()


## A die hitting the tray or another die; strength 0..1 from the speed of the hit.
## When all voices are busy the hit is dropped: a softer one is lost in the rattle anyway.
func dice_hit(strength: float) -> void:
	if not enabled or strength <= 0.0:
		return
	for voice in _dice_voices:
		if not voice.playing:
			voice.stream = Synth.knock(randi() % DICE_VARIANTS)
			voice.volume_db = linear_to_db(clampf(strength, 0.03, 1.0))
			voice.pitch_scale = randf_range(0.94, 1.06)
			voice.play()
			return


## Continuous hum during AgencyOS searches.
func start_hum() -> void:
	if not enabled or _hum.playing:
		return
	_hum.stream = Synth.hum()
	_hum.volume_db = 0.0
	_hum.play()


func stop_hum() -> void:
	if _hum == null or not _hum.playing:
		return
	var tween := create_tween()
	tween.tween_property(_hum, "volume_db", -40.0, HUM_FADE_SECONDS)
	tween.tween_callback(_hum.stop)


# --- Prototype sounds ------------------------------------------------------

func _build_all() -> void:
	for sound: StringName in [&"ding", &"mail", &"pop", &"chime", &"key", &"heartbeat", &"modem"]:
		_build(sound)
	for variant in DICE_VARIANTS:
		Synth.knock(variant)


func _build(sound: StringName) -> AudioStreamWAV:
	var parts: Array = []
	match sound:
		&"chime":
			for i in 4:
				parts.append([i * 0.13, _tone([523, 659, 784, 1047][i], 0.5, TRIANGLE, 0.05)])
		&"ding":
			parts = [[0.0, _tone(880, 0.12, SQUARE, 0.035)], [0.12, _tone(660, 0.25, SQUARE, 0.035)]]
		&"mail":
			parts = [[0.0, _tone(1047, 0.18, SINE, 0.06)], [0.16, _tone(1319, 0.35, SINE, 0.06)]]
		&"pop":
			parts = [[0.0, _tone(380, 0.16, SINE, 0.07, 980)], [0.12, _tone(1200, 0.08, TRIANGLE, 0.03)]]
		&"key":
			parts = [[0.0, Synth.noise(0.012, 0.02, 3200, false)]]
		&"heartbeat":
			parts = [[0.0, _tone(60, 0.18, SINE, 0.12)], [0.28, _tone(55, 0.22, SINE, 0.1)]]
		&"modem":
			parts = [[0.0, _tone(350, 0.45, SINE, 0.03)], [0.0, _tone(440, 0.45, SINE, 0.03)]]
			var dtmf := [[697, 1209], [770, 1336], [852, 1477], [697, 1336], [941, 1336], [770, 1209]]
			for i in dtmf.size():
				parts.append([0.55 + i * 0.11, _tone(dtmf[i][0], 0.08, SINE, 0.04)])
				parts.append([0.55 + i * 0.11, _tone(dtmf[i][1], 0.08, SINE, 0.04)])
			parts.append([1.3, _tone(2100, 0.45, SINE, 0.03)])
			for i in 10:
				parts.append([1.8 + i * 0.09, _tone(1650 if i % 2 else 1850, 0.09, SQUARE, 0.018)])
			parts.append([2.0, Synth.noise(0.6, 0.035, 2400, false)])
			parts.append([2.7, Synth.noise(0.4, 0.025, 1200, false)])
	var stream := Synth.mix(parts)
	_sounds_lock.lock()
	_sounds[sound] = stream
	_sounds_lock.unlock()
	return stream


func _tone(frequency: float, duration: float, wave: Synth.Wave, level: float, end_frequency: float = 0.0) -> AudioStreamWAV:
	return Synth.tone(frequency, duration, wave, level, 0.0, ATTACK, end_frequency)


# --- Volume ----------------------------------------------------------------

func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


## The prototype's sounds have low volumes meant for Web Audio: the bus raises them.
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, linear_to_db(4.0))


func _store() -> void:
	_apply_volume()
	Save.set_ui("audio", {"enabled": enabled, "volume": volume})
	settings_changed.emit()
