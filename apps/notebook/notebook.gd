extends AppContent
## The Manager's Notebook: note pages linked to the sessions,
## saved automatically, exportable to Obsidian one by one or all together.

const SAVE_DELAY := 0.8
const SELECTED_TEXT := Color.WHITE

var _selected_id := ""
var _dirty := false
var _delete_armed := false
var _loading := false
var _exporter: ObsidianExporter

@onready var _rows: VBoxContainer = %Rows
@onready var _empty_list: Label = %EmptyList
@onready var _editor: Control = %Editor
@onready var _empty: Control = %Empty
@onready var _title: LineEdit = %Title
@onready var _session: OptionButton = %Session
@onready var _text: TextEdit = %Text
@onready var _status: Label = %Status
@onready var _export: Button = %Export
@onready var _delete: LinkButton = %Delete
@onready var _vault: Label = %Vault
@onready var _save_timer: Timer = %SaveTimer


func _ready() -> void:
	_exporter = ObsidianExporter.new()
	add_child(_exporter)
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(_flush)
	%NewPage.pressed.connect(_new_page)
	%NewPageEmpty.pressed.connect(_new_page)
	_export.pressed.connect(_export_page)
	%ExportAll.pressed.connect(_export_all)
	%ChangeVault.pressed.connect(_change_vault)
	_delete.pressed.connect(_on_delete_pressed)
	_title.text_changed.connect(_on_title_changed)
	_text.text_changed.connect(_on_text_changed)
	_session.item_selected.connect(_on_session_selected)
	Campaign.pages_changed.connect(_refresh)
	Campaign.interviews_changed.connect(_refresh)
	_refresh()


## args: {"session": n} opens that session's page, or creates one;
## {"export_all": true} exports everything.
func on_opened(args: Dictionary = {}) -> void:
	if args.get("export_all", false):
		_export_all()
	if args.has("session"):
		var number := int(args.session)
		var existing := Campaign.pages_for_session(number)
		if existing.is_empty():
			_flush()
			_selected_id = str(Campaign.new_page(number).id)
		else:
			_select(str(existing.back().id))
		_refresh()
		_text.grab_focus.call_deferred()


func on_closed() -> void:
	_flush()


## Shut down, Restart or Cmd+Q within SAVE_DELAY of the last keystroke: save without touching the UI.
func _exit_tree() -> void:
	if not _dirty:
		return
	_dirty = false
	var page := _page()
	if not page.is_empty():
		Campaign.save_page(page, true)


func _page() -> Dictionary:
	return Campaign.find_page(_selected_id) if _selected_id != "" else {}


func _refresh() -> void:
	var ordered := Campaign.pages_by_modified()
	if _page().is_empty():
		_selected_id = str(ordered[0].id) if not ordered.is_empty() else ""
	_refresh_list(ordered)
	_refresh_editor()
	_refresh_vault()


func _refresh_list(ordered: Array[Dictionary]) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_empty_list.visible = ordered.is_empty()
	for page in ordered:
		_rows.add_child(_make_row(page))


func _make_row(page: Dictionary) -> Button:
	var selected: bool = page.id == _selected_id
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = selected
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 42)
	row.pressed.connect(_select.bind(str(page.id)))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var title := _row_label(str(page.title) if str(page.title) != "" else "Senza titolo", selected)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(title)
	var date := _row_label(ItalianDate.numeric(str(page.modified)), selected)
	date.modulate.a = 0.75
	top.add_child(date)
	var session := int(page.session)
	box.add_child(_row_label("Sessione %03d" % session if session > 0 else "Nessuna sessione", selected))
	return row


func _row_label(text: String, selected: bool) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ListMeta"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if selected:
		label.add_theme_color_override("font_color", SELECTED_TEXT)
	return label


