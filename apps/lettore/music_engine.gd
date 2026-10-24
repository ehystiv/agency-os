class_name MusicEngine
extends Node
## Musiche d'attesa aziendali, sintetizzate dal vivo come nel prototipo.
## Un sequencer a sedicesimi prepara le note con un secondo di anticipo
## (in thread di lavoro) e le suona su un gruppo di voci del bus "Musica".

signal state_changed

const BUS := "Musica"
## Le note di questi brani hanno volumi molto bassi (come nel prototipo): il bus le alza.
const BUS_BOOST := 4.0
const LOOKAHEAD := 1.0
## Una nota pronta in ritardo si suona comunque, entro questo margine.
const LATE_TOLERANCE := 1.5
const VOICES := 20
const SQUARE := Synth.Wave.SQUARE
const TRIANGLE := Synth.Wave.TRIANGLE
const SINE := Synth.Wave.SINE
const TRACKS: Array[Dictionary] = [
	{"nome": "Benvenuto in Filiale", "bpm": 96, "livello": 0},
	{"nome": "Attesa in linea", "bpm": 72, "livello": 0},
	{"nome": "Corridoio B", "bpm": 52, "livello": 0},
	{"nome": "███████", "bpm": 44, "livello": 3},
]
const CHORDS_1: Array = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]
const CHORDS_WAIT: Array = [[62, 66, 69, 73], [59, 62, 66, 69], [55, 59, 62, 66], [57, 61, 64, 67]]
const CHORDS_CORRIDOR: Array = [[45, 52, 57, 60], [43, 50, 55, 58]]

var track := 0
var playing := false
var paused := false
## Secondi di brano trascorsi (si fermano in pausa).
var elapsed := 0.0

var _step := 0
var _next_time := 0.0
## {at: secondi di brano, task: id del lavoro, data: {"stream": AudioStreamWAV}}
var _events: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer] = []
var _analyzer: AudioEffectSpectrumAnalyzerInstance


func _ready() -> void:
	# Il salvaschermo non parte mentre la musica suona.
	add_to_group(&"musica")
	var bus := _ensure_bus()
	_analyzer = AudioServer.get_bus_effect_instance(bus, 0) as AudioEffectSpectrumAnalyzerInstance
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS
		add_child(voice)
		_voices.append(voice)
	set_volume(float(Save.get_ui("lettore_volume", 70)) / 100.0)
	set_process(false)


func is_locked(index: int) -> bool:
	return int(TRACKS[index].livello) > Campaign.level()


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


## Intensità per il visualizzatore: count bande tra 60 Hz e 4 kHz, da 0 a 1.
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


# --- Brani (traduzione delle funzioni del prototipo) -----------------------

func _run_step(step: int, at: float, sd: float) -> void:
	match track:
		0:
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
		1:
			# Se la si lascia andare, l'attesa si stona piano piano.
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
		2:
			var chord: Array = CHORDS_CORRIDOR[(step / 64) % 2]
			var s := step % 64
			if s == 0:
				for m: int in chord:
					_note(m, at, sd * 62, TRIANGLE, 0.03)
			if s % 16 == 8 and randf() < 0.5:
				_note([81, 84, 88, 91].pick_random(), at, sd * 10, SINE, 0.018)
			if s % 32 == 0:
				_noise(at, sd * 20, 0.008, 420)
		3:
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
				Caveau.stir(0.3)


func _note(midi_note: int, at: float, duration: float, wave: Synth.Wave, volume: float, detune: float = 0.0) -> void:
	var frequency := Synth.midi(midi_note)
	_queue(at, func() -> AudioStreamWAV: return Synth.tone(frequency, duration, wave, volume, detune))


func _noise(at: float, duration: float, volume: float, center: float) -> void:
	_queue(at, func() -> AudioStreamWAV: return Synth.noise(duration, volume, center))


## La nota si prepara in un thread di lavoro; data.stream c'è già prima, così il thread non ridimensiona il dizionario.
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
