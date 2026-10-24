class_name Interview
extends RefCounted
## An interview on the reserved line. Saved in campaigns/<id>/interviews/NNN.json.

const VERSION := 1
const OPEN := "open"
const CLOSED := "closed"

var number: int = 0
## Access level when the interview was opened.
var level: int = 1
## OPEN or CLOSED.
var status: String = OPEN
var opened_at: String = ""
var closed_at: String = ""
## The Entity's memories of this interview, written when it is closed.
var summary: String = ""
## Times of the AgencyOS searches that happened during the interview.
var searches: Array[String] = []
## {"who": "manager"|"entity"|"system", "text": String, "time": String, "glitch"?: String}
var messages: Array[Dictionary] = []


static func file_name_for(n: int) -> String:
	return "interviews/%03d.json" % n


func is_open() -> bool:
	return status == OPEN


func add(who: String, text: String) -> Dictionary:
	var message := {"who": who, "text": text, "time": Time.get_datetime_string_from_system()}
	messages.append(message)
	return message


## Number of messages written by the Manager or the Entity.
func spoken_count() -> int:
	return messages.filter(func(m: Dictionary) -> bool: return m.who != "system").size()


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"number": number,
		"level": level,
		"status": status,
		"opened_at": opened_at,
		"closed_at": closed_at,
		"summary": summary,
		"searches": searches,
		"messages": messages,
	}


static func from_dict(data: Dictionary) -> Interview:
	var interview := Interview.new()
	interview.number = int(data.get("number", 0))
	interview.level = int(data.get("level", 1))
	interview.status = str(data.get("status", CLOSED))
	interview.opened_at = str(data.get("opened_at", ""))
	interview.closed_at = str(data.get("closed_at", ""))
	interview.summary = str(data.get("summary", ""))
	for when: Variant in data.get("searches", []):
		interview.searches.append(str(when))
	for message: Variant in data.get("messages", []):
		if message is Dictionary:
			interview.messages.append(message)
	return interview
