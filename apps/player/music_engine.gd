class_name MusicEngine
extends Node
## Company hold music, synthesized live as in the prototype.
## A sixteenth-note sequencer prepares the notes one second ahead
## (on worker threads) and plays them on a pool of voices of the "Music" bus.

signal state_changed

const BUS := "Music"
## The notes of these tracks have very low volumes (as in the prototype): the bus raises them.
const BUS_BOOST := 4.0
const LOOKAHEAD := 1.0
## A note that is ready late is played anyway, within this margin.
const LATE_TOLERANCE := 1.5
const VOICES := 20
const SQUARE := Synth.Wave.SQUARE
const TRIANGLE := Synth.Wave.TRIANGLE
const SINE := Synth.Wave.SINE
const SAWTOOTH := Synth.Wave.SAWTOOTH
## The hold music, the ambient sounds for the table ("utility") and the locked one, last.
const TRACKS: Array[Dictionary] = [
	{"id": "welcome", "name": "Benvenuto in Filiale", "bpm": 96, "level": 0},
	{"id": "hold", "name": "Attesa in linea", "bpm": 72, "level": 0},
	{"id": "corridor", "name": "Corridoio B", "bpm": 52, "level": 0},
	{"id": "rain", "name": "Pioggia sui vetri", "bpm": 120, "level": 0, "utility": true},
	{"id": "office", "name": "Ufficio di notte", "bpm": 120, "level": 0, "utility": true},
	{"id": "tension", "name": "Tensione", "bpm": 70, "level": 0, "utility": true},
	{"id": "alarm", "name": "Allarme di contenimento", "bpm": 100, "level": 0, "utility": true},
	{"id": "vault", "name": "███████", "bpm": 44, "level": 3},
]
## Tension grows to full strength in this many seconds.
const TENSION_RISE := 120.0
const CHORDS_1: Array = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]
const CHORDS_WAIT: Array = [[62, 66, 69, 73], [59, 62, 66, 69], [55, 59, 62, 66], [57, 61, 64, 67]]
const CHORDS_CORRIDOR: Array = [[45, 52, 57, 60], [43, 50, 55, 58]]

var track := 0
var playing := false
var paused := false
## Seconds of the track played so far (they stop while paused).
var elapsed := 0.0

var _step := 0
var _next_time := 0.0
## {at: track seconds, task: job id, data: {"stream": AudioStreamWAV}}
var _events: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer] = []
var _analyzer: AudioEffectSpectrumAnalyzerInstance


func _ready() -> void:
	# The screensaver doesn't start while music is playing.
	add_to_group(&"music")
	var bus := _ensure_bus()
	_analyzer = AudioServer.get_bus_effect_instance(bus, 0) as AudioEffectSpectrumAnalyzerInstance
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		_voices.append(voice)
	set_volume(float(Save.get_ui("player_volume", 70)) / 100.0)
	set_process(false)


func is_locked(index: int) -> bool:
	return int(TRACKS[index].level) > Campaign.level()


func play(index: int) -> void:
	if paused and index == track:
		paused = false
	else:
		stop()
		track = index
		_step = 0
		elapsed = 0.0
		_next_time = 0.08
	playing = true
	set_process(true)
	state_changed.emit()


func pause() -> void:
	if not playing:
		return
	playing = false
	paused = true
	for voice in _voices:
		voice.stop()
	set_process(false)
	state_changed.emit()


func stop() -> void:
	playing = false
	paused = false
	elapsed = 0.0
	for voice in _voices:
		voice.stop()
	_drop_events()
	set_process(false)
	state_changed.emit()


func set_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS), linear_to_db(maxf(value * BUS_BOOST, 0.0001)))


## The visualizer bar marking the current track (red), -1 for none.
func marker_bar(bars: int) -> int:
	return track * bars / TRACKS.size() if playing else -1


