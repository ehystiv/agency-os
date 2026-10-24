class_name SummaryBox
extends PanelContainer
## Riquadro con i ricordi dell'Entità su un colloquio chiuso, correggibile dal Manager.

signal saved(text: String)

const EMPTY_TEXT := "Nessun ricordo: il modello non ha scritto il riassunto. Verrà ritentato alla prossima apertura della linea, oppure scrivilo tu."

var _text: String
var _view: Label
var _editor: TextEdit
var _edit_link: LinkButton
var _edit_buttons: HBoxContainer


static func create(text: String) -> SummaryBox:
	var box := SummaryBox.new()
	box._text = text
	box._build()
	return box


func _build() -> void:
	theme_type_variation = &"SummaryPanel"
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"SummaryTitle"
	title.text = "Ricordi dell'Entità su questo colloquio"
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_edit_link = LinkButton.new()
	_edit_link.theme_type_variation = &"SummaryLink"
	_edit_link.text = "Correggi"
	_edit_link.focus_mode = Control.FOCUS_NONE
	_edit_link.pressed.connect(_start_editing)
	header.add_child(_edit_link)

	_view = Label.new()
	_view.theme_type_variation = &"SummaryText"
	_view.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_view)

	_editor = TextEdit.new()
	_editor.custom_minimum_size = Vector2(0, 150)
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.visible = false
	layout.add_child(_editor)

	_edit_buttons = HBoxContainer.new()
	_edit_buttons.alignment = BoxContainer.ALIGNMENT_END
	_edit_buttons.visible = false
	layout.add_child(_edit_buttons)
	var cancel := Button.new()
	cancel.text = "Annulla"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_stop_editing)
	_edit_buttons.add_child(cancel)
	var save := Button.new()
	save.theme_type_variation = &"PrimaryButton"
	save.text = "Salva"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_on_save_pressed)
	_edit_buttons.add_child(save)
	_show_text()


func _show_text() -> void:
	_view.text = _text if _text != "" else EMPTY_TEXT
	_view.modulate.a = 1.0 if _text != "" else 0.6


func _start_editing() -> void:
	_editor.text = _text
	_set_editing(true)
	_editor.grab_focus()


func _stop_editing() -> void:
	_set_editing(false)


func _set_editing(editing: bool) -> void:
	_view.visible = not editing
	_edit_link.visible = not editing
	_editor.visible = editing
	_edit_buttons.visible = editing


func _on_save_pressed() -> void:
	_text = _editor.text.strip_edges()
	_show_text()
	_set_editing(false)
	saved.emit(_text)
