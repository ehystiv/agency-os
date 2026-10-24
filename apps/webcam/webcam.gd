extends AppContent
## Webcam del Caveau: la scena 3D a 160×120, ridisegnata a 15 fps e ingrandita a pixel,
## con le sovrimpressioni della telecamera. Legge lo stato del soggetto da Caveau.

const FPS := 15.0
const JOLT_PIXELS := 6.0
const JOLT_SECONDS := 0.09
const REC_BLINK_SECONDS := 0.6
## Velocità dell'Entità con le animazioni ridotte.
const REDUCED_SPEED := 0.4

var _time := 0.0
var _wave_time := 0.0
var _since_frame := 0.0
var _jolt_left := 0.0
var _rec_clock := 0.0

@onready var _viewport: SubViewport = %FeedViewport
@onready var _feed: TextureRect = %Feed
@onready var _caveau: CaveauScene = %FeedViewport/Caveau
@onready var _rec_dot: Control = %RecDot
@onready var _timestamp: Label = %Timestamp
@onready var _status: Label = %Status
@onready var _no_signal: Control = %NoSignal


func _ready() -> void:
	_feed.texture = _viewport.get_texture()
	Caveau.signal_changed.connect(_on_signal_changed)
	_on_signal_changed(Caveau.signal_available)
	_render_frame()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var reduced := bool(Save.get_ui("animazioni_ridotte", false))
	var speed := REDUCED_SPEED if reduced else 1.0
	_time += delta * speed
	_wave_time += delta * speed * (1.0 + Caveau.agitation * 2.2)
	_rec_clock += delta
	_rec_dot.visible = fmod(_rec_clock, REC_BLINK_SECONDS * 2.0) < REC_BLINK_SECONDS
	if _jolt_left > 0.0:
		_jolt_left -= delta
		if _jolt_left <= 0.0:
			_feed.position.x = 0.0
	_since_frame += delta
	if _since_frame >= 1.0 / FPS:
		_since_frame = fmod(_since_frame, 1.0 / FPS)
		_render_frame()


func _render_frame() -> void:
	_caveau.step(_time, _wave_time)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var now := Time.get_datetime_dict_from_system()
	_timestamp.text = "%02d/%02d/%02d %02d:%02d:%02d" % [now.day, now.month, now.year % 100, now.hour, now.minute, now.second]
	_status.text = Caveau.status_text()
	_status.theme_type_variation = &"CamHot" if Caveau.is_hot() else &"CamOverlay"
	# Scossone del segnale, più frequente se il soggetto è agitato.
	if _jolt_left <= 0.0 and not bool(Save.get_ui("animazioni_ridotte", false)) and randf() < 0.004 + Caveau.agitation * 0.02:
		_jolt_left = JOLT_SECONDS
		_feed.position.x = JOLT_PIXELS


func _on_signal_changed(available: bool) -> void:
	_no_signal.visible = not available