## Levels for the visualizer: count bands between 60 Hz and 4 kHz, from 0 to 1.
func levels(count: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(count)
	if _analyzer == null or not playing:
		return result
	for i in count:
		var from := 60.0 * pow(4000.0 / 60.0, float(i) / count)
		var to := 60.0 * pow(4000.0 / 60.0, float(i + 1) / count)
		var magnitude := _analyzer.get_magnitude_for_frequency_range(from, to).length()
		result[i] = clampf((linear_to_db(maxf(magnitude, 0.00001)) + 60.0) / 60.0, 0.0, 1.0)
	return result


func _process(delta: float) -> void:
	elapsed += delta
	var step_seconds := 60.0 / float(TRACKS[track].bpm) / 4.0
	while _next_time < elapsed + LOOKAHEAD:
		_run_step(_step, _next_time, step_seconds)
		_next_time += step_seconds
		_step += 1
	var remaining: Array[Dictionary] = []
	for event in _events:
		if event.at > elapsed:
			remaining.append(event)
		elif WorkerThreadPool.is_task_completed(event.task):
			WorkerThreadPool.wait_for_task_completion(event.task)
			_play(event.data.stream)
		elif elapsed - event.at < LATE_TOLERANCE:
			remaining.append(event)
		else:
			WorkerThreadPool.wait_for_task_completion(event.task)
	_events = remaining


# --- Tracks (translated from the prototype's functions) --------------------

func _run_step(step: int, at: float, sd: float) -> void:
	match str(TRACKS[track].id):
		"welcome":
			var chord: Array = CHORDS_1[(step / 16) % 4]
			var s := step % 16
			if s % 2 == 0:
				_note(chord[(s / 2) % 3] + 12, at, sd * 1.6, SQUARE, 0.022)
			if s % 4 == 0:
				_note(chord[0] - 24, at, sd * 3.5, TRIANGLE, 0.07)
			if s % 8 == 4:
				_noise(at, 0.05, 0.03, 6000)
			if s in [0, 6, 12]:
				_note(chord[(s / 6) % 3] + 24, at, sd * 3, SINE, 0.03)
		"hold":
			# Left alone, the hold music slowly goes out of tune.
			var chord: Array = CHORDS_WAIT[(step / 32) % 4].duplicate()
			var s := step % 32
			var detune := -minf(120.0, (at - 150.0) * 0.6) if at > 150.0 else 0.0
			if at > 240.0:
				chord[1] -= 1
			if s == 0:
				for m: int in chord:
					_note(m, at, sd * 30, SINE, 0.03, detune)
			if s % 8 == 0:
				_note(chord[0] - 24, at, sd * 6, TRIANGLE, 0.06, detune)
			if s in [4, 10, 14, 20, 26] and randf() < 0.7:
				_note(chord.pick_random() + 12, at, sd * 3, TRIANGLE, 0.028, detune)
			if at > 200.0 and s == 16 and randf() < 0.5:
				_noise(at, 1.4, 0.012, 900)
		"corridor":
			var chord: Array = CHORDS_CORRIDOR[(step / 64) % 2]
			var s := step % 64
			if s == 0:
				for m: int in chord:
					_note(m, at, sd * 62, TRIANGLE, 0.03)
			if s % 16 == 8 and randf() < 0.5:
				_note([81, 84, 88, 91].pick_random(), at, sd * 10, SINE, 0.018)
			if s % 32 == 0:
				_noise(at, sd * 20, 0.008, 420)
		"rain":
			_rain(step, at, sd)
		"office":
			_office(step, at, sd)
		"tension":
			_tension(step, at, sd)
		"alarm":
			_alarm(step, at, sd)
		"vault":
			var chord: Array = CHORDS_1[(step / 16) % 4]
			var s := step % 16
			var detune := -50.0 + sin(step * 0.05) * 35.0
			if s % 4 == 0:
				_note(chord[(s / 4) % 3] + 12, at, sd * 5, SINE, 0.035, detune)
			if s == 0 or s == 3:
				_queue(at, func() -> AudioStreamWAV: return Synth.tone(52.0, 0.22, SINE, 0.13))
			if s == 8 and randf() < 0.5:
				_noise(at, sd * 10, 0.02, 700)
			if step % 64 == 0:
				Entity.stir(0.3)


# --- Ambient sounds for the table --------------------------------------------
# Continuous beds are pads and washes twice as long as the gap between them: their
# Hann envelopes overlap into a steady sound. Volumes are quantized, so samples are reused.

## Steady rain, drops ticking on the glass, now and then distant thunder.
func _rain(step: int, at: float, sd: float) -> void:
	if step % 16 == 0:
		var variant := (step / 16) % 3
		_wash(at, sd * 32, 0.03, 2600, variant)
		_wash(at, sd * 32, 0.022, 380, variant)
	if randf() < 0.55:
		var center: float = [3500.0, 4800.0, 6200.0].pick_random()
		var volume: float = [0.02, 0.03, 0.045].pick_random()
		_queue(at + randf() * sd, func() -> AudioStreamWAV: return Synth.noise(0.02, volume, center))
	if step % 64 == 32 and randf() < 0.2:
		_wash(at, 3.0, 0.06, 90, 0)


## The empty branch: neon hum, ventilation, a keyboard far away, sometimes a phone.
func _office(step: int, at: float, sd: float) -> void:
	if step % 16 == 0:
		_pad(at, sd * 32, 120.0, SQUARE, 0.004)
		_pad(at, sd * 32, 60.0, SINE, 0.02)
		_wash(at, sd * 32, 0.014, 700, (step / 16) % 3)
	if step % 16 == 8 and randf() < 0.12:
		var keys := randi_range(6, 14)
		var when := at
		for k in keys:
			_queue(when, func() -> AudioStreamWAV: return Synth.noise(0.012, 0.012, 3200, false))
			when += randf_range(0.08, 0.2)
	if step % 256 == 128 and randf() < 0.5:
		for ring in 2:
			for k in 20:
				var frequency := 440.0 if k % 2 == 0 else 480.0
				_queue(at + ring * 2.0 + k * 0.05, func() -> AudioStreamWAV: return Synth.tone(frequency, 0.05, SINE, 0.008, 0.0, 0.005))


## A low dissonant drone that grows, and a heartbeat at 70 beats per minute.
func _tension(step: int, at: float, sd: float) -> void:
	var strength := snappedf(clampf(at / TENSION_RISE, 0.5, 1.0), 0.1)
	if step % 16 == 0:
		_pad(at, sd * 32, 55.0, TRIANGLE, 0.11 * strength)
		_pad(at, sd * 32, 82.4, SINE, 0.07 * strength)
		_pad(at, sd * 32, 58.3, SINE, 0.035 * strength)
	if step % 4 == 0:
		_queue(at, func() -> AudioStreamWAV: return Synth.tone(60.0, 0.18, SINE, 0.2 * strength, 0.0, 0.01))
		_queue(at + 0.28, func() -> AudioStreamWAV: return Synth.tone(55.0, 0.22, SINE, 0.16 * strength, 0.0, 0.01))
	if step % 32 == 16 and randf() < 0.4:
		_note([84, 85].pick_random(), at, 2.0, SINE, 0.018)


## A siren wailing somewhere in the building, over an electric buzz.
func _alarm(step: int, at: float, sd: float) -> void:
	if step % 16 == 0:
		var half := sd * 8
		_pad(at, half * 1.4, 520.0, TRIANGLE, 0.035, 880.0)
		_pad(at + half, half * 1.4, 880.0, TRIANGLE, 0.035, 520.0)
		_pad(at, sd * 32, 100.0, SQUARE, 0.004)
		_wash(at, sd * 32, 0.012, 300, (step / 16) % 3)
	if step % 64 == 48 and randf() < 0.5:
		for k in 3:
			_queue(at + k * 0.3, func() -> AudioStreamWAV: return Synth.tone(330.0, 0.18, SQUARE, 0.012, 0.0, 0.01))


func _pad(at: float, duration: float, frequency: float, wave: Synth.Wave, volume: float, end_frequency: float = 0.0) -> void:
	_queue(at, func() -> AudioStreamWAV: return Synth.pad(frequency, duration, wave, volume, end_frequency))


func _wash(at: float, duration: float, volume: float, center: float, variant: int) -> void:
	_queue(at, func() -> AudioStreamWAV: return Synth.wash(duration, volume, center, variant))


func _note(midi_note: int, at: float, duration: float, wave: Synth.Wave, volume: float, detune: float = 0.0) -> void:
	var frequency := Synth.midi(midi_note)
	_queue(at, func() -> AudioStreamWAV: return Synth.tone(frequency, duration, wave, volume, detune))


func _noise(at: float, duration: float, volume: float, center: float) -> void:
	_queue(at, func() -> AudioStreamWAV: return Synth.noise(duration, volume, center))


## The note is prepared on a worker thread; data.stream exists beforehand, so the thread doesn't resize the dictionary.
func _queue(at: float, render: Callable) -> void:
	var data := {"stream": null}
	var task := WorkerThreadPool.add_task(func() -> void: data.stream = render.call())
	_events.append({"at": at, "task": task, "data": data})


func _play(stream: AudioStreamWAV) -> void:
	if stream == null:
		return
	var voice: AudioStreamPlayer = null
	for candidate in _voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		voice = _voices[0]
		_voices.push_back(_voices.pop_front())
	voice.stream = stream
	voice.play()


func _drop_events() -> void:
	for event in _events:
		WorkerThreadPool.wait_for_task_completion(event.task)
	_events.clear()


func _exit_tree() -> void:
	_drop_events()


static func _ensure_bus() -> int:
	var index := AudioServer.get_bus_index(BUS)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, "Master")
	AudioServer.add_bus_effect(index, AudioEffectSpectrumAnalyzer.new())
	return index
