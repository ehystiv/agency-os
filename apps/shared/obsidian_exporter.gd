class_name ObsidianExporter
extends Node
## Writes Markdown notes into the campaign's vault folder.
## Asks for the folder the first time (native dialog) and asks for confirmation
## before overwriting files that changed in the meantime, e.g. in Obsidian.

signal _dialog_closed(result: Variant)


## The notes items are {"name": String, "text": String}.
## Returns {"written": int, "skipped": int, "folder": String, "error": String, "cancelled": bool}.
func export_notes(notes: Array[Dictionary]) -> Dictionary:
	var result := {"written": 0, "skipped": 0, "folder": "", "error": "", "cancelled": false}
	var folder := Campaign.obsidian_folder
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		folder = await choose_folder()
		if folder == "":
			result.cancelled = true
			return result
	result.folder = folder
	var conflicts: Array[Dictionary] = []
	var ready_to_write: Array[Dictionary] = []
	for note in notes:
		var path := folder.path_join(str(note.name) + ".md")
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) != str(note.text):
			conflicts.append(note)
		else:
			ready_to_write.append(note)
	if not conflicts.is_empty():
		if await _confirm_overwrite(conflicts):
			ready_to_write.append_array(conflicts)
		else:
			result.skipped = conflicts.size()
	for note in ready_to_write:
		var err := Save.write_text(folder.path_join(str(note.name) + ".md"), str(note.text))
		if err != OK:
			result.error = "Non riesco a scrivere nella cartella del vault (%s)." % error_string(err)
			return result
		result.written += 1
	return result


## Native dialog to choose the vault folder; "" if cancelled.
func choose_folder() -> String:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "Cartella del vault Obsidian"
	if Campaign.obsidian_folder != "":
		dialog.current_dir = Campaign.obsidian_folder
	dialog.dir_selected.connect(func(path: String) -> void: _dialog_closed.emit(path))
	dialog.canceled.connect(func() -> void: _dialog_closed.emit(""))
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)
	var chosen: String = await _dialog_closed
	dialog.queue_free()
	if chosen != "":
		Campaign.set_obsidian_folder(chosen)
	return chosen


func _confirm_overwrite(conflicts: Array[Dictionary]) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.title = "AgencyOS"
	var names: PackedStringArray = []
	for note in conflicts.slice(0, 5):
		names.append("• " + str(note.name) + ".md")
	if conflicts.size() > 5:
		names.append("• …e altri %d" % (conflicts.size() - 5))
	dialog.dialog_text = "%s nel vault con un contenuto diverso, forse modificat%s in Obsidian:\n\n%s\n\nSovrascrivere?" % [
		"Esiste già un file" if conflicts.size() == 1 else "Esistono già %d file" % conflicts.size(),
		"o" if conflicts.size() == 1 else "i",
		"\n".join(names)]
	dialog.ok_button_text = "Sovrascrivi"
	dialog.cancel_button_text = "Lascia com'è" if conflicts.size() == 1 else "Lasciali come sono"
	dialog.confirmed.connect(func() -> void: _dialog_closed.emit(true))
	dialog.canceled.connect(func() -> void: _dialog_closed.emit(false))
	add_child(dialog)
	dialog.popup_centered()
	var overwrite: bool = await _dialog_closed
	dialog.queue_free()
	return overwrite


## Text for the balloon after an export.
static func summary(result: Dictionary) -> String:
	if result.error != "":
		return result.error
	var text := "%d %s nel vault." % [result.written, "nota scritta" if result.written == 1 else "note scritte"]
	if result.skipped > 0:
		text += " %d lasciat%s com'%s." % [result.skipped, "a" if result.skipped == 1 else "e", "era" if result.skipped == 1 else "erano"]
	return text + " Clic per aprire la cartella."
