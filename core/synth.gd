class_name Synth
extends RefCounted
## Small synthesizer: renders notes and noise bursts as audio samples,
## with the prototype's envelopes (Web Audio). Each sound is computed once
## and then reused from the cache. Used by the Player and by the system sounds.
## Safe to call from worker threads: the cache is protected by a mutex.

enum Wave { SINE, SQUARE, TRIANGLE, SAWTOOTH }

const MIX_RATE := 22050
## Finer details than this can't be heard: rounding lets samples be reused.
const DETUNE_STEP := 10.0
const DURATION_STEP := 0.01

static var _cache: Dictionary = {}
static var _lock := Mutex.new()


## Frequency of a MIDI note (69 = A 440 Hz).
static func midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Note: short linear attack, then exponential decay down to silence.
## attack < 0 = like the prototype's music (up to 40 ms); end_frequency > 0 = exponential glide.
static func tone(frequency: float, duration: float, wave: Wave, volume: float, detune_cents: float = 0.0, attack: float = -1.0, end_frequency: float = 0.0) -> AudioStreamWAV:
	duration = snappedf(duration, DURATION_STEP)
	detune_cents = snappedf(detune_cents, DETUNE_STEP)
	var key := "t%.2f/%.2f/%d/%.4f/%.0f/%.3f/%.1f" % [frequency, duration, wave, volume, detune_cents, attack, end_frequency]
	var cached := _cached(key)
	if cached != null:
		return cached
	var freq := frequency * pow(2.0, detune_cents / 1200.0)
	var frames := int((duration + 0.05) * MIX_RATE)
	if attack < 0.0:
		attack = minf(0.04, duration * 0.3)
	var attack_frames := maxi(1, int(attack * MIX_RATE))
	var decay_frames := maxi(1, int((duration - attack) * MIX_RATE))
	var decay := pow(0.0001 / maxf(volume, 0.0001), 1.0 / decay_frames)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	var step := freq / MIX_RATE
	var glide := 1.0
	if end_frequency > 0.0:
		glide = pow(end_frequency / frequency, 1.0 / maxi(1, int(duration * MIX_RATE)))
	var level := 0.0
	for i in frames:
		if i < attack_frames:
			level = volume * float(i) / attack_frames
		elif i < attack_frames + decay_frames:
			level *= decay
		else:
			level = 0.0
		data.encode_s16(i * 2, int(clampf(_wave(wave, phase) * level, -1.0, 1.0) * 32767.0))
		phase = fmod(phase + step, 1.0)
		step *= glide
	return _store(key, _stream(data))


## Noise burst filtered around center Hz: rises until 40% and then fades out
## (shaped = false: constant volume, like the noise hits of the system sounds).
static func noise(duration: float, volume: float, center: float, shaped: bool = true) -> AudioStreamWAV:
	duration = snappedf(duration, DURATION_STEP)
	var key := "n%.2f/%.4f/%.0f/%s" % [duration, volume, center, shaped]
	var cached := _cached(key)
	if cached != null:
		return cached
	var frames := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	# Two-pole band-pass (resonator) to give the noise a colour.
	var r := 0.97
	var theta := TAU * clampf(center, 20.0, MIX_RATE * 0.45) / MIX_RATE
	var a1 := 2.0 * r * cos(theta)
	var a2 := -r * r
	var gain := (1.0 - r) * 4.0
	var y1 := 0.0
	var y2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center * 1000.0 + duration * 10.0)
	for i in frames:
		var t := float(i) / frames
		var envelope := (t / 0.4 if t < 0.4 else (1.0 - t) / 0.6) if shaped else 1.0
		var y := rng.randf_range(-1.0, 1.0) * gain + a1 * y1 + a2 * y2
		y2 = y1
		y1 = y
		data.encode_s16(i * 2, int(clampf(y * envelope * volume * 4.0, -1.0, 1.0) * 32767.0))
	return _store(key, _stream(data))


