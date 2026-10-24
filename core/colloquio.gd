class_name Colloquio
extends RefCounted
## Un colloquio sulla linea riservata. Si salva in campagne/<id>/colloqui/NNN.json.

const VERSION := 1

var numero: int = 0
## Livello di accesso al momento dell'apertura.
var livello: int = 1
## "aperto" oppure "chiuso".
var stato: String = "aperto"
var aperto: String = ""
var chiuso: String = ""
## Ricordi dell'Entità su questo colloquio, scritti alla chiusura.
var riassunto: String = ""
## Orari delle ricerche di AgencyOS avvenute durante il colloquio.
var ricerche: Array[String] = []
## {"chi": "manager"|"entita"|"sistema", "testo": String, "ora": String, "glitch"?: String}
var messaggi: Array[Dictionary] = []


static func file_name_for(n: int) -> String:
	return "colloqui/%03d.json" % n


func is_open() -> bool:
	return stato == "aperto"


func add(chi: String, testo: String) -> Dictionary:
	var message := {"chi": chi, "testo": testo, "ora": Time.get_datetime_string_from_system()}
	messaggi.append(message)
	return message


## Numero di messaggi scritti dal Manager o dall'Entità.
func spoken_count() -> int:
	return messaggi.filter(func(m: Dictionary) -> bool: return m.chi != "sistema").size()


func to_dict() -> Dictionary:
	return {
		"versione": VERSION,
		"numero": numero,
		"livello": livello,
		"stato": stato,
		"aperto": aperto,
		"chiuso": chiuso,
		"riassunto": riassunto,
		"ricerche": ricerche,
		"messaggi": messaggi,
	}


static func from_dict(data: Dictionary) -> Colloquio:
	var c := Colloquio.new()
	c.numero = int(data.get("numero", 0))
	c.livello = int(data.get("livello", 1))
	c.stato = str(data.get("stato", "chiuso"))
	c.aperto = str(data.get("aperto", ""))
	c.chiuso = str(data.get("chiuso", ""))
	c.riassunto = str(data.get("riassunto", ""))
	for when: Variant in data.get("ricerche", []):
		c.ricerche.append(str(when))
	for message: Variant in data.get("messaggi", []):
		if message is Dictionary:
			c.messaggi.append(message)
	return c
