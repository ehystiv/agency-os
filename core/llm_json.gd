class_name LlmJson
extends RefCounted
## Chiede al modello un oggetto JSON con campi testuali, vincolato da uno schema
## quando il server lo supporta; altrimenti cerca l'oggetto nel testo libero.


## fields: nome -> schema del campo, es. {"oggetto": {"type": "string"}}.
## Restituisce {} se il modello non risponde o non scrive un oggetto valido.
static func ask(prompt: String, fields: Dictionary, temperature: float = 0.8, max_tokens: int = 900) -> Dictionary:
	var schema := {
		"type": "json_schema",
		"json_schema": {
			"name": "risposta",
			"strict": true,
			"schema": {"type": "object", "properties": fields, "required": fields.keys(), "additionalProperties": false},
		},
	}
	var messages: Array[Dictionary] = [{"role": "user", "content": prompt}]
	var options := {"stream": false, "temperature": temperature, "max_tokens": max_tokens, "extra": {"response_format": schema}}
	var request := Brain.chat(messages, options)
	if not request.is_done:
		await request.finished
	if not request.ok() and request.http_status >= 400 and request.http_status < 500:
		options.erase("extra")
		request = Brain.chat(messages, options)
		if not request.is_done:
			await request.finished
	if not request.ok():
		push_warning("LlmJson: chiamata fallita: %s" % request.error)
		return {}
	return parse(request.text)


## L'oggetto JSON nel testo, anche se circondato da altre parole o da ```json.
static func parse(text: String) -> Dictionary:
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return {}
	var data: Variant = JSON.parse_string(text.substr(start, end - start + 1))
	return data if data is Dictionary else {}
