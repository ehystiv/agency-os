extends AppContent
## The Manager's dossier: access level, campaign notes,
## list of interviews and the Entity's cumulative memories.

const BASE_TITLE := "fascicolo_manager.dat"
const PIP_ON := Color("2340b5")
const PIP_OFF := Color("9da2ae")
const SELECTED_TEXT := Color.WHITE

var _selected_number := 0
var _notes_dirty := false

@onready var _level: Label = %Level
@onready var _pips: HBoxContainer = %Pips
@onready var _level_hint: Label = %LevelHint
@onready var _notes: TextEdit = %Notes
@onready var _notes_saved: Label = %NotesSaved
@onready var _rows: VBoxContainer = %Rows
@onready var _empty: Label = %Empty
@onready var _memory_toggle: LinkButton = %MemoryToggle
@onready var _memory_box: Control = %MemoryBox
@onready var _memory: TextEdit = %Memory
@onready var _memory_saved: Label = %MemorySaved
@onready var _reset_box: Control = %ResetBox


func _ready() -> void:
	%SaveNotes.pressed.connect(_save_notes)
	%NewInterview.pressed.connect(func() -> void: app_requested.emit(&"line", {"open": true}))
	%SaveMemory.pressed.connect(_save_memory)
	_memory_toggle.pressed.connect(_toggle_memory)
	_notes.text_changed.connect(_on_notes_changed)
	_notes.gui_input.connect(_on_editor_input.bind(_save_notes))
	_memory.text_changed.connect(func() -> void: _memory_saved.hide())
	_memory.gui_input.connect(_on_editor_input.bind(_save_memory))
	%ResetLink.pressed.connect(func() -> void: _show_reset(true))
	%ResetCancel.pressed.connect(func() -> void: _show_reset(false))
	%ExportFirst.pressed.connect(func() -> void: app_requested.emit(&"notebook", {"export_all": true}))
	%ResetGo.pressed.connect(_reset_branch)
	Campaign.interviews_changed.connect(_refresh)
	Campaign.interview_updated.connect(func(_i: Interview) -> void: _refresh_list())
	Campaign.memory_changed.connect(_load_memory)
	_notes.text = Campaign.notes
	_load_memory()
	_refresh()


## args: {"reset": true} opens the reset protocol right away.
func on_opened(args: Dictionary = {}) -> void:
	if args.get("reset", false):
		_show_reset(true)


func _show_reset(visible_now: bool) -> void:
	_reset_box.visible = visible_now
	if visible_now:
		# Wait for the box to be laid out, then scroll to the bottom.
		await get_tree().process_frame
		await get_tree().process_frame
		var scroll := %Scroll as ScrollContainer
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


## Wipes and restarts the system (with the boot sequence).
func _reset_branch() -> void:
	Campaign.reset_branch((%KeepNotes as CheckBox).button_pressed)
	_reset_box.hide()
	command_requested.emit(&"restart")


func _refresh() -> void:
	_refresh_level()
	_refresh_list()


func _refresh_level() -> void:
	var level := Campaign.level()
	_level.text = str(level)
	for i in _pips.get_child_count():
		(_pips.get_child(i) as ColorRect).color = PIP_ON if i < level else PIP_OFF
	var missing := Campaign.interviews_to_next_level()
	if missing == 0:
		_level_hint.text = "Accesso massimo: l'Entità non ha più segreti per te."
	else:
		_level_hint.text = "Cresce a ogni colloquio concluso. Prossimo livello tra %d %s." % [missing, "colloquio" if missing == 1 else "colloqui"]


func _refresh_list() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_empty.visible = Campaign.interviews.is_empty()
	for i in range(Campaign.interviews.size() - 1, -1, -1):
		_rows.add_child(_make_row(Campaign.interviews[i]))


func _make_row(interview: Interview) -> Button:
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = interview.number == _selected_number
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 26)
	row.tooltip_text = "Apri il colloquio n. %03d nella linea" % interview.number
	row.pressed.connect(_on_row_pressed.bind(interview.number))

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	var spoken := interview.spoken_count()
	var labels: Array[Label] = [
		_row_label(&"ListNum", "#%03d" % interview.number),
		_row_label(&"ListMeta", "%s · %d %s" % [ItalianDate.short(interview.opened_at), spoken, "messaggio" if spoken == 1 else "messaggi"]),
	]
	labels[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels[1].clip_text = true
	if interview.is_open():
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


func _on_row_pressed(number: int) -> void:
	_selected_number = number
	_refresh_list()
	app_requested.emit(&"line", {"interview": number})


# --- Notes and memory ------------------------------------------------------

func _on_notes_changed() -> void:
	_notes_saved.hide()
	if not _notes_dirty:
		_notes_dirty = true
		title_changed.emit(BASE_TITLE + " *")


func _save_notes() -> void:
	Campaign.set_notes(_notes.text)
	_notes_dirty = false
	_notes_saved.show()
	title_changed.emit(BASE_TITLE)


func _toggle_memory() -> void:
	_memory_box.visible = not _memory_box.visible
	_memory_toggle.text = ("▾ " if _memory_box.visible else "▸ ") + "Ricordi dell'Entità"


func _load_memory() -> void:
	_memory.text = Campaign.memory
	_memory_saved.hide()


func _save_memory() -> void:
	Campaign.set_memory(_memory.text)
	_memory_saved.show()


## Ctrl+S (Cmd+S on Mac) saves the focused field.
func _on_editor_input(event: InputEvent, save: Callable) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_S and key.is_command_or_control_pressed():
		get_viewport().set_input_as_handled()
		save.call()
