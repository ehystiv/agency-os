extends AppContent
## AMail: the Agency's memos, newest first. Unread ones are bold;
## opening a memo marks it as read (and the counter on the desktop goes down).

const SELECTED_TEXT := Color.WHITE
const BOLD := preload("res://ui/fonts/IBMPlexMono-Medium.ttf")

var _selected_id := ""

@onready var _rows: VBoxContainer = %Rows
@onready var _receiving: Label = %Receiving
@onready var _empty: Label = %Empty
@onready var _hint: Label = %Hint
@onready var _message: Control = %Message
@onready var _from: Label = %From
@onready var _date: Label = %Date
@onready var _subject: Label = %Subject
@onready var _body: Label = %Body
@onready var _count: Label = %Count


func _ready() -> void:
	var mail := Campaign.correspondence
	mail.mail_changed.connect(_refresh)
	mail.receiving_changed.connect(func(_active: bool) -> void: _refresh())
	_refresh()


## args: {"memo": id} opens that memo.
func on_opened(args: Dictionary = {}) -> void:
	if args.has("memo"):
		_open(str(args.memo))
	else:
		_refresh()


func _refresh() -> void:
	var mail := Campaign.correspondence
	var list := mail.delivered_mail()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_receiving.visible = mail.receiving
	_empty.visible = list.is_empty() and not mail.receiving
	for memo in list:
		_rows.add_child(_make_row(memo))
	var unread := mail.unread_count()
	_count.text = "%d %s · %d da leggere" % [list.size(), "messaggio" if list.size() == 1 else "messaggi", unread]
	_show(mail.find_mail(_selected_id), not list.is_empty())


func _make_row(memo: Dictionary) -> Button:
	var selected: bool = memo.id == _selected_id
	var unread: bool = not memo.read
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = selected
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 42)
	row.pressed.connect(_open.bind(str(memo.id)))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var sender := _row_label(str(memo.sender), selected, unread)
	sender.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sender.clip_text = true
	sender.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(sender)
	var date := _row_label(ItalianDate.numeric(str(memo.created)), selected, false)
	date.modulate.a = 0.75
	top.add_child(date)
	var subject := _row_label(str(memo.subject), selected, unread)
	subject.clip_text = true
	subject.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(subject)
	return row


func _row_label(text: String, selected: bool, bold: bool) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ListMeta"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if selected:
		label.add_theme_color_override("font_color", SELECTED_TEXT)
	if bold:
		label.add_theme_font_override("font", BOLD)
	return label


func _open(id: String) -> void:
	_selected_id = id
	var memo := Campaign.correspondence.find_mail(id)
	if not memo.is_empty() and not memo.read:
		Campaign.correspondence.mark_read(memo)
	else:
		_refresh()


func _show(memo: Dictionary, has_messages: bool) -> void:
	_message.visible = not memo.is_empty()
	_hint.visible = memo.is_empty()
	_hint.text = "Seleziona un messaggio da leggere." if has_messages else ""
	if memo.is_empty():
		return
	_from.text = "%s <%s>" % [memo.sender, _address(str(memo.sender))]
	_date.text = "%s %s" % [ItalianDate.numeric(str(memo.created)), ItalianDate.time(str(memo.created))]
	_subject.text = str(memo.subject)
	_body.text = str(memo.body)


## "Ufficio Controlli Qualità" -> "ufficio.controlli.qualit@filiale.agency", as in the prototype.
static func _address(sender: String) -> String:
	var regex := RegEx.create_from_string("[^a-z]+")
	return regex.sub(sender.to_lower(), ".", true).trim_prefix(".").trim_suffix(".") + "@filiale.agency"


# --- Menus ---------------------------------------------------------------------

func menu(title: String) -> Array[Dictionary]:
	var memo := Campaign.correspondence.find_mail(_selected_id)
	match title:
		"Messaggio":
			return [
				{"label": "Copia il testo del messaggio", "action": "copy", "disabled": memo.is_empty()},
			]
		"Cartelle":
			return [
				{"label": "Posta in arrivo", "action": "inbox", "checked": true},
				{"label": "Posta inviata (vuota)", "action": "sent", "disabled": true},
				{"label": "Posta eliminata (accesso negato)", "action": "deleted", "disabled": true},
			]
	return []


func on_menu_action(action: StringName) -> void:
	match action:
		&"copy":
			var memo := Campaign.correspondence.find_mail(_selected_id)
			if not memo.is_empty():
				DisplayServer.clipboard_set("Da: %s\nOggetto: %s\n\n%s" % [memo.sender, memo.subject, memo.body])
		&"inbox":
			_refresh()
