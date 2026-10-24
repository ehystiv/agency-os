extends AppContent
## Blocco note: apre i file lasciati dall'Entità sulla scrivania.
## Il Manager può correggerli: la sua versione diventa la verità per l'Entità.

const BASE_TITLE := "Blocco note"
const SAVED_SECONDS := 1.6

var _file_id := ""

@onready var _text: TextEdit = %Text
@onready var _status: RichTextLabel = %Status
@onready var _save: Button = %Save
@onready var _restore: Button = %Restore
@onready var _saved: Label = %Saved


func _ready() -> void:
	_save.pressed.connect(_on_save_pressed)
	_restore.pressed.connect(_on_restore_pressed)
	Campaign.correspondence.files_changed.connect(_refresh)
	_refresh()


## args: {"file": id} apre quel file e lo segna come letto.
func on_opened(args: Dictionary = {}) -> void:
	if args.has("file"):
		_file_id = str(args.file)
		_text.text = str(_file().get("contenuto", ""))
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
		_text.text = ""
		_text.placeholder_text = "Nessun file aperto."
		_status.text = ""
		_restore.visible = false
		title_changed.emit(BASE_TITLE)
		return
	title_changed.emit("%s · %s" % [file.nome, BASE_TITLE])
	if not _text.has_focus() and _text.text != str(file.contenuto):
		_text.text = str(file.contenuto)
	if file.get("corretto", false):
		_status.text = "[b]Corretto dal Manager.[/b] L'Entità considera questa versione la verità."
	else:
		_status.text = "Versione dell'Entità. Se la correggi, la tua versione diventa canone."
	_restore.visible = file.get("corretto", false)


func _on_save_pressed() -> void:
	var file := _file()
	if file.is_empty():
		return
	Campaign.correspondence.correct_file(file, _text.text)
	_refresh()
	_saved.show()
	await get_tree().create_timer(SAVED_SECONDS).timeout
	_saved.hide()


func _on_restore_pressed() -> void:
	var file := _file()
	if file.is_empty():
		return
	Campaign.correspondence.restore_file(file)
	_text.text = str(file.contenuto)
	_refresh()
