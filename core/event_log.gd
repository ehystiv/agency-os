class_name EventLog
extends RefCounted
## Eventi di sistema ricostruiti dai dati della campagna, dal più recente.
## Ogni evento: {ora (ISO), gravita ("i", "w", "e"), origine, testo}.


static func collect() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var previous_level := 1
	for c in Campaign.colloqui:
		_add(events, c.aperto, "i", "AgencyOS", "Canale del General Manager aperto (sessione %d)." % c.numero)
		if c.livello > previous_level:
			_add(events, c.aperto, "i", "Controlli Qualità", "Livello di accesso del General Manager aggiornato a %d." % c.livello)
		previous_level = maxi(previous_level, c.livello)
		for when in c.ricerche:
			_add(events, when, "w", "AgencyOS", "Ricerca di U0047BB avviata sul canale del General Manager. Esito: nessuna attività anomala.")
		for m in c.messaggi:
			var glitch := str(m.get("glitch", ""))
			if glitch != "":
				_add(events, str(m.get("ora", "")), "w", "Driver video", "Instabilità del segnale rilevata (codice %s)." % glitch.to_upper())
		if c.chiuso != "":
			_add(events, c.chiuso, "i", "AgencyOS", "Canale del General Manager chiuso (sessione %d)." % c.numero)
	var mail := Campaign.correspondence
	for memo in mail.delivered_mail():
		_add(events, str(memo.creato), "i", "AMail", "Memo recapitato da %s: \"%s\"." % [memo.mittente, memo.oggetto])
	for file in mail.delivered_files():
		_add(events, str(file.creato), "e", "File system", "File non registrato comparso sulla scrivania: %s. Origine sconosciuta." % file.nome)
		if file.get("corretto", false):
			_add(events, str(file.get("corretto_il", file.creato)), "w", "File system", "Il file %s è stato modificato dall'utente." % file.nome)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.ora) > str(b.ora))
	return events


static func _add(events: Array[Dictionary], when: String, severity: String, origin: String, text: String) -> void:
	if when != "":
		events.append({"ora": when, "gravita": severity, "origine": origin, "testo": text})
