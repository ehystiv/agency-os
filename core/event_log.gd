class_name EventLog
extends RefCounted
## System events rebuilt from the campaign data, newest first.
## Each event: {time (ISO), severity ("i", "w", "e"), origin, text}.
## Origins and texts are shown on screen, so they stay in Italian.


static func collect() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var previous_level := 1
	for interview in Campaign.interviews:
		_add(events, interview.opened_at, "i", "AgencyOS", "Canale del General Manager aperto (sessione %d)." % interview.number)
		if interview.level > previous_level:
			_add(events, interview.opened_at, "i", "Controlli Qualità", "Livello di accesso del General Manager aggiornato a %d." % interview.level)
		previous_level = maxi(previous_level, interview.level)
		for when in interview.searches:
			_add(events, when, "w", "AgencyOS", "Ricerca di U0047BB avviata sul canale del General Manager. Esito: nessuna attività anomala.")
		for m in interview.messages:
			var glitch := str(m.get("glitch", ""))
			if glitch != "":
				_add(events, str(m.get("time", "")), "w", "Driver video", "Instabilità del segnale rilevata (codice %s)." % glitch.to_upper())
		if interview.closed_at != "":
			_add(events, interview.closed_at, "i", "AgencyOS", "Canale del General Manager chiuso (sessione %d)." % interview.number)
	var mail := Campaign.correspondence
	for memo in mail.delivered_mail():
		_add(events, str(memo.created), "i", "AMail", "Memo recapitato da %s: \"%s\"." % [memo.sender, memo.subject])
	for file in mail.delivered_files():
		_add(events, str(file.created), "e", "File system", "File non registrato comparso sulla scrivania: %s. Origine sconosciuta." % file.name)
		if file.get("corrected", false):
			_add(events, str(file.get("corrected_at", file.created)), "w", "File system", "Il file %s è stato modificato dall'utente." % file.name)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.time) > str(b.time))
	return events


static func _add(events: Array[Dictionary], when: String, severity: String, origin: String, text: String) -> void:
	if when != "":
		events.append({"time": when, "severity": severity, "origin": origin, "text": text})
