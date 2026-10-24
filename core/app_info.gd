class_name AppInfo
extends Resource
## Describes an AgencyOS application: how it looks on the desktop and how it opens.

@export var id: StringName
## Short name for icons, Start menu and taskbar.
@export var label: String
## Title bar text; empty = use label.
@export var window_title: String
@export var icon: Texture2D
## Content scene, with an AppContent root.
@export var scene: PackedScene
## Position on first opening; -1 on an axis = centered on that axis.
@export var default_position: Vector2i = Vector2i(-1, 40)
@export var default_size: Vector2i = Vector2i(480, 220)
@export var on_desktop: bool = true
@export var on_start_menu: bool = true
@export var open_at_first_start: bool = false
## Decorative menu under the title, e.g. ["File", "Modifica", "?"].
@export var menu_strip: PackedStringArray = []