func _refresh_editor() -> void:
	var page := _page()
	var has_page := not page.is_empty()
	_editor.visible = has_page
	_empty.visible = not has_page
	_export.visible = has_page
	_delete.visible = has_page
	_delete.text = "Conferma: sposta nel cestino" if _delete_armed else "Sposta nel cestino"
	if not has_page:
		_status.text = ""
		return
	_loading = true
	if not _title.has_focus():
		_title.text = str(page.title)
	if not _text.has_focus():
		_text.text = str(page.text)
	_session.clear()
	_session.add_item("Nessuna", 0)
	for i in range(Campaign.interviews.size() - 1, -1, -1):
		var interview := Campaign.interviews[i]
		_session.add_item("Colloquio %03d · %s" % [interview.number, ItalianDate.short(interview.opened_at)], interview.number)
	_session.select(maxi(0, _session.get_item_index(int(page.session))))
	_loading = false


func _refresh_vault() -> void:
	var folder := Campaign.obsidian_folder
	var home := OS.get_environment("HOME")
	if home != "" and folder.begins_with(home):
		folder = "~" + folder.substr(home.length())
	_vault.text = "Vault: " + (folder if folder != "" else "non scelto (te lo chiedo al primo export)")


func _select(id: String) -> void:
	_flush()
	_selected_id = id
	_delete_armed = false
	_refresh()


func _new_page() -> void:
	_flush()
	_selected_id = str(Campaign.new_page().id)
	_delete_armed = false
	_refresh()
	_text.grab_focus.call_deferred()


# --- Edits and saving ------------------------------------------------------

func _on_title_changed(text: String) -> void:
	var page := _page()
	if _loading or page.is_empty():
		return
	page.title = text
	_mark_dirty()


func _on_text_changed() -> void:
	var page := _page()
	if _loading or page.is_empty():
		return
	page.text = _text.text
	_mark_dirty()


func _on_session_selected(index: int) -> void:
	var page := _page()
	if _loading or page.is_empty():
		return
	page.session = _session.get_item_id(index)
	_mark_dirty()
	_flush()


func _mark_dirty() -> void:
	_dirty = true
	_status.text = "Modifiche non salvate…"
	_save_timer.start()


func _flush() -> void:
	_save_timer.stop()
	if not _dirty:
		return
	_dirty = false
	var page := _page()
	if page.is_empty():
		return
	Campaign.save_page(page, true)
	_status.text = "Salvato alle " + ItalianDate.time(str(page.modified))
	_refresh_list(Campaign.pages_by_modified())


func _on_delete_pressed() -> void:
	var page := _page()
	if page.is_empty():
		return
	if not _delete_armed:
		_delete_armed = true
		_refresh_editor()
		return
	_delete_armed = false
	_save_timer.stop()
	_dirty = false
	_selected_id = ""
	Campaign.trash_page(page)


# --- Export ----------------------------------------------------------------

func _export_page() -> void:
	_flush()
	var page := _page()
	if page.is_empty():
		return
	var linked := Campaign.find(int(page.session))
	var notes: Array[Dictionary] = [{"name": ObsidianMarkdown.page_name(page), "text": ObsidianMarkdown.page(page, linked)}]
	await _write_notes(notes)


## All the campaign's interviews and pages, to resync the vault.
func _export_all() -> void:
	_flush()
	var notes: Array[Dictionary] = []
	for interview in Campaign.interviews:
		notes.append({"name": ObsidianMarkdown.interview_name(interview), "text": ObsidianMarkdown.interview(interview, Campaign.pages_for_session(interview.number), Campaign.correspondence.mail_for_session(interview.number))})
	for page in Campaign.pages:
		notes.append({"name": ObsidianMarkdown.page_name(page), "text": ObsidianMarkdown.page(page, Campaign.find(int(page.session)))})
	if notes.is_empty():
		notification_requested.emit("Niente da esportare", "Non ci sono ancora colloqui né pagine.", {})
		return
	await _write_notes(notes)


func _write_notes(notes: Array[Dictionary]) -> void:
	var result := await _exporter.export_notes(notes)
	_refresh_vault()
	if result.cancelled:
		return
	var title := "Esportato in Obsidian" if result.error == "" else "Esportazione non riuscita"
	notification_requested.emit(title, ObsidianExporter.summary(result), {"folder": result.folder} if result.folder != "" else {})


func _change_vault() -> void:
	await _exporter.choose_folder()
	_refresh_vault()
