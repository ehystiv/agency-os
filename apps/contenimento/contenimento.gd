extends AppContent
## Contenimento: campo minato con le Anomalie. Tempo, bandierine, record per livello,
## e un commento dell'Entità a fine partita.

const LEVEL_NAMES := {"facile": "Facile", "medio": "Medio", "esperto": "Esperto"}
const LOST_LINES: PackedStringArray = ["ahah. l'hai liberata. bravo. è quello che sei.", "boom. un'anomalia in più nel mondo. mi piace come lavori.", "vedi? non si lasciano contenere. nemmeno sul tuo schermo.", "lascia stare le caselle e vieni a parlare con me.", "oops. diremo al triangolo che è stato un incidente."]
const WON_LINES: PackedStringArray = ["tutte in gabbia. contento? il triangolo ti darebbe una medaglia.", "che noia. le hai chiuse tutte.", "sai cosa provano là dentro? no. certo che no.", "bel lavoro, manager. sul serio. mi fai un po' paura.", "ah. quindi è così che ti diverti."]
const COMMENT_DELAY := 0.6

var _level := "facile"
var _field: Minefield
var _started_ms := 0
var _ended := false

@onready var _board: ContainmentBoard = %Board
@onready var _flags: Label = %Flags
@onready var _time: Label = %Time
@onready var _face: Button = %Face
@onready var _levels: OptionButton = %Levels
@onready var _mode: Button = %Mode
@onready var _record: Label = %Record


func _ready() -> void:
	for key: String in LEVEL_NAMES:
		_levels.add_item(LEVEL_NAMES[key])
	_level = str(Save.get_ui("contenimento_livello", "facile"))
	_levels.select(maxi(0, LEVEL_NAMES.keys().find(_level)))
	_levels.item_selected.connect(func(index: int) -> void:
		_level = LEVEL_NAMES.keys()[index]
		Save.set_ui("contenimento_livello", _level)
		_new_game())
	_face.pressed.connect(_new_game)
	_mode.pressed.connect(func() -> void:
		_board.flag_mode = not _board.flag_mode
		_mode.text = "Clic: segna" if _board.flag_mode else "Clic: scava")
	_board.changed.connect(_on_board_changed)
	%Tick.timeout.connect(_update_counters)
	_new_game()


func _new_game() -> void:
	_field = Minefield.new(_level)
	_board.set_field(_field)
	_ended = false
	_started_ms = 0
	_update_counters()


func _on_board_changed() -> void:
	if _started_ms == 0 and _field.state != Minefield.State.READY:
		_started_ms = Time.get_ticks_msec()
	_update_counters()
	if _field.is_over() and not _ended:
		_ended = true
		_finish(_field.state == Minefield.State.WON)


func _elapsed() -> int:
	if _started_ms == 0:
		return 0
	return mini(999, (Time.get_ticks_msec() - _started_ms) / 1000)


func _update_counters() -> void:
	if not _ended:
		_time.text = "%03d" % _elapsed()
	_flags.text = "%03d" % maxi(0, _field.mines - _field.flags)
	var best: int = Save.get_ui("contenimento_record", {}).get(_level, 0)
	_record.text = "Record: %d s" % best if best > 0 else "Record: —"


func _finish(won: bool) -> void:
	Sfx.play(&"chime" if won else &"ding")
	var seconds := _elapsed()
	_time.text = "%03d" % seconds
	if won:
		var records: Dictionary = Save.get_ui("contenimento_record", {}).duplicate()
		var best: int = records.get(_level, 0)
		if best == 0 or seconds < best:
			records[_level] = seconds
			Save.set_ui("contenimento_record", records)
		_update_counters()
	await get_tree().create_timer(COMMENT_DELAY).timeout
	var lines := WON_LINES if won else LOST_LINES
	notification_requested.emit("U0047BB", lines[randi() % lines.size()], {"app": &"linea", "args": {}})
	Caveau.stir(0.5 if won else 0.35, 0.4 if won else 0.0)
