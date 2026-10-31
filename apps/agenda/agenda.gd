extends AppContent
## Agenda: month calendar, scheduled sessions with time, title and preparation
## checklist, interviews held on that day.

const DAY_LETTERS: PackedStringArray = ["L", "M", "M", "G", "V", "S", "D"]
const SESSION_MARK := preload("res://ui/icons/tri_small.svg")
const INTERVIEW_MARK := Color("2fb8cc")
const TIME_REGEX := "^([01]?\\d|2[0-3]):[0-5]\\d$"

var _selected_day := ""
var _year := 0
var _month := 0
var _cancel_armed := false
## True while the day panel is rebuilt: fields losing focus don't save.
var _rebuilding := false
## Saving a new checklist item rebuilds the panel: the new field gets the focus back,
## so several items can be typed in a row.
var _refocus_new_item := false

@onready var _title: Label = %MonthTitle
@onready var _grid: GridContainer = %Grid
@onready var _side: VBoxContainer = %Side
@onready var _status: Label = %Status


func _ready() -> void:
	%Prev.pressed.connect(_shift_month.bind(-1))
	%Next.pressed.connect(_shift_month.bind(1))
	%Today.pressed.connect(func() -> void: _select(ItalianDate.today()))
	Campaign.agenda_changed.connect(_refresh)
	Campaign.interviews_changed.connect(_refresh)
	_select(ItalianDate.today())


## args: {"day": "YYYY-MM-DD"} opens the agenda on that day.
func on_opened(args: Dictionary = {}) -> void:
	if args.has("day"):
		_select(str(args.day))
	else:
		_refresh()


func _select(day: String) -> void:
	_selected_day = day
	_year = int(day.left(4))
	_month = int(day.substr(5, 2))
	_cancel_armed = false
	_refresh()


func _shift_month(step: int) -> void:
	_month += step
	if _month < 1:
		_month = 12
		_year -= 1
	elif _month > 12:
		_month = 1
		_year += 1
	_refresh()


func _refresh() -> void:
	_title.text = "%s %d" % [ItalianDate.MONTH_NAMES[_month - 1], _year]
	_build_grid()
	_build_side()
	var next := Campaign.next_session()
	_status.text = "Prossima sessione: %s %s %s" % [ItalianDate.weekday_short(next.date), ItalianDate.numeric(next.date), next.get("time", "")] if not next.is_empty() else "Nessuna sessione programmata"


# --- Calendar --------------------------------------------------------------

func _build_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for letter in DAY_LETTERS:
		var head := Label.new()
		head.theme_type_variation = &"CalHeader"
		head.text = letter
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(head)
	var first := "%04d-%02d-01" % [_year, _month]
	# Weeks start on Monday.
	var offset := (ItalianDate.weekday_index(first) + 6) % 7
	for i in offset:
		_grid.add_child(Control.new())
	var today := ItalianDate.today()
	var interview_days := {}
	for interview in Campaign.interviews:
		interview_days[ItalianDate.day(interview.opened_at)] = true
	var day := first
	while int(day.substr(5, 2)) == _month:
		_grid.add_child(_make_day(day, day == today, not Campaign.session_on(day).is_empty(), interview_days.has(day)))
		day = ItalianDate.add_days(day, 1)


func _make_day(day: String, is_today: bool, has_session: bool, has_interview: bool) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"CalDayToday" if is_today else &"CalDay"
	button.toggle_mode = true
	button.button_pressed = day == _selected_day
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(38, 30)
	button.text = str(int(day.right(2)))
	button.tooltip_text = ItalianDate.long_day(day) + (" · sessione programmata" if has_session else "") + (" · colloquio" if has_interview else "")
	button.pressed.connect(_select.bind(day))
	if has_session:
		var mark := TextureRect.new()
		mark.texture = SESSION_MARK
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.size = Vector2(8, 7)
		mark.position = Vector2(3, 3)
		button.add_child(mark)
	if has_interview:
		var dot := ColorRect.new()
		dot.color = INTERVIEW_MARK
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Anchored at the bottom center of the cell, whatever its width.
		dot.anchor_left = 0.5
		dot.anchor_right = 0.5
		dot.anchor_top = 1.0
		dot.anchor_bottom = 1.0
		dot.offset_left = -2.5
		dot.offset_right = 2.5
		dot.offset_top = -7.0
		dot.offset_bottom = -2.0
		button.add_child(dot)
	return button


# --- Selected day ----------------------------------------------------------

