class_name BranchFiles
## The branch's programs and the Entity's files, by name: what DIR lists and what
## the Prompt's APRI and Start › Esegui… can open.

## Branch programs: name, app id, size shown by DIR.
const SYSTEM_FILES: Array[Array] = [
	["LINEA.EXE", &"line", "24.576"], ["FASCICOLO.DAT", &"dossier", "8.192"], ["CAM03.AVI", &"cam", "1.048.576"],
	["AMAIL.EXE", &"amail", "65.536"], ["TACCUINO.EXE", &"notebook", "20.480"], ["CALC.EXE", &"calc", "12.288"],
	["AGENDA.EXE", &"agenda", "18.432"], ["CONTEN.EXE", &"mine", "28.672"], ["LETTORE.EXE", &"player", "40.960"],
	["PANNELLO.CPL", &"ctrl", "9.216"], ["CANONE.HLP", &"canon", "32.768"], ["REGISTRO.EVT", &"event_viewer", "16.384"],
]
## Other names that open a program, only by their exact name (DIR doesn't list them).
const ALIASES := {"COMMAND": &"term", "COMMAND.COM": &"term", "CMD": &"term", "PROMPT": &"term", "NOTEPAD": &"notepad", "BLOCCONOTE": &"notepad", "BENVENUTI": &"welcome", "WELCOME": &"welcome"}


## What a typed name stands for:
## {"program": [name, app id, size]}, {"file": the Entity's file}, {"ambiguous": [names]} or {}.
## An exact name (or app id) wins; otherwise the start of a name, but only if it's not
## ambiguous ("C" could be CALC, CAM03, CANONE…).
static func resolve(typed: String) -> Dictionary:
	var wanted := typed.strip_edges().to_upper()
	if wanted == "":
		return {}
	for entry in SYSTEM_FILES:
		if entry[0] == wanted or String(entry[1]).to_upper() == wanted:
			return {"program": entry}
	if ALIASES.has(wanted):
		return {"program": [wanted, ALIASES[wanted], ""]}
	var files := Campaign.correspondence.delivered_files()
	for file in files:
		if str(file.name).to_upper() == wanted:
			return {"file": file}
	var matches: Array = []
	for entry in SYSTEM_FILES:
		if str(entry[0]).begins_with(wanted):
			matches.append(entry)
	for file in files:
		if str(file.name).to_upper().begins_with(wanted):
			matches.append(file)
	if matches.is_empty():
		return {}
	if matches.size() == 1:
		return {"program": matches[0]} if matches[0] is Array else {"file": matches[0]}
	var names: Array = matches.map(func(match_: Variant) -> String: return str(match_[0]) if match_ is Array else str(match_.name).to_upper())
	return {"ambiguous": names}
