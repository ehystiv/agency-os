extends Node
## Stato del soggetto U0047BB nel Caveau, condiviso tra le app:
## la Linea e i glitch lo agitano, la webcam lo mostra. Torna da solo alla calma.

signal signal_changed(available: bool)
## Un glitch è appena partito: la scrivania e il CRT reagiscono ai loro effetti.
signal glitch_started(glitch_name: String)

## Valori minimi di agitazione: a riposo e mentre parla.
const CALM := 0.06
const SPEAKING_CALM := 0.25
## Quanto resta di ogni valore dopo un secondo (dal prototipo: 0,985 / 0,97 a 15 fps).
const AGITATION_DECAY := 0.797
const TINT_DECAY := 0.633
const SHRINK_DECAY := 0.797

## 0..1: velocità della deformazione, scossoni, occhi che sbattono più spesso.
var agitation: float = CALM
## 0..1: quanto il soggetto vira al rosso.
var tint: float = 0.0
## 0..1: quanto si ritira verso il fondo della gabbia.
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


## Agita il soggetto: ogni valore sale fino a quello indicato, se è più alto.
func stir(new_agitation: float, new_tint: float = 0.0, new_shrink: float = 0.0) -> void:
	agitation = maxf(agitation, clampf(new_agitation, 0.0, 1.0))
	tint = maxf(tint, clampf(new_tint, 0.0, 1.0))
	shrink = maxf(shrink, clampf(new_shrink, 0.0, 1.0))


## Reazione del soggetto a un glitch (tabella in data/glitch.json) e avviso a chi ascolta.
func glitch(glitch_name: String) -> void:
	var info: Dictionary = Campaign.glitch_table().get(glitch_name, {})
	var reaction: Array = info.get("webcam", [])
	if reaction.size() == 3:
		stir(float(reaction[0]), float(reaction[1]), float(reaction[2]))
	if glitch_name == "statico":
		lose_signal(1.3)
	elif glitch_name == "occhi":
		widen_eyes(3.5)
	glitch_started.emit(glitch_name)


func set_speaking(value: bool) -> void:
	speaking = value


## La webcam perde il segnale; con seconds > 0 torna da sola.
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


## Didascalia della telecamera.
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
