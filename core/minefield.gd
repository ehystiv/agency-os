class_name Minefield
extends RefCounted
## Logica del campo minato di Contenimento: le "mine" sono Anomalie da contenere.
## Il primo clic non trova mai un'Anomalia, né nelle caselle accanto.

enum State { READY, PLAYING, WON, LOST }

## Livello -> [larghezza, altezza, Anomalie]
const LEVELS := {"facile": [9, 9, 10], "medio": [12, 12, 24], "esperto": [16, 16, 40]}

var width: int
var height: int
var mines: int
var state := State.READY
var flags := 0
## Casella dell'Anomalia che ha fatto perdere, -1 se nessuna.
var exploded := -1

var _mined := PackedByteArray()
var _opened := PackedByteArray()
var _flagged := PackedByteArray()


func _init(level: String = "facile") -> void:
	var size: Array = LEVELS.get(level, LEVELS.facile)
	width = size[0]
	height = size[1]
	mines = size[2]
	# I Packed*Array si copiano per valore: vanno ridimensionati uno per uno.
	_mined.resize(width * height)
	_mined.fill(0)
	_opened.resize(width * height)
	_opened.fill(0)
	_flagged.resize(width * height)
	_flagged.fill(0)


func cells() -> int:
	return width * height


func is_mined(i: int) -> bool:
	return _mined[i] == 1


func is_opened(i: int) -> bool:
	return _opened[i] == 1


func is_flagged(i: int) -> bool:
	return _flagged[i] == 1


func is_over() -> bool:
	return state == State.WON or state == State.LOST


func neighbors(i: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	var x := i % width
	var y := i / width
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < width and ny < height:
				result.append(ny * width + nx)
	return result


## Anomalie nelle caselle accanto.
func count(i: int) -> int:
	var total := 0
	for n in neighbors(i):
		total += _mined[n]
	return total


func open(i: int) -> void:
	if is_over() or is_opened(i) or is_flagged(i):
		return
	if state == State.READY:
		_place_mines(i)
		state = State.PLAYING
	if is_mined(i):
		_opened[i] = 1
		exploded = i
		state = State.LOST
		for cell in cells():
			if is_mined(cell):
				_opened[cell] = 1
		return
	# Le caselle senza Anomalie vicine aprono anche le loro vicine.
	var stack := [i]
	while not stack.is_empty():
		var cell: int = stack.pop_back()
		if is_opened(cell) or is_flagged(cell):
			continue
		_opened[cell] = 1
		if count(cell) == 0:
			for n in neighbors(cell):
				if not is_opened(n):
					stack.append(n)
	_check_win()


func toggle_flag(i: int) -> void:
	if is_over() or is_opened(i):
		return
	_flagged[i] = 1 - _flagged[i]
	flags += 1 if is_flagged(i) else -1


## Su un numero già aperto, con abbastanza bandierine attorno, apre le altre vicine.
func chord(i: int) -> void:
	if not is_opened(i) or is_over():
		return
	var flagged_around := 0
	for n in neighbors(i):
		flagged_around += _flagged[n]
	if flagged_around != count(i):
		return
	for n in neighbors(i):
		if not is_flagged(n):
			open(n)


func _place_mines(safe: int) -> void:
	var forbidden := {safe: true}
	for n in neighbors(safe):
		forbidden[n] = true
	var candidates: Array[int] = []
	for cell in cells():
		if not forbidden.has(cell):
			candidates.append(cell)
	candidates.shuffle()
	for cell in candidates.slice(0, mines):
		_mined[cell] = 1


func _check_win() -> void:
	for cell in cells():
		if not is_mined(cell) and not is_opened(cell):
			return
	state = State.WON
	for cell in cells():
		if is_mined(cell) and not is_flagged(cell):
			_flagged[cell] = 1
			flags += 1
