class_name AgencyTicker
extends PanelContainer
## Active Desktop item: the Agency's news ticker, pinned to the desktop under the windows.
## Headlines from data/ticker.json, mixed with the branch's state.

const DATA_PATH := "res://data/ticker.json"
const SPEED := 60.0
const GAP := "     ✦     "

var _headlines: PackedStringArray = []
var _next := 0

@onready var _strip: Control = %Strip
@onready var _text: Label = %Text


func _ready() -> void:
	var file := FileAccess.open(Locale.data_path(DATA_PATH), FileAccess.READ)
	if file != null:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary:
			_headlines = PackedStringArray(data.get("headlines", []))
	# Moving even a hidden label redraws the whole screen: scroll only while it's shown.
	var follow_visibility := func() -> void: set_process(is_visible_in_tree())
	visibility_changed.connect(follow_visibility)
	follow_visibility.call_deferred()  # the desktop sets the starting visibility after this
	_restart()


func _process(delta: float) -> void:
	_text.position.x -= SPEED * delta
	if _text.position.x < -_text.size.x:
		_restart()


## Three headlines at a time, then one line about the branch.
func _restart() -> void:
	var parts: PackedStringArray = []
	for i in 3:
		if not _headlines.is_empty():
			parts.append(_headlines[_next % _headlines.size()])
			_next += 1
	parts.append(_branch_line())
	_text.text = GAP.join(parts) + GAP
	_text.reset_size()
	_text.position = Vector2(_strip.size.x, (_strip.size.y - _text.size.y) / 2.0)


func _branch_line() -> String:
	var unread := Campaign.correspondence.unread_count()
	var line := tr("FILIALE · Livello di accesso %d.") % Campaign.level()
	if unread > 0:
		line += " " + tr("%d memo non letti in AMail.") % unread
	return line
