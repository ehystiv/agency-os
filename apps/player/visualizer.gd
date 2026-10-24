extends Control
## The Player's green bars; the one marking the current track is red.

const BARS := 20
const GREEN := Color("3fd27a")
const RED := Color("e5262c")
const BACKGROUND := Color.BLACK

var engine: MusicEngine


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if engine == null:
		return
	var levels := engine.levels(BARS)
	var bar_width := size.x / BARS
	for i in BARS:
		var height := maxf(1.0, round(levels[i] * (size.y - 2.0)))
		var color := RED if i == engine.track * 4 and engine.playing else GREEN
		draw_rect(Rect2(i * bar_width + 1.0, size.y - height, bar_width - 2.0, height), color)
