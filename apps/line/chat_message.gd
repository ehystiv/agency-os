class_name ChatMessage
extends HBoxContainer
## A row of the line's log: Manager (box on the right), Entity (cyan ink),
## system message (red), note or error (centered).

signal retry_pressed
signal settings_pressed

enum Kind { MANAGER, ENTITY, SYSTEM, NOTE, ERROR }

const MANAGER_MAX_RATIO := 0.78
const CENTERED_MAX_RATIO := 0.85
## Room left for the "Rinvia" and "Impostazioni…" links next to an error.
const ERROR_LINKS_WIDTH := 110.0
const TYPING_CURSOR := "▌"
const CORRUPTION_GLYPHS := "█▓▒░#%&@¤§ΔΞ"
const CORRUPTION_STEPS := 12
const CORRUPTION_STEP_SECONDS := 0.13
const DRIP_SECONDS := 2.9

var kind: Kind
## Plain text of the message, without markup.
var plain_text: String = ""

var _label: Control
var _extra_width := 0.0


static func create(message_kind: Kind, text: String) -> ChatMessage:
	var message := ChatMessage.new()
	message.kind = message_kind
	message._build(text)
	return message


static func kind_for(who: String) -> Kind:
	match who:
		"manager":
			return Kind.MANAGER
		"entity":
			return Kind.ENTITY
	return Kind.SYSTEM


func _ready() -> void:
	resized.connect(_fit)


## Updates the Entity's text while streaming.
func set_entity_text(text: String, typing: bool) -> void:
	plain_text = text
	_label.theme_type_variation = &"MsgEntityTyping" if typing else &"MsgEntity"
	_set_rich(_escape(text if text != "" else "…") + (TYPING_CURSOR if typing else ""))


## Global rect of the text, for the effects drawn over it.
func text_rect() -> Rect2:
	return _label.get_global_rect()


# --- Effects on the Entity's text ------------------------------------------

## The words become a scream for a few seconds.
func play_shout(seconds: float) -> void:
	_label.theme_type_variation = &"MsgShout"
	_set_rich(_escape(plain_text.to_upper()))
	await get_tree().create_timer(seconds).timeout
	if is_inside_tree():
		_label.theme_type_variation = &"MsgEntity"
		_set_rich(_escape(plain_text))


## Voice reduced to a whisper; it stays like this in the archive too.
func set_whisper() -> void:
	_label.theme_type_variation = &"MsgWhisper"


func play_drip() -> void:
	var rich := _label as RichTextLabel
	rich.install_effect(DripEffect.new())
	_set_rich("[drip]%s[/drip]" % _escape(plain_text))
	await get_tree().create_timer(DRIP_SECONDS).timeout
	if is_inside_tree():
		_set_rich(_escape(plain_text))
		rich.custom_effects = []


## Letters get corrupted and become readable again little by little.
func play_corruption() -> void:
	for step in range(1, CORRUPTION_STEPS + 1):
		var chance := maxf(0.0, 0.55 * (1.0 - float(step) / CORRUPTION_STEPS))
		var corrupted := ""
		for c in plain_text:
			corrupted += c if c.strip_edges() == "" or randf() > chance else CORRUPTION_GLYPHS[randi() % CORRUPTION_GLYPHS.length()]
		_set_rich(_escape(corrupted))
		await get_tree().create_timer(CORRUPTION_STEP_SECONDS).timeout
		if not is_inside_tree():
			return
	_set_rich(_escape(plain_text))


func _set_rich(bbcode: String) -> void:
	(_label as RichTextLabel).text = bbcode


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _build(text: String) -> void:
	add_theme_constant_override("separation", 8)
	plain_text = text
	match kind:
		Kind.MANAGER:
			add_child(_spacer())
			var rich := RichTextLabel.new()
			rich.theme_type_variation = &"MsgManager"
			rich.bbcode_enabled = true
			rich.fit_content = true
			rich.scroll_active = false
			rich.selection_enabled = true
			rich.text = "[font_size=11][color=#8a92a8]MANAGER > [/color][/font_size]" + _escape(text)
			_label = rich
			# Box margins plus a bit of air: the prefix is already in the measured text.
			_extra_width = 26.0
			add_child(rich)
		Kind.ENTITY:
			# RichTextLabel for per-character effects (e.g. drip).
			var rich := RichTextLabel.new()
			rich.theme_type_variation = &"MsgEntity"
			rich.bbcode_enabled = true
			rich.fit_content = true
			rich.scroll_active = false
			rich.selection_enabled = true
			rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rich.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rich.text = _escape(text)
			_label = rich
			add_child(rich)
		Kind.SYSTEM:
			var label := _make_label(&"MsgSystem", text)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.uppercase = true
			add_child(label)
		Kind.NOTE, Kind.ERROR:
			alignment = BoxContainer.ALIGNMENT_CENTER
			var label := _make_label(&"MsgNote" if kind == Kind.NOTE else &"MsgError", text)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_extra_width = 24.0
			add_child(label)
			if kind == Kind.ERROR:
				var links := VBoxContainer.new()
				links.alignment = BoxContainer.ALIGNMENT_CENTER
				links.add_child(_link("Rinvia", retry_pressed.emit))
				links.add_child(_link("Impostazioni…", settings_pressed.emit))
				add_child(links)


func _make_label(variation: StringName, text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label = label
	return label


func _link(text: String, action: Callable) -> LinkButton:
	var link := LinkButton.new()
	link.text = text
	link.focus_mode = Control.FOCUS_NONE
	link.pressed.connect(action)
	return link


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Boxes that aren't full width follow the text, up to a maximum.
func _fit() -> void:
	if kind == Kind.ENTITY or kind == Kind.SYSTEM or size.x <= 0.0:
		return
	var ratio := MANAGER_MAX_RATIO if kind == Kind.MANAGER else CENTERED_MAX_RATIO
	var font := _label.get_theme_font("normal_font" if kind == Kind.MANAGER else "font")
	var font_size := _label.get_theme_font_size("normal_font_size" if kind == Kind.MANAGER else "font_size")
	var raw := (_label as RichTextLabel).get_parsed_text() if kind == Kind.MANAGER else (_label as Label).text
	var text_width := font.get_multiline_string_size(raw, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var max_width := size.x * ratio
	if kind == Kind.ERROR:
		max_width = minf(max_width, size.x - ERROR_LINKS_WIDTH)
	var width := minf(text_width + _extra_width, max_width)
	if not is_equal_approx(_label.custom_minimum_size.x, width):
		_label.custom_minimum_size.x = ceilf(width)
