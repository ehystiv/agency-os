extends AppContent
## Notepad: opens the files the Entity leaves on the desktop.
## The Manager can correct them: their version becomes the truth for the Entity.

const BASE_TITLE := "Blocco note"
const SAVED_SECONDS := 1.6

var _file_id := ""
## The text last put in the editor from the file: if the editor differs, there are unsaved edits.
var _loaded := ""

@onready var _text: TextEdit = %Text
@onready var _status: RichTextLabel = %Status
@onready var _save: Button = %Save
@onready var _restore: Button = %Restore
@onready var _saved: Label = %Saved
@onready var _find_bar: HBoxContainer = %FindBar
@onready var _find_field: LineEdit = %FindField


func _ready() -> void:
	_save.pressed.connect(_on_save_pressed)
	_restore.pressed.connect(_on_restore_pressed)
	Campaign.correspondence.files_changed.connect(_refresh)
	_text.text_changed.connect(_update_title)
	_text.gui_input.connect(_on_text_input)
	%FindNext.pressed.connect(_find_next)
	%FindClose.pressed.connect(_close_find)
	_find_field.text_submitted.connect(func(_t: String) -> void: _find_next())
	_find_field.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			_close_find()
			_find_field.accept_event())
	_refresh()


## args: {"file": id} opens that file and marks it as read.
func on_opened(args: Dictionary = {}) -> void:
	if args.has("file") and str(args.file) != _file_id:
		# Opening another file: the edits to this one are kept, as if saved.
		if _is_dirty():
			_on_save_pressed()
		_file_id = str(args.file)
		_show_text(str(_file().get("content", "")))
		var file := _file()
		if not file.is_empty():
			Campaign.correspondence.mark_file_read(file)
	_refresh()


func _file() -> Dictionary:
	return Campaign.correspondence.find_file(_file_id) if _file_id != "" else {}


func _refresh() -> void:
	var file := _file()
	var has_file := not file.is_empty()
	_text.editable = has_file
	_save.disabled = not has_file
	if not has_file:
		_show_text("")
		_text.placeholder_text = "Nessun file aperto."
		_status.text = ""
		_restore.visible = false
		title_changed.emit(BASE_TITLE)
		return
	# The file is replaced only when there's nothing unsaved to lose.
	if not _is_dirty() and _text.text != str(file.content):
		_show_text(str(file.content))
	_update_title()
	if file.get("corrected", false):
		_status.text = "[b]Corretto dal Manager.[/b] L'Entità considera questa versione la verità."
	else:
		_status.text = "Versione dell'Entità. Se la correggi, la tua versione diventa canone."
	_restore.visible = file.get("corrected", false)


func _on_save_pressed() -> void:
	var file := _file()
	if file.is_empty():
		return
	Campaign.correspondence.correct_file(file, _text.text)
	_loaded = _text.text
	_refresh()
	_saved.show()
	await get_tree().create_timer(SAVED_SECONDS).timeout
	_saved.hide()


func _on_restore_pressed() -> void:
	var file := _file()
	if file.is_empty():
		return
	Campaign.correspondence.restore_file(file)
	_show_text(str(file.content))
	_refresh()


func _show_text(text: String) -> void:
	_loaded = text
	_text.text = text


func _is_dirty() -> bool:
	return _text.text != _loaded


func _update_title() -> void:
	var file := _file()
	if file.is_empty():
		return
	title_changed.emit("%s%s · %s" % [file.name, " *" if _is_dirty() else "", BASE_TITLE])


## Ctrl+S (Cmd+S on Mac) saves, as in the Dossier.
func _on_text_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_S and key.is_command_or_control_pressed():
		get_viewport().set_input_as_handled()
		_on_save_pressed()


## Cmd+F finds, Cmd+G finds the next one (wherever the focus is in the window).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not window_active or key == null or not key.pressed or not key.is_command_or_control_pressed():
		return
	if key.keycode == KEY_F:
		_open_find()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_G:
		_find_next()
		get_viewport().set_input_as_handled()


# --- Menus ---------------------------------------------------------------------

func menu(title: String) -> Array[Dictionary]:
	var file := _file()
	match title:
		"File":
			return [
				{"label": "Salva la correzione", "action": "save", "accel": KEY_MASK_CMD_OR_CTRL | KEY_S, "disabled": file.is_empty()},
				{"label": "Ripristina la versione dell'Entità", "action": "restore", "disabled": not file.get("corrected", false)},
				{},
				{"label": "Mostra ai giocatori", "action": "present", "accel": KEY_MASK_CMD_OR_CTRL | KEY_MASK_SHIFT | KEY_P, "disabled": file.is_empty()},
			]
		"Cerca":
			return [
				{"label": "Trova…", "action": "find", "accel": KEY_MASK_CMD_OR_CTRL | KEY_F, "disabled": file.is_empty()},
				{"label": "Trova successivo", "action": "find_next", "accel": KEY_MASK_CMD_OR_CTRL | KEY_G, "disabled": _find_field.text == ""},
			]
	return []


func on_menu_action(action: StringName) -> void:
	match action:
		&"save": _on_save_pressed()
		&"restore": _on_restore_pressed()
		&"find": _open_find()
		&"find_next": _find_next()
		&"present":
			var file := _file()
			if not file.is_empty():
				# What is on screen, unsaved corrections included.
				present_requested.emit({"kind": "text", "caption": "%s · Blocco note" % file.name, "body": _text.text})


# --- Find ----------------------------------------------------------------------

func _open_find() -> void:
	if _file().is_empty():
		return
	_find_bar.show()
	var selected := _text.get_selected_text()
	if selected != "" and not selected.contains("\n"):
		_find_field.text = selected
	_find_field.grab_focus()
	_find_field.edit()
	_find_field.select_all()


func _close_find() -> void:
	_find_bar.hide()
	_text.grab_focus()


## From the caret on, back to the top after the end; the match is selected.
func _find_next() -> void:
	var wanted := _find_field.text
	if wanted == "":
		_open_find()
		return
	var from_line := _text.get_caret_line()
	var from_column := _text.get_caret_column()
	var found := _text.search(wanted, 0, from_line, from_column)
	if found.x < 0:
		Sfx.play(&"ding")
		return
	_text.select(found.y, found.x, found.y, found.x + wanted.length())
	_text.set_caret_line(found.y)
	_text.set_caret_column(found.x + wanted.length())
	_text.center_viewport_to_caret()
