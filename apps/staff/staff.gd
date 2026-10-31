extends AppContent
## Personale: the team's Agents, one sheet each (name, player, ARC, commendations,
## demerits, notes). Saved automatically; the Agents the Entity knows go in its prompt.

const SAVE_DELAY := 0.8
const SELECTED_TEXT := Color.WHITE
## The counters of a sheet: key in the agent, label on screen.
const COUNTERS := {"commendations": "Encomi", "demerits": "Richiami"}

var _selected_id := ""
## The agent the form shows: when it changes, every field is rewritten, even the focused one.
var _shown_id := ""
var _dirty := false
var _delete_armed := false
var _loading := false
var _counter_labels: Dictionary[String, Label] = {}

@onready var _rows: VBoxContainer = %Rows
@onready var _empty_list: Label = %EmptyList
@onready var _form: Control = %Form
@onready var _empty: Control = %Empty
@onready var _name: LineEdit = %AgentName
@onready var _notes: TextEdit = %Notes
@onready var _known: CheckBox = %Known
@onready var _status: Label = %Status
@onready var _delete: LinkButton = %Delete
@onready var _fields: Dictionary[String, LineEdit] = {"player": %Player, "anomaly": %Anomaly, "reality": %Reality, "competency": %Competency}
@onready var _save_timer := Timer.new()


func _ready() -> void:
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_flush)
	add_child(_save_timer)
	for key: String in COUNTERS:
		_build_counter(key, COUNTERS[key])
	%NewAgent.pressed.connect(_new_agent)
	%NewAgentEmpty.pressed.connect(_new_agent)
	_delete.pressed.connect(_on_delete_pressed)
	_name.text_changed.connect(func(text: String) -> void: _edit("name", text))
	for key: String in _fields:
		_fields[key].text_changed.connect(func(text: String) -> void: _edit(key, text))
	_notes.text_changed.connect(func() -> void: _edit("notes", _notes.text))
	_known.toggled.connect(func(on: bool) -> void:
		_edit("known", on)
		_flush())
	Campaign.agents_changed.connect(_refresh)
	_refresh()


func on_closed() -> void:
	_flush()


## Quitting within SAVE_DELAY of the last keystroke: save without touching the UI.
func _exit_tree() -> void:
	if _dirty:
		_dirty = false
		var agent := _agent()
		if not agent.is_empty():
			Campaign.save_agent(agent, true)


func _agent() -> Dictionary:
	return Campaign.find_agent(_selected_id) if _selected_id != "" else {}


func _refresh() -> void:
	if _agent().is_empty():
		_selected_id = str(Campaign.agents[0].id) if not Campaign.agents.is_empty() else ""
	_refresh_list()
	_refresh_form()


func _refresh_list() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_empty_list.visible = Campaign.agents.is_empty()
	for agent in Campaign.agents:
		_rows.add_child(_make_row(agent))


func _make_row(agent: Dictionary) -> Button:
	var selected: bool = agent.id == _selected_id
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = selected
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 42)
	row.pressed.connect(_select.bind(str(agent.id)))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)
	var title := _row_label(str(agent.name) if str(agent.name) != "" else tr("Agente senza nome"), selected)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var meta := str(agent.anomaly) if str(agent.anomaly) != "" else str(agent.player)
	var counts := tr("E%d · R%d") % [int(agent.commendations), int(agent.demerits)]
	var line := _row_label(counts + (" · " + meta if meta != "" else ""), selected)
	line.clip_text = true
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.modulate.a = 0.75
	box.add_child(line)
	return row


func _row_label(text: String, selected: bool) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ListMeta"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if selected:
		label.add_theme_color_override("font_color", SELECTED_TEXT)
	return label


func _refresh_form() -> void:
	var agent := _agent()
	var has_agent := not agent.is_empty()
	_form.visible = has_agent
	_empty.visible = not has_agent
	_delete.visible = has_agent
	_delete.text = tr("Conferma: elimina l'Agente") if _delete_armed else tr("Elimina l'Agente")
	if not has_agent:
		_status.text = ""
		_shown_id = ""
		return
	_loading = true
	var other := _shown_id != _selected_id
	_shown_id = _selected_id
	if other or not _name.has_focus():
		_name.text = str(agent.name)
	for key: String in _fields:
		if other or not _fields[key].has_focus():
			_fields[key].text = str(agent.get(key, ""))
	if other or not _notes.has_focus():
		_notes.text = str(agent.notes)
	_known.set_pressed_no_signal(bool(agent.get("known", true)))
	for key: String in COUNTERS:
		_counter_labels[key].text = "%02d" % int(agent.get(key, 0))
	_loading = false


