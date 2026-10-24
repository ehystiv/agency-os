extends AppContent
## Fascicolo del Manager: livello di accesso, note sulla campagna,
## elenco dei colloqui e ricordi cumulativi dell'Entità.

const BASE_TITLE := "fascicolo_manager.dat"
const PIP_ON := Color("2340b5")
const PIP_OFF := Color("9da2ae")
const SELECTED_TEXT := Color.WHITE

var _selected_numero := 0
var _note_dirty := false

@onready var _level: Label = %Level
@onready var _pips: HBoxContainer = %Pips
@onready var _level_hint: Label = %LevelHint
@onready var _note: TextEdit = %Note
@onready var _note_saved: Label = %NoteSaved
@onready var _rows: VBoxContainer = %Rows
@onready var _empty: Label = %Empty
@onready var _memory_toggle: LinkButton = %MemoryToggle
@onready var _memory_box: Control = %MemoryBox
@onready var _memory: TextEdit = %Memory
@onready var _memory_saved: Label = %MemorySaved
@onready var _reset_box: Control = %ResetBox


func _ready() -> void:
	%SaveNote.pressed.connect(_save_note)
	%NewColloquio.pressed.connect(func() -> void: app_requested.emit(&"linea", {"apri": true}))
	%SaveMemory.pressed.connect(_save_memory)
	_memory_toggle.pressed.connect(_toggle_memory)
	_note.text_changed.connect(_on_note_changed)
	_note.gui_input.connect(_on_editor_input.bind(_save_note))
	_memory.text_changed.connect(func() -> void: _memory_saved.hide())
	_memory.gui_input.connect(_on_editor_input.bind(_save_memory))
	%ResetLink.pressed.connect(func() -> void: _show_reset(true))
	%ResetCancel.pressed.connect(func() -> void: _show_reset(false))
	%ExportFirst.pressed.connect(func() -> void: app_requested.emit(&"taccuino", {"esporta_tutto": true}))
	%ResetGo.pressed.connect(_reset_filiale)
	Campaign.colloqui_changed.connect(_refresh)
	Campaign.colloquio_updated.connect(func(_c: Colloquio) -> void: _refresh_list())
	Campaign.memory_changed.connect(_load_memory)
	_note.text = Campaign.note
	_load_memory()
	_refresh()


## args: {"azzera": true} apre direttamente il protocollo di azzeramento.
func on_opened(args: Dictionary = {}) -> void:
	if args.get("azzera", false):
		_show_reset(true)


func _show_reset(visible_now: bool) -> void:
	_reset_box.visible = visible_now
	if visible_now:
		# Aspetto che il riquadro sia disposto, poi scorro fino in fondo.
		await get_tree().process_frame
		await get_tree().process_frame
		var scroll := %Scroll as ScrollContainer
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## Cancella e riavvia il sistema (con la sequenza di avvio).
func _reset_filiale() -> void:
	Campaign.reset_filiale((%KeepNotes as CheckBox).button_pressed)
	_reset_box.hide()
	command_requested.emit(&"riavvia")


func _refresh() -> void:
	_refresh_level()
	_refresh_list()


func _refresh_level() -> void:
	var level := Campaign.level()
	_level.text = str(level)
	for i in _pips.get_child_count():
		(_pips.get_child(i) as ColorRect).color = PIP_ON if i < level else PIP_OFF
	var missing := Campaign.colloqui_to_next_level()
	if missing == 0:
		_level_hint.text = "Accesso massimo: l'Entità non ha più segreti per te."
	else:
		_level_hint.text = "Cresce a ogni colloquio concluso. Prossimo livello tra %d %s." % [missing, "colloquio" if missing == 1 else "colloqui"]


func _refresh_list() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_empty.visible = Campaign.colloqui.is_empty()
	for i in range(Campaign.colloqui.size() - 1, -1, -1):
		_rows.add_child(_make_row(Campaign.colloqui[i]))


func _make_row(c: Colloquio) -> Button:
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = c.numero == _selected_numero
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 26)
	row.tooltip_text = "Apri il colloquio n. %03d nella linea" % c.numero
	row.pressed.connect(_on_row_pressed.bind(c.numero))

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	var spoken := c.spoken_count()
	var labels: Array[Label] = [
		_row_label(&"ListNum", "#%03d" % c.numero),
		_row_label(&"ListMeta", "%s · %d %s" % [ItalianDate.short(c.aperto), spoken, "messaggio" if spoken == 1 else "messaggi"]),
	]
	labels[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels[1].clip_text = true
	if c.is_open():
		labels.append(_row_label(&"ListTag", "in linea"))
	for label in labels:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if row.button_pressed:
			label.add_theme_color_override("font_color", SELECTED_TEXT)
		content.add_child(label)
	return row


func _row_label(variation: StringName, text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	return label


func _on_row_pressed(numero: int) -> void:
	_selected_numero = numero
	_refresh_list()
	app_requested.emit(&"linea", {"colloquio": numero})


# --- Note e memoria --------------------------------------------------------

func _on_note_changed() -> void:
	_note_saved.hide()
	if not _note_dirty:
		_note_dirty = true
		title_changed.emit(BASE_TITLE + " *")


func _save_note() -> void:
	Campaign.set_note(_note.text)
	_note_dirty = false
	_note_saved.show()
	title_changed.emit(BASE_TITLE)


func _toggle_memory() -> void:
	_memory_box.visible = not _memory_box.visible
	_memory_toggle.text = ("▾ " if _memory_box.visible else "▸ ") + "Ricordi dell'Entità"


func _load_memory() -> void:
	_memory.text = Campaign.memoria
	_memory_saved.hide()


func _save_memory() -> void:
	Campaign.set_memoria(_memory.text)
	_memory_saved.show()


## Ctrl+S (Cmd+S su Mac) salva il campo che ha il focus.
func _on_editor_input(event: InputEvent, save: Callable) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_S and key.is_command_or_control_pressed():
		get_viewport().set_input_as_handled()
		save.call()
