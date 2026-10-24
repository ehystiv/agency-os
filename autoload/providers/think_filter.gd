class_name ThinkFilter
extends RefCounted
## Toglie dal testo i blocchi <think>…</think> dei modelli "che ragionano".
## Durante lo streaming nasconde anche un tag di apertura arrivato solo a metà.

const OPEN := "<think>"
const CLOSE := "</think>"


static func visible(raw: String, final: bool) -> String:
	var result := ""
	var pos := 0
	while true:
		var start := raw.find(OPEN, pos)
		if start < 0:
			result += raw.substr(pos)
			break
		result += raw.substr(pos, start - pos)
		var end := raw.find(CLOSE, start + OPEN.length())
		if end < 0:
			# Blocco ancora aperto: il resto è ragionamento.
			return result if not final else result.strip_edges()
		pos = end + CLOSE.length()
	# Alcuni modelli chiudono il ragionamento senza averlo aperto nel testo.
	var orphan_close := result.find(CLOSE)
	if orphan_close >= 0:
		result = result.substr(orphan_close + CLOSE.length())
	if not final:
		for cut in range(OPEN.length() - 1, 0, -1):
			if result.ends_with(OPEN.left(cut)):
				return result.left(result.length() - cut)
	return result.strip_edges(true, false) if final else result.lstrip("\n ")