## [label] [-] 00 [+], like the Chaos pool of the Calcolatrice.
func _build_counter(key: String, label_text: String) -> void:
	var counters: HBoxContainer = %Counters
	if counters.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size.x = 14
		counters.add_child(gap)
	var label := Label.new()
	label.theme_type_variation = &"StatusLabel"
	label.text = label_text
	counters.add_child(label)
	counters.add_child(_step_button("−", key, -1))
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"LcdPanel"
	panel.custom_minimum_size.x = 40
	counters.add_child(panel)
	var value := Label.new()
	value.theme_type_variation = &"LcdSmall"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(value)
	_counter_labels[key] = value
	counters.add_child(_step_button("+", key, 1))


func _step_button(text: String, key: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(26, 0)
	button.pressed.connect(func() -> void:
		var agent := _agent()
		if agent.is_empty():
			return
		agent[key] = maxi(0, int(agent.get(key, 0)) + step)
		_counter_labels[key].text = "%02d" % int(agent[key])
		_dirty = true
		_flush())
	return button


func _select(id: String) -> void:
	_flush()
	_selected_id = id
	_delete_armed = false
	_refresh()


func _new_agent() -> void:
	_flush()
	_delete_armed = false
	_selected_id = str(Campaign.new_agent().id)
	_refresh()
	_name.grab_focus.call_deferred()


# --- Edits and saving ------------------------------------------------------

func _edit(key: String, value: Variant) -> void:
	var agent := _agent()
	if _loading or agent.is_empty():
		return
	agent[key] = value
	_dirty = true
	_status.text = tr("Modifiche non salvate…")
	_save_timer.start()


func _flush() -> void:
	_save_timer.stop()
	if not _dirty:
		return
	_dirty = false
	var agent := _agent()
	if agent.is_empty():
		return
	Campaign.save_agent(agent, true)
	_status.text = tr("Salvato alle %s") % Time.get_time_string_from_system().left(5)
	_refresh_list()


func _on_delete_pressed() -> void:
	var agent := _agent()
	if agent.is_empty():
		return
	if not _delete_armed:
		_delete_armed = true
		_refresh_form()
		return
	_delete_armed = false
	_save_timer.stop()
	_dirty = false
	_selected_id = ""
	Campaign.delete_agent(agent)


## The sheet as the players see it on the TV: no Manager's notes.
func _present() -> void:
	_flush()
	var agent := _agent()
	if agent.is_empty():
		return
	var lines: PackedStringArray = []
	for key: String in Campaign.AGENT_FIELDS:
		var value := str(agent.get(key, "")).strip_edges()
		lines.append("%s: %s" % [tr(Campaign.AGENT_FIELDS[key]), value if value != "" else "—"])
	lines.append("")
	lines.append("%s: %d · %s: %d" % [tr(COUNTERS.commendations), int(agent.commendations), tr(COUNTERS.demerits), int(agent.demerits)])
	present_requested.emit({
		"kind": "text",
		"caption": tr("Personale · scheda dell'Agente"),
		"heading": str(agent.name) if str(agent.name) != "" else tr("Agente senza nome"),
		"meta": str(agent.player),
		"body": "\n".join(lines),
	})


# --- Menus -------------------------------------------------------------------

func menu(title: String) -> Array[Dictionary]:
	var has_agent := not _agent().is_empty()
	match title:
		"File":
			return [{"label": "Nuovo Agente", "action": "new", "accel": KEY_MASK_CMD_OR_CTRL | KEY_N}]
		"Agente":
			return [
				{"label": "Mostra ai giocatori", "action": "present", "accel": KEY_MASK_CMD_OR_CTRL | KEY_MASK_SHIFT | KEY_P, "disabled": not has_agent},
				{},
				{"label": "Elimina l'Agente", "action": "delete", "disabled": not has_agent},
			]
	return []


func on_menu_action(action: StringName) -> void:
	match action:
		&"new": _new_agent()
		&"present": _present()
		&"delete":
			_delete_armed = true
			_on_delete_pressed()


## Cmd+N: new Agent.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if window_active and key != null and key.pressed and key.keycode == KEY_N and key.is_command_or_control_pressed():
		_new_agent()
		get_viewport().set_input_as_handled()
