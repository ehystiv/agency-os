class_name ObsidianMarkdown
extends RefCounted
## Markdown notes for Obsidian: frontmatter, callout, transcript and [[…]] links
## between interviews and Notebook pages. File names and frontmatter are in English;
## the body keeps the interface language (Italian).

const CAMPAIGN_NAME := "Triangle Agency"
const UNSAFE_CHARS := ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", "#", "^", "[", "]"]


static func interview_name(interview: Interview) -> String:
	return "%s - Interview %03d (%s)" % [CAMPAIGN_NAME, interview.number, ItalianDate.day(interview.opened_at)]


static func page_name(page_data: Dictionary) -> String:
	return "%s - %s" % [CAMPAIGN_NAME, safe_name(str(page_data.get("title", "")))]


## Removes the characters that Obsidian or the file system don't accept in names.
static func safe_name(text: String) -> String:
	for unsafe: String in UNSAFE_CHARS:
		text = text.replace(unsafe, "")
	var regex := RegEx.create_from_string("\\s+")
	text = regex.sub(text, " ", true).strip_edges().left(120)
	return text if text != "" else "Senza titolo"


## memo: the memo delivered at the start of that session, or {}.
static func interview(entry: Interview, pages: Array[Dictionary], memo: Dictionary = {}) -> String:
	var lines: PackedStringArray = [
		"---",
		"type: interview",
		"campaign: " + CAMPAIGN_NAME,
		"session: %d" % entry.number,
		"date: " + ItalianDate.day(entry.opened_at),
		"access_level: %d" % entry.level,
		"status: " + ("in progress" if entry.is_open() else "closed"),
		"tags: [triangle-agency, interview, u0047bb]",
		"---",
		"",
		"# Colloquio %03d con U0047BB" % entry.number,
		"",
	]
	var info := "> Aperto il %s alle %s" % [ItalianDate.numeric(entry.opened_at), ItalianDate.time(entry.opened_at)]
	if entry.closed_at != "":
		info += " · chiuso il %s alle %s" % [ItalianDate.numeric(entry.closed_at), ItalianDate.time(entry.closed_at)]
	info += " · livello di accesso %d/5" % entry.level
	lines.append_array(["> [!info] Linea riservata", info, ""])
	lines.append_array(["## Trascrizione", ""])
	for m in entry.messages:
		var text := str(m.text)
		match str(m.who):
			"system":
				lines.append_array(["*%s*" % text, ""])
			"manager":
				lines.append_array(["**Manager:** " + text.replace("\n", "  \n"), ""])
			"entity":
				var glitch := str(m.get("glitch", ""))
				lines.append_array(["**U0047BB:**" + (" *(glitch: %s)*" % glitch if glitch != "" else ""), quote(text), ""])
	if entry.summary != "":
		lines.append_array(["## Ricordi dell'Entità", "", entry.summary, ""])
	if not memo.is_empty():
		lines.append_array(["## Memo dell'Agenzia", "", "**Da:** %s  " % memo.sender, "**Oggetto:** %s" % memo.subject, "", quote(str(memo.body)), ""])
	if not pages.is_empty():
		lines.append_array(["## Appunti collegati", ""])
		for page_data in pages:
			lines.append("- [[%s]]" % page_name(page_data))
		lines.append("")
	return "\n".join(lines)


## linked: the interview of the page's session, if there is one.
static func page(page_data: Dictionary, linked: Interview) -> String:
	var lines: PackedStringArray = ["---", "type: notes", "campaign: " + CAMPAIGN_NAME]
	var session := int(page_data.get("session", 0))
	if session > 0:
		lines.append("session: %d" % session)
	lines.append_array([
		"date: " + ItalianDate.day(str(page_data.get("created", ""))),
		"updated: " + ItalianDate.day(str(page_data.get("modified", page_data.get("created", "")))),
		"tags: [triangle-agency, notes]",
		"---",
		"",
		"# " + (str(page_data.title) if str(page_data.get("title", "")) != "" else "Senza titolo"),
		"",
	])
	if linked != null:
		lines.append_array(["Colloquio: [[%s]]" % interview_name(linked), ""])
	lines.append_array([str(page_data.get("text", "")), ""])
	return "\n".join(lines)


static func quote(text: String) -> String:
	var quoted: PackedStringArray = []
	for line in text.split("\n"):
		quoted.append("> " + line)
	return "\n".join(quoted)
