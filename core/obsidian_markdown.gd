class_name ObsidianMarkdown
extends RefCounted
## Note Markdown per Obsidian, nello stesso formato del prototipo:
## frontmatter, callout, trascrizione e link [[…]] tra colloqui e pagine del Taccuino.

const CAMPAIGN_NAME := "Triangle Agency"
const UNSAFE_CHARS := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]


static func colloquio_name(c: Colloquio) -> String:
	return "%s - Colloquio %03d (%s)" % [CAMPAIGN_NAME, c.numero, ItalianDate.day(c.aperto)]


static func page_name(page: Dictionary) -> String:
	return "%s - %s" % [CAMPAIGN_NAME, safe_name(str(page.get("titolo", "")))]


## Toglie i caratteri che Obsidian o il file system non accettano nei nomi.
static func safe_name(text: String) -> String:
	for unsafe: String in UNSAFE_CHARS:
		text = text.replace(unsafe, "")
	var regex := RegEx.create_from_string("\\s+")
	text = regex.sub(text, " ", true).strip_edges().left(120)
	return text if text != "" else "Senza titolo"


## memo: il memo recapitato all'inizio di quella sessione, oppure {}.
static func colloquio(c: Colloquio, pages: Array[Dictionary], memo: Dictionary = {}) -> String:
	var lines: PackedStringArray = [
		"---",
		"tipo: colloquio",
		"campagna: " + CAMPAIGN_NAME,
		"sessione: %d" % c.numero,
		"data: " + ItalianDate.day(c.aperto),
		"livello_accesso: %d" % c.livello,
		"stato: " + ("in corso" if c.is_open() else "chiuso"),
		"tags: [triangle-agency, colloquio, u0047bb]",
		"---",
		"",
		"# Colloquio %03d con U0047BB" % c.numero,
		"",
	]
	var info := "> Aperto il %s alle %s" % [ItalianDate.numeric(c.aperto), ItalianDate.time(c.aperto)]
	if c.chiuso != "":
		info += " · chiuso il %s alle %s" % [ItalianDate.numeric(c.chiuso), ItalianDate.time(c.chiuso)]
	info += " · livello di accesso %d/5" % c.livello
	lines.append_array(["> [!info] Linea riservata", info, ""])
	lines.append_array(["## Trascrizione", ""])
	for m in c.messaggi:
		var text := str(m.testo)
		match str(m.chi):
			"sistema":
				lines.append_array(["*%s*" % text, ""])
			"manager":
				lines.append_array(["**Manager:** " + text.replace("\n", "  \n"), ""])
			"entita":
				var glitch := str(m.get("glitch", ""))
				lines.append_array(["**U0047BB:**" + (" *(glitch: %s)*" % glitch if glitch != "" else ""), quote(text), ""])
	if c.riassunto != "":
		lines.append_array(["## Ricordi dell'Entità", "", c.riassunto, ""])
	if not memo.is_empty():
		lines.append_array(["## Memo dell'Agenzia", "", "**Da:** %s  " % memo.mittente, "**Oggetto:** %s" % memo.oggetto, "", quote(str(memo.corpo)), ""])
	if not pages.is_empty():
		lines.append_array(["## Appunti collegati", ""])
		for page in pages:
			lines.append("- [[%s]]" % page_name(page))
		lines.append("")
	return "\n".join(lines)


## colloquio_linked: il colloquio della sessione della pagina, se esiste.
static func page(page_data: Dictionary, colloquio_linked: Colloquio) -> String:
	var lines: PackedStringArray = ["---", "tipo: appunti", "campagna: " + CAMPAIGN_NAME]
	var session := int(page_data.get("sessione", 0))
	if session > 0:
		lines.append("sessione: %d" % session)
	lines.append_array([
		"data: " + ItalianDate.day(str(page_data.get("creato", ""))),
		"aggiornato: " + ItalianDate.day(str(page_data.get("modificato", page_data.get("creato", "")))),
		"tags: [triangle-agency, appunti]",
		"---",
		"",
		"# " + (str(page_data.titolo) if str(page_data.get("titolo", "")) != "" else "Senza titolo"),
		"",
	])
	if colloquio_linked != null:
		lines.append_array(["Colloquio: [[%s]]" % colloquio_name(colloquio_linked), ""])
	lines.append_array([str(page_data.get("testo", "")), ""])
	return "\n".join(lines)


static func quote(text: String) -> String:
	var quoted: PackedStringArray = []
	for line in text.split("\n"):
		quoted.append("> " + line)
	return "\n".join(quoted)
