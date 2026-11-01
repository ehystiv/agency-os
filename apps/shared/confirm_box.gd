class_name ConfirmBox
extends RefCounted
## The small Windows 98 confirmation box: a warning icon, the question, Sì / No.
## Used before every deletion: `if await ConfirmBox.ask(self, "Elimina file", "Eliminare…?"):`.
## Texts are translated here (pass them in Italian, already formatted after tr() if needed).

const ICON := preload("res://ui/icons/event_warning.svg")
const TEXT_WIDTH := 320.0


## true if the Manager chose ok_text; false for No, Esc or the close button.
static func ask(parent: Node, title: String, text: String, ok_text: String = "Sì", cancel_text: String = "No") -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = TranslationServer.translate(title)
	dialog.ok_button_text = TranslationServer.translate(ok_text)
	dialog.cancel_button_text = TranslationServer.translate(cancel_text)
	dialog.exclusive = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	dialog.add_child(row)
	var icon := TextureRect.new()
	icon.texture = ICON
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var label := Label.new()
	label.text = TranslationServer.translate(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH
	row.add_child(label)
	dialog.add_user_signal("closed", [{"name": "ok", "type": TYPE_BOOL}])
	dialog.confirmed.connect(func() -> void: dialog.emit_signal("closed", true))
	dialog.canceled.connect(func() -> void: dialog.emit_signal("closed", false))
	parent.add_child(dialog)
	label.add_theme_color_override(&"font_color", dialog.get_theme_color(&"font_color", &"AcceptDialog"))
	# Windows 98 order, whatever the platform: Sì on the left, No on the right.
	var ok_button := dialog.get_ok_button()
	var cancel_button := dialog.get_cancel_button()
	var buttons := ok_button.get_parent()
	var ok_index := ok_button.get_index()
	var cancel_index := cancel_button.get_index()
	if cancel_index < ok_index:
		buttons.move_child(ok_button, cancel_index)
		buttons.move_child(cancel_button, ok_index)
	dialog.popup_centered()
	cancel_button.grab_focus.call_deferred()
	Sfx.play(&"error")
	var ok: bool = await Signal(dialog, "closed")
	dialog.queue_free()
	return ok
