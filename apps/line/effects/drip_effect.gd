class_name DripEffect
extends RichTextEffect
## [drip]…[/drip]: letters drip down, stay a moment and go back up
## ("drip" glitch). Each instance starts from the moment it is created.

const DURATION := 2.6
const DELAY_PER_CHAR := 0.012
const MIN_DEPTH := 4.0
const MAX_DEPTH := 22.0

var bbcode := "drip"

var _start_ms := Time.get_ticks_msec()


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var t := (Time.get_ticks_msec() - _start_ms) / 1000.0 - char_fx.relative_index * DELAY_PER_CHAR
	if t <= 0.0:
		return true
	var p := clampf(t / DURATION, 0.0, 1.0)
	# Goes down until 40%, stays until 70%, then goes back in place.
	var k := p / 0.4 if p < 0.4 else (1.0 if p < 0.7 else 1.0 - (p - 0.7) / 0.3)
	k = ease(k, -2.0)
	var depth := lerpf(MIN_DEPTH, MAX_DEPTH, fposmod(sin(char_fx.relative_index * 12.9898) * 43758.5453, 1.0))
	char_fx.offset.y += depth * k
	char_fx.color.a *= 1.0 - 0.55 * k
	return true
