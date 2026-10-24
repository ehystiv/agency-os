extends AppContent
## Vault webcam: the 3D scene at 160×120, redrawn at 15 fps and scaled up pixelated,
## with the camera overlays. Reads the subject's state from Entity.

const FPS := 15.0
const JOLT_PIXELS := 6.0
const JOLT_SECONDS := 0.09
const REC_BLINK_SECONDS := 0.6
## The Entity's speed with reduced motion.
const REDUCED_SPEED := 0.4

var _time := 0.0
var _wave_time := 0.0
var _since_frame := 0.0
var _jolt_left := 0.0
var _rec_clock := 0.0

@onready var _viewport: SubViewport = %FeedViewport
@onready var _feed: TextureRect = %Feed
@onready var _cage: CageScene = %FeedViewport/Cage
@onready var _rec_dot: Control = %RecDot
@onready var _timestamp: Label = %Timestamp
@onready var _status: Label = %Status
@onready var _no_signal: Control = %NoSignal


func _ready() -> void:
	_feed.texture = _viewport.get_texture()
	Entity.signal_changed.connect(_on_signal_changed)
	_on_signal_changed(Entity.signal_available)
	_render_frame()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var reduced := bool(Save.get_ui("reduced_motion", false))
	var speed := REDUCED_SPEED if reduced else 1.0
	_time += delta * speed
	_wave_time += delta * speed * (1.0 + Entity.agitation * 2.2)
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
	_cage.step(_time, _wave_time)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var now := Time.get_datetime_dict_from_system()
	_timestamp.text = "%02d/%02d/%02d %02d:%02d:%02d" % [now.day, now.month, now.year % 100, now.hour, now.minute, now.second]
	_status.text = Entity.status_text()
	_status.theme_type_variation = &"CamHot" if Entity.is_hot() else &"CamOverlay"
	# Signal jolt, more frequent when the subject is agitated.
	if _jolt_left <= 0.0 and not bool(Save.get_ui("reduced_motion", false)) and randf() < 0.004 + Entity.agitation * 0.02:
		_jolt_left = JOLT_SECONDS
		_feed.position.x = JOLT_PIXELS


func _on_signal_changed(available: bool) -> void:
	_no_signal.visible = not available
