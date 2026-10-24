class_name DiceRules
extends RefCounted
## Triangle Agency roll rules: roll 6d4, every 3 is a success,
## every other result adds 1 Chaos. Exactly three 3s is the Triscendence (0 Chaos),
## six 3s is a stable success (0 Chaos).

const DICE := 6
const FACES := 4
const TARGET := 3
const TRISCENDENCE := "triscendence"
const SUCCESS := "success"
const FAILURE := "failure"
## Words shown in the result line (the interface is in Italian).
const COUNT_WORDS: PackedStringArray = ["Nessun 3", "Un 3", "Due 3", "Tre 3", "Quattro 3", "Cinque 3", "Sei 3"]
const OUTCOME_WORDS := {TRISCENDENCE: "TRISCENDENZA", SUCCESS: "SUCCESSO", FAILURE: "FALLIMENTO"}


## {"threes": int, "outcome": TRISCENDENCE|SUCCESS|FAILURE, "chaos": int, "stable": bool}
static func evaluate(values: Array[int]) -> Dictionary:
	var threes := values.count(TARGET)
	var stable := threes == 3 or threes == DICE
	var outcome := TRISCENDENCE if threes == 3 else (SUCCESS if threes > 0 else FAILURE)
	return {"threes": threes, "outcome": outcome, "chaos": 0 if stable else values.size() - threes, "stable": stable}


## The outcome as shown on screen, e.g. "SUCCESSO".
static func outcome_word(result: Dictionary) -> String:
	return OUTCOME_WORDS[result.outcome]


## Result line as in the prototype, e.g. "Due 3 · SUCCESSO · Caos +4".
static func describe(result: Dictionary) -> String:
	var text := "%s · %s · Caos +%d" % [COUNT_WORDS[result.threes], outcome_word(result), result.chaos]
	if result.stable and result.outcome != TRISCENDENCE:
		text += " (successo stabile)"
	if result.outcome == TRISCENDENCE:
		text += ". Scegli un effetto della Triscendenza."
	return text
