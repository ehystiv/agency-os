extends AppContent
## Properties of a desktop icon: an app or one of the Entity's files.
## Opened with {"app": AppInfo} or {"file": the file's id}.

const FILE_ICON := preload("res://ui/icons/note.svg")
## The date every branch program carries, as if installed with the system.
const INSTALLED := "1998-01-01T09:00:00"
const LABEL_WIDTH := 130.0

@onready var _icon: TextureRect = %Icon
@onready var _name: LineEdit = %Name
@onready var _sections: VBoxContainer = %Sections


func _ready() -> void:
	%Ok.pressed.connect(close_requested.emit)
	%Cancel.pressed.connect(close_requested.emit)
	%Tabs.set_tab_title(0, tr("Generale"))


func on_opened(args: Dictionary = {}) -> void:
	if args.get("app") is AppInfo:
		_show_app(args.app)
	elif args.has("file"):
		_show_file(Campaign.correspondence.find_file(str(args.file)))


func _show_app(app: AppInfo) -> void:
	if app == null:
		return
	_icon.texture = app.icon
	if app.id == &"trash":
		_fill(tr(app.label), [
			[tr("Tipo:"), tr("Cartella di sistema")],
			[tr("Percorso:"), "C:\\"],
			[tr("Contenuto:"), tr("%d oggetti") % Campaign.trash.size()],
			[],
			[tr("Creato:"), _when(INSTALLED)],
		], [false, true, false])
		return
	var file_name := _program_name(app)
	var bytes := _program_size(app)
	_fill(file_name, [
		[tr("Tipo:"), tr("Applicazione")],
		[tr("Percorso:"), "C:\\FILIALE"],
		[tr("Dimensioni:"), _size(bytes)],
		[tr("Descrizione:"), tr(app.label)],
		[tr("Origine:"), "Triangle Agency"],
		[],
		[tr("Creato:"), _when(INSTALLED)],
		[tr("Modificato:"), _when(INSTALLED)],
		[tr("Ultimo accesso:"), ItalianDate.numeric(Time.get_datetime_string_from_system())],
	], [true, false, true])


func _show_file(file: Dictionary) -> void:
	if file.is_empty():
		return
	_icon.texture = FILE_ICON
	var name := str(file.name)
	var created := str(file.get("created", ""))
	var modified := str(file.get("corrected_at", created))
	_fill(name, [
		[tr("Tipo:"), _file_type(name)],
		[tr("Percorso:"), "C:\\FILIALE\\DESKTOP"],
		[tr("Dimensioni:"), _size(str(file.get("content", "")).to_utf8_buffer().size())],
		[tr("Origine:"), tr("sconosciuta")],
		[],
		[tr("Creato:"), _when(created)],
		[tr("Modificato:"), _when(modified)],
		[tr("Ultimo accesso:"), ItalianDate.numeric(Time.get_datetime_string_from_system()) if file.get("read", false) else "—"],
	], [false, true, false])


## rows: [label, value], or [] for a separator. attributes: read-only, hidden, archive.
func _fill(title: String, rows: Array, attributes: Array) -> void:
	title_changed.emit(tr("Proprietà - %s") % title)
	_name.text = title
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	_sections.add_child(HSeparator.new())
	var grid := _new_grid()
	for row: Array in rows:
		if row.is_empty():
			_sections.add_child(HSeparator.new())
			grid = _new_grid()
			continue
		var label := Label.new()
		label.text = row[0]
		label.custom_minimum_size.x = LABEL_WIDTH
		grid.add_child(label)
		var value := Label.new()
		value.text = row[1]
		value.theme_type_variation = &"InfoText"
		grid.add_child(value)
	_sections.add_child(HSeparator.new())
	%ReadOnly.button_pressed = attributes[0]
	%Hidden.button_pressed = attributes[1]
	%Archive.button_pressed = attributes[2]


func _new_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"v_separation", 4)
	_sections.add_child(grid)
	return grid


## The name DIR shows for the program; apps without one get their label as an .EXE.
static func _program_name(app: AppInfo) -> String:
	for entry in BranchFiles.SYSTEM_FILES:
		if entry[1] == app.id:
			return entry[0]
	for alias: String in BranchFiles.ALIASES:
		if BranchFiles.ALIASES[alias] == app.id and alias.contains("."):
			return alias
	return TranslationServer.translate(app.label).to_upper().replace(" ", "").left(8) + ".EXE"


static func _program_size(app: AppInfo) -> int:
	for entry in BranchFiles.SYSTEM_FILES:
		if entry[1] == app.id:
			return int(str(entry[2]).replace(".", ""))
	# A stable, made-up size for the programs DIR doesn't list.
	return 4096 * (2 + absi(hash(String(app.id))) % 14)


## "24.576 byte (24 KB)"
static func _size(bytes: int) -> String:
	var kb := maxi(1, ceili(bytes / 1024.0))
	return TranslationServer.translate("%s byte (%d KB)") % [_grouped(bytes), kb]


static func _grouped(n: int) -> String:
	var digits := str(n)
	var out := ""
	while digits.length() > 3:
		out = TranslationServer.translate(".", "thousands") + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return digits + out


static func _when(iso: String) -> String:
	var day := ItalianDate.numeric(iso)
	if day == "":
		return "—"
	var hour := ItalianDate.time(iso)
	return day + ("  " + hour if hour != "" else "")


static func _file_type(name: String) -> String:
	match name.get_extension().to_lower():
		"txt":
			return TranslationServer.translate("Documento di testo")
		"log":
			return TranslationServer.translate("File di registro")
		"":
			return TranslationServer.translate("File")
		var extension:
			return TranslationServer.translate("File %s") % extension.to_upper()
