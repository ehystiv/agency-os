extends AppContent
## "Benvenuti in AgencyOS 98", like Windows 98's Welcome screen: a few links on the left,
## the description of the one under the mouse on the right.

## UI pref: show it at every start (the desktop shows it anyway the first time).
const AT_START_PREF := "welcome_at_start"
const INTRO_HEADING := "Benvenuto, Manager"
const INTRO := "AgencyOS 98 è il terminale della tua Filiale. Da qui parli con l'Entità sulla linea riservata, tieni il Fascicolo e prepari le sessioni.\n\nPassa con il mouse su una voce a sinistra per saperne di più."
## label, icon, what it opens ({"app": id} or {"command": id}), description.
const LINKS: Array[Array] = [
	["Apri la linea riservata", preload("res://ui/icons/line.svg"), {"app": &"line"},
		"La linea con l'Entità U0047BB. Apri un colloquio e scrivile: risponderà. Ogni parola resta agli atti."],
	["Configura la linea", preload("res://ui/icons/ctrl.svg"), {"app": &"line_settings"},
		"Scegli il modello che darà voce all'Entità: locale (LM Studio, Ollama, llama.cpp), Hugging Face o Claude. «Prova connessione» controlla che tutto risponda."],
	["Prepara la campagna", preload("res://ui/icons/dossier.svg"), {"app": &"dossier"},
		"Nel Fascicolo scrivi chi è il Manager, chi sono gli Agenti e cosa è successo. L'Entità e l'Agenzia leggono queste note."],
	["Scopri AgencyOS", preload("res://ui/icons/keys.svg"), {"command": &"shortcuts"},
		"Le scorciatoie da tastiera e i trucchi del sistema: il tasto destro sulle icone, la barra Avvio veloce, Start › Esegui… e lo schermo per i giocatori."],
]

@onready var _links: VBoxContainer = %Links
@onready var _heading: Label = %Heading
@onready var _text: Label = %Text
@onready var _at_start: CheckBox = %AtStart


func _ready() -> void:
	for link in LINKS:
		var button := Button.new()
		button.theme_type_variation = &"StartMenuItem"
		button.add_theme_color_override(&"font_color", Color.WHITE)
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = link[1]
		button.text = tr(link[0])
		button.mouse_entered.connect(_describe.bind(link[0], link[3]))
		var target: Dictionary = link[2]
		button.pressed.connect(func() -> void: _follow(target))
		_links.add_child(button)
	_links.mouse_exited.connect(_describe.bind(INTRO_HEADING, INTRO))
	_at_start.toggled.connect(func(on: bool) -> void: Save.set_ui(AT_START_PREF, on))
	%Close.pressed.connect(close_requested.emit)


func on_opened(_args: Dictionary = {}) -> void:
	_at_start.set_pressed_no_signal(bool(Save.get_ui(AT_START_PREF, false)))
	_describe(INTRO_HEADING, INTRO)


func _describe(heading: String, text: String) -> void:
	_heading.text = tr(heading)
	_text.text = tr(text)


func _follow(target: Dictionary) -> void:
	if target.has("app"):
		app_requested.emit(target.app, {})
	else:
		command_requested.emit(target.command)
