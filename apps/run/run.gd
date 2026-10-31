extends AppContent
## Start › Esegui…: opens a branch program or one of the Entity's files by name,
## like the Prompt's APRI. Remembers the last names typed (↑/↓ go through them).

const HISTORY_PREF := "run_history"
const HISTORY_SIZE := 10

var _history_index := -1

@onready var _name: LineEdit = %Name
@onready var _ok: Button = %Ok


func _ready() -> void:
	_name.text_submitted.connect(func(_t: String) -> void: _run())
	_name.text_changed.connect(func(_t: String) -> void: _refresh())
	_name.gui_input.connect(_on_name_input)
	_ok.pressed.connect(_run)
	%Cancel.pressed.connect(close_requested.emit)


func on_opened(_args: Dictionary = {}) -> void:
	var history := _history()
	_name.text = history[0] if not history.is_empty() else ""
	_history_index = 0 if not history.is_empty() else -1
	_refresh()


func on_activated() -> void:
	_name.grab_focus.call_deferred()
	_name.select_all.call_deferred()


func _refresh() -> void:
	_ok.disabled = _name.text.strip_edges() == ""


func _run() -> void:
	var typed := _name.text.strip_edges()
	if typed == "":
		return
	var found := BranchFiles.resolve(typed)
	if found.has("program"):
		app_requested.emit(found.program[1], {})
	elif found.has("file"):
		app_requested.emit(&"notepad", {"file": found.file.id})
	else:
		_not_found(typed)
		return
	_remember(typed)
	close_requested.emit()


func _not_found(typed: String) -> void:
	Sfx.play(&"ding")
	var dialog := AcceptDialog.new()
	dialog.title = typed
	dialog.dialog_text = tr("Impossibile trovare il file '%s' o uno dei suoi componenti. Verificare che il percorso e il nome del file siano corretti e che tutte le librerie richieste siano disponibili.") % typed
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "OK"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.tree_exited.connect(func() -> void: _name.grab_focus())
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 0))


func _history() -> Array[String]:
	var result: Array[String] = []
	result.assign(Save.get_ui(HISTORY_PREF, []))
	return result


func _remember(typed: String) -> void:
	var history := _history()
	history.erase(typed)
	history.push_front(typed)
	Save.set_ui(HISTORY_PREF, history.slice(0, HISTORY_SIZE))


func _on_name_input(event: InputEvent) -> void:
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	var history := _history()
	if step == 0 or history.is_empty():
		return
	_name.accept_event()
	_history_index = clampi(_history_index + step, 0, history.size() - 1)
	_name.text = history[_history_index]
	_name.caret_column = _name.text.length()
	_refresh()
