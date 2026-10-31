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


func _ready() -> void:
	_save.pressed.connect(_on_save_pressed)
	_restore.pressed.connect(_on_restore_pressed)
	Campaign.correspondence.files_changed.connect(_refresh)
	_text.text_changed.connect(_update_title)
	_text.gui_input.connect(_on_text_input)
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
