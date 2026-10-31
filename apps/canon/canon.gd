extends AppContent
## The Entity's canon: sections above the access level are redacted,
## but the Manager can read them anyway (GM view). The search shows only the points
## that contain the words (classified ones too), with the matches highlighted.

const REDACTION := "██████ ███ ████████ ██ ███████"
const HIGHLIGHT := "#ffd23f"

@onready var _sections: VBoxContainer = %Sections
@onready var _intro: Label = %Intro
@onready var _search: LineEdit = %Search
@onready var _count: Label = %Count


func _ready() -> void:
	Campaign.level_changed.connect(func(_level: int) -> void: _build())
	_search.text_changed.connect(func(_t: String) -> void: _build())
	_search.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel") and _search.text != "":
			_search.clear()
			_build()
			_search.accept_event())
	_build()


## Cmd+F (Ctrl+F) goes to the search field.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if window_active and key != null and key.pressed and key.keycode == KEY_F and key.is_command_or_control_pressed():
		_search.grab_focus()
		_search.edit()
		_search.select_all()
		get_viewport().set_input_as_handled()


func on_opened(_args: Dictionary = {}) -> void:
	_build()


func _build() -> void:
	var level := Campaign.level()
	_intro.text = "Quello che l'Entità sa e rispetta in ogni risposta. Livello di accesso attuale: %d. Le sezioni oltre il tuo livello l'Entità le conosce ma non te le rivela." % level
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	if query == "":
		_count.text = ""
		for section: Dictionary in Campaign.canon_sections():
			_sections.add_child(_make_section(section, level))
		return
	var found := 0
	for section: Dictionary in Campaign.canon_sections():
		# A section whose title matches shows all its points.
		var title_hit := str(section.get("title", "")).to_lower().contains(query)
		var hits: Array[String] = []
		for point: String in section.get("points", []):
			if title_hit or point.to_lower().contains(query):
				hits.append(point)
		if hits.is_empty():
			continue
		found += hits.size()
		_sections.add_child(_make_result(section, level, hits, query))
	_count.text = "Nessun risultato" if found == 0 else ("1 risultato" if found == 1 else "%d risultati" % found)


## A section in the search results: only the matching points, readable even if classified.
func _make_result(section: Dictionary, level: int, hits: Array[String], query: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var section_level := int(section.get("level", 0))
	var locked := section_level > level
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"CanonHeadingLocked" if locked else &"CanonHeading"
	title.text = str(section.get("title", ""))
	title.uppercase = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var badge := Label.new()
	badge.theme_type_variation = &"CanonBadge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.text = "base" if section_level == 0 else ("classificato · " if locked else "") + "livello %d" % section_level
	header.add_child(badge)
	for point in hits:
		box.add_child(_highlighted("•  " + point, query))
	return box


## A point with every occurrence of query in the highlight color, styled like CanonPoint.
func _highlighted(text: String, query: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.selection_enabled = true
	label.add_theme_font_size_override(&"normal_font_size", get_theme_font_size(&"font_size", &"CanonPoint"))
	label.add_theme_color_override(&"default_color", get_theme_color(&"font_color", &"CanonPoint"))
	label.add_theme_constant_override(&"line_separation", get_theme_constant(&"line_spacing", &"CanonPoint"))
	var bbcode := ""
	var lower := text.to_lower()
	var at := 0
	while true:
		var found := lower.find(query, at)
		if found < 0:
			bbcode += text.substr(at).replace("[", "[lb]")
			break
		bbcode += text.substr(at, found - at).replace("[", "[lb]")
		bbcode += "[color=%s][u]%s[/u][/color]" % [HIGHLIGHT, text.substr(found, query.length()).replace("[", "[lb]")]
		at = found + query.length()
	label.text = bbcode
	return label


func _make_section(section: Dictionary, level: int) -> Control:
	var section_level := int(section.get("level", 0))
	var locked := section_level > level
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"CanonHeadingLocked" if locked else &"CanonHeading"
	title.text = str(section.get("title", ""))
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
	for point: String in section.get("points", []):
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