func _build_side() -> void:
	_rebuilding = true
	for child in _side.get_children():
		_side.remove_child(child)
		child.queue_free()
	_rebuilding = false
	var heading := Label.new()
	heading.theme_type_variation = &"MailSubject"
	heading.text = ItalianDate.long_day(_selected_day)
	_side.add_child(heading)
	var held := Campaign.interviews.filter(func(i: Interview) -> bool: return ItalianDate.day(i.opened_at) == _selected_day)
	if not held.is_empty():
		var row := HBoxContainer.new()
		row.add_child(_label("Colloqui:", &"", false))
		for interview: Interview in held:
			var link := LinkButton.new()
			link.text = "#%03d" % interview.number
			link.focus_mode = Control.FOCUS_NONE
			link.pressed.connect(func() -> void: app_requested.emit(&"line", {"interview": interview.number}))
			row.add_child(link)
		_side.add_child(row)
	var session := Campaign.session_on(_selected_day)
	if session.is_empty():
		_side.add_child(_label("Nessuna sessione in questo giorno.", &"HintLabel"))
		var schedule := Button.new()
		schedule.theme_type_variation = &"PrimaryButton"
		schedule.text = "Programma una sessione"
		schedule.focus_mode = Control.FOCUS_NONE
		schedule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		schedule.pressed.connect(func() -> void: Campaign.schedule_session(_selected_day))
		_side.add_child(schedule)
		return
	_side.add_child(_label("Ora", &"HintLabel"))
	var time := LineEdit.new()
	time.text = str(session.get("time", ""))
	time.placeholder_text = "21:00"
	time.max_length = 5
	time.custom_minimum_size = Vector2(70, 0)
	time.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	time.text_submitted.connect(func(_t: String) -> void: _commit_time(session, time))
	time.focus_exited.connect(func() -> void: _commit_time(session, time))
	_side.add_child(time)
	_side.add_child(_label("Titolo o Incarico", &"HintLabel"))
	var title := LineEdit.new()
	title.text = str(session.get("title", ""))
	title.placeholder_text = "Recupero Anomalia al faro"
	title.max_length = 80
	title.text_submitted.connect(func(_t: String) -> void: _commit_title(session, title))
	title.focus_exited.connect(func() -> void: _commit_title(session, title))
	_side.add_child(title)
	_side.add_child(_label("Preparazione", &"FieldLabel"))
	for item: Dictionary in session.checklist:
		_side.add_child(_make_check(session, item))
	var add_row := HBoxContainer.new()
	var new_item := LineEdit.new()
	new_item.placeholder_text = "Aggiungi una voce"
	new_item.max_length = 80
	new_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add := Button.new()
	add.text = "+"
	add.focus_mode = Control.FOCUS_NONE
	var add_item := func() -> void:
		if new_item.text.strip_edges() == "":
			return
		session.checklist.append({"text": new_item.text.strip_edges(), "done": false})
		_refocus_new_item = true
		Campaign.save_agenda()
	add.pressed.connect(add_item)
	new_item.text_submitted.connect(func(_t: String) -> void: add_item.call())
	add_row.add_child(new_item)
	add_row.add_child(add)
	_side.add_child(add_row)
	if _refocus_new_item:
		_refocus_new_item = false
		new_item.grab_focus.call_deferred()
	var cancel := LinkButton.new()
	cancel.theme_type_variation = &"LinkDanger"
	cancel.text = "Conferma: annulla la sessione" if _cancel_armed else "Annulla la sessione"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel.pressed.connect(func() -> void:
		if not _cancel_armed:
			_cancel_armed = true
			_build_side()
			return
		_cancel_armed = false
		Campaign.cancel_session(session))
	_side.add_child(cancel)


func _make_check(session: Dictionary, item: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var check := CheckBox.new()
	check.text = str(item.text)
	check.button_pressed = item.done
	check.focus_mode = Control.FOCUS_NONE
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.toggled.connect(func(on: bool) -> void:
		item.done = on
		Campaign.save_agenda())
	row.add_child(check)
	var remove := LinkButton.new()
	remove.text = "×"
	remove.tooltip_text = "Rimuovi " + str(item.text)
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(func() -> void:
		session.checklist.erase(item)
		Campaign.save_agenda())
	row.add_child(remove)
	return row


func _commit_time(session: Dictionary, field: LineEdit) -> void:
	if _rebuilding:
		return
	var value := field.text.strip_edges()
	if value != "" and RegEx.create_from_string(TIME_REGEX).search(value) == null:
		field.text = str(session.get("time", ""))
		return
	if value.length() == 4:
		value = "0" + value
	if value != str(session.get("time", "")):
		session.time = value
		Campaign.save_agenda()


func _commit_title(session: Dictionary, field: LineEdit) -> void:
	if _rebuilding:
		return
	var value := field.text.strip_edges()
	if value != str(session.get("title", "")):
		session.title = value
		Campaign.save_agenda()


## wrap = false for labels inside a row, which otherwise would have no width.
func _label(text: String, variation: StringName = &"", wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
