class_name ObsidianExporter
extends Node
## Scrive note Markdown nella cartella del vault della campagna.
## Chiede la cartella la prima volta (finestra nativa) e chiede conferma
## prima di sovrascrivere file che nel frattempo sono cambiati, es. in Obsidian.

signal _dialog_closed(result: Variant)


## Gli elementi di notes sono {"nome": String, "testo": String}.
## Restituisce {"scritti": int, "saltati": int, "cartella": String, "errore": String, "annullato": bool}.
func export_notes(notes: Array[Dictionary]) -> Dictionary:
	var result := {"scritti": 0, "saltati": 0, "cartella": "", "errore": "", "annullato": false}
	var folder := Campaign.obsidian_folder
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		folder = await choose_folder()
		if folder == "":
			result.annullato = true
			return result
	result.cartella = folder
	var conflicts: Array[Dictionary] = []
	var ready_to_write: Array[Dictionary] = []
	for note in notes:
		var path := folder.path_join(str(note.nome) + ".md")
		if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) != str(note.testo):
			conflicts.append(note)
		else:
			ready_to_write.append(note)
	if not conflicts.is_empty():
		if await _confirm_overwrite(conflicts):
			ready_to_write.append_array(conflicts)
		else:
			result.saltati = conflicts.size()
	for note in ready_to_write:
		var err := Save.write_text(folder.path_join(str(note.nome) + ".md"), str(note.testo))
		if err != OK:
			result.errore = "Non riesco a scrivere nella cartella del vault (%s)." % error_string(err)
			return result
		result.scritti += 1
	return result


## Finestra nativa per scegliere la cartella del vault; "" se annullata.
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
		names.append("• " + str(note.nome) + ".md")
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


## Testo pronto per il fumetto dopo un export.
static func summary(result: Dictionary) -> String:
	if result.errore != "":
		return result.errore
	var text := "%d %s nel vault." % [result.scritti, "nota scritta" if result.scritti == 1 else "note scritte"]
	if result.saltati > 0:
		text += " %d lasciat%s com'%s." % [result.saltati, "a" if result.saltati == 1 else "e", "era" if result.saltati == 1 else "erano"]
	return text + " Clic per aprire la cartella."
