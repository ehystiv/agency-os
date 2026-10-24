class_name AppInfo
extends Resource
## Descrive un'applicazione di AgencyOS: come appare sulla scrivania e come si apre.

@export var id: StringName
## Nome breve per icone, menu Start e barra delle applicazioni.
@export var label: String
## Testo della barra del titolo; vuoto = usa label.
@export var window_title: String
@export var icon: Texture2D
## Scena del contenuto, con radice AppContent.
@export var scene: PackedScene
## Posizione della prima apertura; -1 su un asse = centrata su quell'asse.
@export var default_position: Vector2i = Vector2i(-1, 40)
@export var default_size: Vector2i = Vector2i(480, 220)
@export var on_desktop: bool = true
@export var on_start_menu: bool = true
@export var open_at_first_start: bool = false
## Menu decorativo sotto il titolo, es. ["File", "Modifica", "?"].
@export var menu_strip: PackedStringArray = []
