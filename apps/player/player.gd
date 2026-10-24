extends AppContent
## Media player: the company hold music, synthesized live.

const SELECTED_TEXT := Color.WHITE

@onready var _engine: MusicEngine = %Engine
@onready var _now: Label = %NowPlaying
@onready var _time: Label = %Time
@onready var _play: Button = %Play
@onready var _volume: HSlider = %Volume
@onready var _rows: VBoxContainer = %Rows
@onready var _status: Label = %Status


func _ready() -> void:
	%Visualizer.engine = _engine
	%Prev.pressed.connect(_skip.bind(-1))
	%Next.pressed.connect(_skip.bind(1))
	%Stop.pressed.connect(_engine.stop)
	_play.pressed.connect(_on_play_pressed)
	_volume.value = float(Save.get_ui("player_volume", 70))
	_volume.value_changed.connect(func(value: float) -> void:
		_engine.set_volume(value / 100.0)
		Save.set_ui("player_volume", int(value)))
	_engine.state_changed.connect(_refresh)
	Campaign.interviews_changed.connect(_refresh)
	_refresh()


func on_opened(_args: Dictionary = {}) -> void:
	_refresh()


## Closing the Player stops the music (minimizing doesn't).
func on_closed() -> void:
	_engine.stop()


func _process(_delta: float) -> void:
	if _engine.playing or _engine.paused:
		var seconds := int(_engine.elapsed)
		_time.text = "%02d:%02d" % [seconds / 60, seconds % 60]


func _on_play_pressed() -> void:
	if _engine.playing:
		_engine.pause()
	else:
		_start(_engine.track)


func _skip(step: int) -> void:
	var index := posmod(_engine.track + step, MusicEngine.TRACKS.size())
	if _engine.playing:
		_start(index)
	else:
		_engine.stop()
		_engine.track = index
		_refresh()


func _start(index: int) -> void:
	if _engine.is_locked(index):
		_engine.stop()
		_engine.track = index
		_refresh()
		_status.text = "Accesso negato. Livello richiesto: %d." % MusicEngine.TRACKS[index].level
		Sfx.play(&"ding")
		return
	_engine.play(index)


func _refresh() -> void:
	var track: Dictionary = MusicEngine.TRACKS[_engine.track]
	_now.text = str(track.name) if _engine.playing or _engine.paused else "nessuna traccia"
	if not _engine.playing and not _engine.paused:
		_time.text = "00:00"
	_play.text = "❚❚" if _engine.playing else "▶"
	_play.tooltip_text = "Pausa" if _engine.playing else "Riproduci"
	if _engine.playing:
		_status.text = "In riproduzione"
	elif _engine.paused:
		_status.text = "In pausa"
	else:
		_status.text = "Musiche d'attesa aziendali · sintetizzate dal vivo"
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i in MusicEngine.TRACKS.size():
		_rows.add_child(_make_row(i))


func _make_row(index: int) -> Button:
	var track: Dictionary = MusicEngine.TRACKS[index]
	var current := index == _engine.track and (_engine.playing or _engine.paused)
	var locked := _engine.is_locked(index)
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = current
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "%d.  %s%s" % [index + 1, track.name, "   [livello %d]" % track.level if locked else ""]
	if current:
		row.add_theme_color_override("font_pressed_color", SELECTED_TEXT)
		row.add_theme_color_override("font_hover_pressed_color", SELECTED_TEXT)
	if locked:
		row.modulate.a = 0.55
	row.pressed.connect(_start.bind(index))
	return row
