extends Node
## State of subject U0047BB in the vault, shared between apps:
## the Line and the glitches stir it, the webcam shows it. It calms down by itself.

signal signal_changed(available: bool)
## A glitch just started: the desktop and the CRT react to their effects.
signal glitch_started(glitch_name: String)

## Minimum agitation: at rest and while speaking.
const CALM := 0.06
const SPEAKING_CALM := 0.25
## How much of each value is left after a second (from the prototype: 0.985 / 0.97 at 15 fps).
const AGITATION_DECAY := 0.797
const TINT_DECAY := 0.633
const SHRINK_DECAY := 0.797

## 0..1: deformation speed, jolts, eyes blinking more often.
var agitation: float = CALM
## 0..1: how much the subject turns red.
var tint: float = 0.0
## 0..1: how far it withdraws to the back of the cage.
var shrink: float = 0.0
var speaking: bool = false
var signal_available: bool = true

var _wide_until_ms := 0
var _signal_token := 0


func _process(delta: float) -> void:
	var floor_value := SPEAKING_CALM if speaking else CALM
	agitation = maxf(floor_value, agitation * pow(AGITATION_DECAY, delta))
	tint *= pow(TINT_DECAY, delta)
	shrink *= pow(SHRINK_DECAY, delta)
	# Calm again: nothing to do until the next stir() or set_speaking().
	if agitation <= floor_value and tint < 0.005 and shrink < 0.005:
		tint = 0.0
		shrink = 0.0
		set_process(false)


## Stirs the subject: each value rises to the given one, if higher.
func stir(new_agitation: float, new_tint: float = 0.0, new_shrink: float = 0.0) -> void:
	agitation = maxf(agitation, clampf(new_agitation, 0.0, 1.0))
	tint = maxf(tint, clampf(new_tint, 0.0, 1.0))
	shrink = maxf(shrink, clampf(new_shrink, 0.0, 1.0))
	set_process(true)


## The subject's reaction to a glitch (table in data/glitch.json), then tells the listeners.
func glitch(glitch_name: String) -> void:
	var info: Dictionary = Campaign.glitch_table().get(glitch_name, {})
	var reaction: Array = info.get("webcam", [])
	if reaction.size() == 3:
		stir(float(reaction[0]), float(reaction[1]), float(reaction[2]))
	if glitch_name == "static":
		lose_signal(1.3)
	elif glitch_name == "eyes":
		widen_eyes(3.5)
	glitch_started.emit(glitch_name)


func set_speaking(value: bool) -> void:
	speaking = value
	set_process(true)


## The webcam loses the signal; with seconds > 0 it comes back by itself.
func lose_signal(seconds: float = 0.0) -> void:
	_signal_token += 1
	_set_signal(false)
	if seconds > 0.0:
		var token := _signal_token
		await get_tree().create_timer(seconds).timeout
		if token == _signal_token:
			_set_signal(true)


func restore_signal() -> void:
	_signal_token += 1
	_set_signal(true)


func widen_eyes(seconds: float) -> void:
	_wide_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func eyes_wide() -> bool:
	return Time.get_ticks_msec() < _wide_until_ms


func is_hot() -> bool:
	return agitation > 0.55 or tint > 0.4


## The camera caption (shown on screen).
func status_text() -> String:
	if is_hot():
		return "SOGGETTO AGITATO"
	if shrink > 0.3:
		return "SOGGETTO IN RITIRATA"
	if speaking:
		return "ATTIVITÀ ANOMALA"
	return "SOGGETTO CONTENUTO"


func _set_signal(value: bool) -> void:
	if signal_available == value:
		return
	signal_available = value
	signal_changed.emit(value)
