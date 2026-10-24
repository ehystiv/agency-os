class_name ThinkFilter
extends RefCounted
## Removes the <think>…</think> blocks of "thinking" models from the text.
## While streaming it also hides an opening tag that has only half arrived.

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
			# Block still open: the rest is reasoning.
			return result if not final else result.strip_edges()
		pos = end + CLOSE.length()
	# Some models close the reasoning without having opened it in the text.
	var orphan_close := result.find(CLOSE)
	if orphan_close >= 0:
		result = result.substr(orphan_close + CLOSE.length())
	if not final:
		for cut in range(OPEN.length() - 1, 0, -1):
			if result.ends_with(OPEN.left(cut)):
				return result.left(result.length() - cut)
	return result.strip_edges(true, false) if final else result.lstrip("\n ")
