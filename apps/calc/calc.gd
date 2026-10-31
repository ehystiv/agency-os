extends AppContent
## AgencyOS calculator: rolls 6d4 in the 3D tray and applies the roll rules;
## keeps the branch's Chaos pool.

const ENTITY_LCD: PackedStringArray = ["liberami", "3 3 3 ah", "ciao :)", "non è un caso", "ti vedo"]
const ENTITY_LCD_CHANCE := 0.1
const ENTITY_LCD_SECONDS := 1.3
const IDLE_TEXT := "Premi TIRA per lanciare 6d4. Ogni 3 è un successo, ogni altro risultato aggiunge 1 Caos."

var _reset_armed := false

@onready var _viewport: SubViewport = %TrayViewport
@onready var _tray: DiceTray = %TrayViewport/DiceTray
@onready var _feed: TextureRect = %Feed
@onready var _lcd: Label = %Lcd
@onready var _result: RichTextLabel = %Result
@onready var _roll: Button = %Roll
@onready var _chaos: Label = %Chaos
@onready var _reset: Button = %Reset


func _ready() -> void:
	_feed.texture = _viewport.get_texture()
	_roll.pressed.connect(_on_roll_pressed)
	%Minus.pressed.connect(func() -> void: _change_chaos(-1))
	%Plus.pressed.connect(func() -> void: _change_chaos(1))
	_reset.pressed.connect(_on_reset_pressed)
	Campaign.chaos_changed.connect(func(_c: int) -> void: _refresh_chaos())
	_result.text = IDLE_TEXT
	_refresh_chaos()
	# Continuous redraw only while rolling; when still one frame is enough.
	_tray.rolling_changed.connect(_set_live)
	_tray.impact.connect(Sfx.dice_hit)
	_set_live(true)
	await get_tree().create_timer(0.6).timeout
	_set_live(false)


func _unhandled_key_input(event: InputEvent) -> void:
	if window_active and is_visible_in_tree() and event.is_action_pressed("ui_select"):
		get_viewport().set_input_as_handled()
		_on_roll_pressed()


func _on_roll_pressed() -> void:
	if _tray.rolling:
		return
	_reset_armed = false
	_refresh_chaos()
	_roll.disabled = true
	_lcd.text = "· · · · · ·"
	_result.text = "Lancio in corso…"
	var values := await _tray.roll()
	var outcome := DiceRules.evaluate(values)
	_tray.highlight(DiceRules.TARGET)
	_set_live(false)
	Campaign.add_chaos(outcome.chaos)
	var line := DiceRules.describe(outcome)
	var word := DiceRules.outcome_word(outcome)
	var triscendence: bool = outcome.outcome == DiceRules.TRISCENDENCE
	var color := "#7a1418" if triscendence else "#14161c"
	_result.text = line.replace(word, "[b][color=%s]%s[/color][/b]" % [color, word])
	if triscendence:
		Sfx.play(&"chime")
		Entity.stir(0.5)
	var digits: PackedStringArray = []
	for value in values:
		digits.append(str(value))
	var real := " ".join(digits)
	if Campaign.level() >= 2 and randf() < ENTITY_LCD_CHANCE:
		# The Entity takes over the display for a moment.
		_lcd.text = ENTITY_LCD[randi() % ENTITY_LCD.size()]
		Entity.stir(0.35)
		await get_tree().create_timer(ENTITY_LCD_SECONDS).timeout
	_lcd.text = real
	_roll.disabled = false


func _change_chaos(amount: int) -> void:
	_reset_armed = false
	Campaign.add_chaos(amount)


func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		_refresh_chaos()
		return
	_reset_armed = false
	Campaign.set_chaos(0)


func _refresh_chaos() -> void:
	_chaos.text = "%02d" % Campaign.chaos
	_reset.text = "Conferma" if _reset_armed else "Azzera"


func _set_live(live: bool) -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if live else SubViewport.UPDATE_ONCE
