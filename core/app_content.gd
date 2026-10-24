class_name AppContent
extends MarginContainer
## Base class for every app's content. Talks to its window only through signals.

@warning_ignore("unused_signal")
signal title_changed(title: String)
## action, when not empty, is {"app": id, "args": {...}} (the app opened by clicking the balloon)
## or {"folder": path} (opened in Finder).
@warning_ignore("unused_signal")
signal notification_requested(title: String, text: String, action: Dictionary)
## Asks to open another app; args reaches that app's on_opened(),
## e.g. &"line", {"interview": 3}.
@warning_ignore("unused_signal")
signal app_requested(id: StringName, args: Dictionary)
## System command for the desktop, e.g. &"arrange_windows", &"align_icons".
@warning_ignore("unused_signal")
signal command_requested(command: StringName)
## The app asks to close its own window (e.g. ESCI in the command prompt).
@warning_ignore("unused_signal")
signal close_requested

## Set by the window before the content enters the tree.
var app: AppInfo
## True while the app's window is in front (kept up to date by the window).
var window_active: bool = false


## Called on every opening, including when the window is restored from minimized.
## args comes from whoever asked to open it; empty for icons, Start menu and taskbar.
func on_opened(_args: Dictionary = {}) -> void:
	pass


## Called when the window is closed (it is hidden, not destroyed).
func on_closed() -> void:
	pass
