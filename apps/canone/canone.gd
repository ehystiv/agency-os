extends AppContent
## Canone dell'Entità: le sezioni oltre il livello di accesso sono oscurate,
## ma il Manager può leggerle comunque (vista GM).

const REDACTION := "██████ ███ ████████ ██ ███████"

@onready var _sections: VBoxContainer = %Sections
@onready var _intro: Label = %Intro


func _ready() -> void:
	Campaign.level_changed.connect(func(_level: int) -> void: _build())
	_build()


func on_opened(_args: Dictionary = {}) -> void:
	_build()


func _build() -> void:
	var level := Campaign.level()
	_intro.text = "Quello che l'Entità sa e rispetta in ogni risposta. Livello di accesso attuale: %d. Le sezioni oltre il tuo livello l'Entità le conosce ma non te le rivela." % level
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	for section: Dictionary in Campaign.canone_sections():
		_sections.add_child(_make_section(section, level))


func _make_section(section: Dictionary, level: int) -> Control:
	var section_level := int(section.get("livello", 0))
	var locked := section_level > level
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"CanonHeadingLocked" if locked else &"CanonHeading"
	title.text = str(section.get("titolo", ""))
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var badge := Label.new()
	badge.theme_type_variation = &"CanonBadge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if section_level == 0:
		badge.text = "base"
	else:
		badge.text = ("classificato · " if locked else "") + "livello %d" % section_level
	header.add_child(badge)

	var points := VBoxContainer.new()
	points.add_theme_constant_override("separation", 6)
	for point: String in section.get("punti", []):
		var label := Label.new()
		label.theme_type_variation = &"CanonPoint"
		label.text = "•  " + point
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		points.add_child(label)

	if locked:
		var redaction := Label.new()
		redaction.theme_type_variation = &"CanonRedact"
		redaction.text = REDACTION
		box.add_child(redaction)
		var reveal := LinkButton.new()
		reveal.theme_type_variation = &"CanonReveal"
		reveal.focus_mode = Control.FOCUS_NONE
		reveal.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		reveal.text = "▸ Leggi comunque (vista GM)"
		reveal.pressed.connect(func() -> void:
			points.visible = not points.visible
			reveal.text = ("▾ " if points.visible else "▸ ") + "Leggi comunque (vista GM)")
		box.add_child(reveal)
		points.visible = false
	box.add_child(points)
	return box