## A die hitting the tray: a sharp click (resin ringing at a few high frequencies, gone in
## a few milliseconds) over a short low thud from the table. Each variant has slightly
## different resonances, like different dice landing on different edges. Peak about 0.25.
static func knock(variant: int) -> AudioStreamWAV:
	var key := "k%d" % variant
	var cached := _cached(key)
	if cached != null:
		return cached
	const RATE := 44100
	const SECONDS := 0.12
	var rng := RandomNumberGenerator.new()
	rng.seed = 4047 + variant * 7919
	# [frequency, amplitude, decay time]: the die's own ringing, then the table.
	var modes: Array[Vector3] = []
	for mode: Vector3 in [Vector3(2300, 0.5, 0.030), Vector3(3800, 0.36, 0.022), Vector3(5600, 0.24, 0.016), Vector3(7900, 0.14, 0.010)]:
		modes.append(Vector3(mode.x * rng.randf_range(0.88, 1.12), mode.y * rng.randf_range(0.7, 1.0), mode.z))
	modes.append(Vector3(rng.randf_range(170.0, 260.0), rng.randf_range(0.25, 0.4), 0.028))
	var phases: Array[float] = []
	for mode in modes:
		phases.append(rng.randf() * TAU)
	var frames := int(SECONDS * RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var peak := 0.0
	var previous_noise := 0.0
	for i in frames:
		var t := float(i) / RATE
		var value := 0.0
		for m in modes.size():
			var mode := modes[m]
			value += sin(TAU * mode.x * t + phases[m]) * mode.y * exp(-t / mode.z)
		# The contact itself: 2 ms of bright noise (differenced = high-passed).
		var noise_value := rng.randf_range(-1.0, 1.0)
		value += (noise_value - previous_noise) * 0.35 * exp(-t / 0.0015)
		previous_noise = noise_value
		# 0.3 ms attack, so the start doesn't pop.
		value *= minf(1.0, t / 0.0003)
		samples[i] = value
		peak = maxf(peak, absf(value))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.25, -1.0, 1.0) * 32767.0))
	var stream := _stream(data)
	stream.mix_rate = RATE
	return _store(key, stream)


## Sums several sounds into one sample: parts = [[delay in seconds, AudioStreamWAV], …].
static func mix(parts: Array) -> AudioStreamWAV:
	var length := 0
	for part: Array in parts:
		length = maxi(length, int(float(part[0]) * MIX_RATE) + (part[1] as AudioStreamWAV).data.size() / 2)
	var sum := PackedFloat32Array()
	sum.resize(length)
	for part: Array in parts:
		var offset := int(float(part[0]) * MIX_RATE)
		var data: PackedByteArray = (part[1] as AudioStreamWAV).data
		for i in data.size() / 2:
			sum[offset + i] += data.decode_s16(i * 2) / 32767.0
	var out := PackedByteArray()
	out.resize(length * 2)
	for i in length:
		out.encode_s16(i * 2, int(clampf(sum[i], -1.0, 1.0) * 32767.0))
	return _stream(out)


## Continuous search hum: 55 Hz sawtooth, filtered and wobbling, looped.
static func hum() -> AudioStreamWAV:
	var cached := _cached("hum")
	if cached != null:
		return cached
	var seconds := 2.0
	var frames := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	var smooth := 0.0
	var cutoff := 1.0 - exp(-TAU * 320.0 / MIX_RATE)
	for i in frames:
		var t := float(i) / MIX_RATE
		smooth += (_wave(Wave.SAWTOOTH, phase) - smooth) * cutoff
		var level := 0.02 + 0.012 * sin(TAU * 5.5 * t)
		data.encode_s16(i * 2, int(clampf(smooth * level * 4.0, -1.0, 1.0) * 32767.0))
		phase = fmod(phase + 55.0 / MIX_RATE, 1.0)
	var stream := _stream(data)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = frames
	return _store("hum", stream)


static func _cached(key: String) -> AudioStreamWAV:
	_lock.lock()
	var stream: AudioStreamWAV = _cache.get(key)
	_lock.unlock()
	return stream


static func _store(key: String, stream: AudioStreamWAV) -> AudioStreamWAV:
	_lock.lock()
	_cache[key] = stream
	_lock.unlock()
	return stream


static func _wave(wave: Wave, phase: float) -> float:
	match wave:
		Wave.SQUARE:
			return 1.0 if phase < 0.5 else -1.0
		Wave.TRIANGLE:
			return 4.0 * absf(phase - 0.5) - 1.0
		Wave.SAWTOOTH:
			return 2.0 * phase - 1.0
	return sin(phase * TAU)


static func _stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
