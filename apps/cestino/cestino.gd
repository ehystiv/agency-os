extends AppContent
## Cestino: pagine del Taccuino eliminate (ripristinabili) e bozze che l'Entità
## ha scritto e buttato senza mandarle (si leggono, ma non si ripristinano).

const SELECTED_TEXT := Color.WHITE

var _selected_id := ""
## Conferma in sospeso: "" oppure "elimina" / "svuota".
var _armed := ""

@onready var _rows: VBoxContainer = %Rows
@onready var _empty: Label = %Empty
@onready var _title: Label = %Title
@onready var _meta: Label = %Meta
@onready var _page_text: Label = %PageText
@onready var _ink_text: Label = %InkText
@onready var _note: Label = %Note
@onready var _restore: Button = %Restore
@onready var _delete: Button = %Delete
@onready var _empty_all: LinkButton = %EmptyAll
@onready var _count: Label = %Count


func _ready() -> void:
	_restore.pressed.connect(_on_restore_pressed)
	_delete.pressed.connect(_on_delete_pressed)
	_empty_all.pressed.connect(_on_empty_pressed)
	Campaign.trash_changed.connect(_refresh)
	_refresh()


func on_opened(_args: Dictionary = {}) -> void:
	_armed = ""
	_refresh()


func _sorted() -> Array[Dictionary]:
	var list := Campaign.trash.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.eliminato) > str(b.eliminato))
	return list


func _selected() -> Dictionary:
	for item in Campaign.trash:
		if item.id == _selected_id:
			return item
	return {}


func _refresh() -> void:
	var list := _sorted()
	if _selected().is_empty():
		_selected_id = str(list[0].id) if not list.is_empty() else ""
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_empty.visible = list.is_empty()
	for item in list:
		_rows.add_child(_make_row(item))
	_count.text = "%d %s" % [list.size(), "elemento" if list.size() == 1 else "elementi"]
	_empty_all.visible = not list.is_empty()
	_empty_all.text = "Conferma: svuota il cestino" if _armed == "svuota" else "Svuota il cestino"
	_show(_selected())


func _make_row(item: Dictionary) -> Button:
	var selected: bool = item.id == _selected_id
	var draft: bool = item.get("tipo", "") == "bozza"
	var row := Button.new()
	row.theme_type_variation = &"ListRow"
	row.toggle_mode = true
	row.button_pressed = selected
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0, 42)
	row.pressed.connect(func() -> void:
		_selected_id = str(item.id)
		_armed = ""
		_refresh())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name_label := _row_label(str(item.nome), selected)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if draft:
		name_label.theme_type_variation = &"ListMetaItalic"
		if selected:
			name_label.add_theme_color_override("font_color", SELECTED_TEXT)
	top.add_child(name_label)
	var date := _row_label(ItalianDate.numeric(str(item.eliminato)), selected)
	date.modulate.a = 0.75
	top.add_child(date)
	box.add_child(_row_label("File non registrato · origine sconosciuta" if draft else "Pagina del Taccuino", selected))
	return row


func _row_label(text: String, selected: bool) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"ListMeta"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if selected:
		label.add_theme_color_override("font_color", SELECTED_TEXT)
	return label


func _show(item: Dictionary) -> void:
	var has_item := not item.is_empty()
	var draft: bool = has_item and item.get("tipo", "") == "bozza"
	for node: Control in [_title, _meta, _note]:
		node.visible = has_item
	_restore.visible = has_item and not draft
	_delete.visible = has_item
	_delete.text = "Conferma eliminazione" if _armed == "elimina" else "Elimina definitivamente"
	_page_text.visible = has_item and not draft
	_ink_text.visible = draft
	if not has_item:
		return
	_title.text = str(item.nome)
	var when := "%s alle %s" % [ItalianDate.numeric(str(item.eliminato)), ItalianDate.time(str(item.eliminato))]
	if draft:
		_meta.text = "Origine sconosciuta · comparso il " + when
		_ink_text.text = str(item.get("testo", ""))
		_note.text = "Questo file non può essere ripristinato."
	else:
		var page: Dictionary = item.get("dati", {})
		var session := int(page.get("sessione", 0))
		_meta.text = "Eliminata il " + when + (" · Sessione %03d" % session if session > 0 else "")
		_page_text.text = str(page.get("testo", "")) if str(page.get("testo", "")) != "" else "(pagina vuota)"
		_note.text = "Ripristinandola torna nel Taccuino."


func _on_restore_pressed() -> void:
	var item := _selected()
	if not item.is_empty():
		_armed = ""
		Campaign.restore_from_trash(item)


func _on_delete_pressed() -> void:
	var item := _selected()
	if item.is_empty():
		return
	if _armed != "elimina":
		_armed = "elimina"
		_refresh()
		return
	_armed = ""
	Campaign.delete_from_trash(item)


func _on_empty_pressed() -> void:
	if _armed != "svuota":
		_armed = "svuota"
		_refresh()
		return
	_armed = ""
	Campaign.empty_trash()
