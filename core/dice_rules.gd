class_name DiceRules
extends RefCounted
## Regole del tiro di Triangle Agency: si tirano 6d4, ogni 3 è un successo,
## ogni altro risultato aggiunge 1 Caos. Tre 3 esatti sono la Triscendenza (0 Caos),
## sei 3 sono un successo stabile (0 Caos).

const DICE := 6
const FACES := 4
const TARGET := 3
const COUNT_WORDS: PackedStringArray = ["Nessun 3", "Un 3", "Due 3", "Tre 3", "Quattro 3", "Cinque 3", "Sei 3"]


## {"tre": int, "esito": "TRISCENDENZA"|"SUCCESSO"|"FALLIMENTO", "caos": int, "stabile": bool}
static func evaluate(values: Array[int]) -> Dictionary:
	var threes := values.count(TARGET)
	var triscendenza := threes == 3
	var stable := threes == 3 or threes == DICE
	var outcome := "TRISCENDENZA" if triscendenza else ("SUCCESSO" if threes > 0 else "FALLIMENTO")
	return {"tre": threes, "esito": outcome, "caos": 0 if stable else values.size() - threes, "stabile": stable}


## Riga del risultato come nel prototipo, es. "Due 3 · SUCCESSO · Caos +4".
static func describe(result: Dictionary) -> String:
	var text := "%s · %s · Caos +%d" % [COUNT_WORDS[result.tre], result.esito, result.caos]
	if result.stabile and result.esito != "TRISCENDENZA":
		text += " (successo stabile)"
	if result.esito == "TRISCENDENZA":
		text += ". Scegli un effetto della Triscendenza."
	return text
