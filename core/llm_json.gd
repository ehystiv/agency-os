class_name LlmJson
extends RefCounted
## Asks the model for a JSON object with text fields, constrained by a schema
## when the server supports it; otherwise looks for the object in free text.


## fields: name -> field schema, e.g. {"subject": {"type": "string"}}.
## Returns {} if the model doesn't answer or doesn't write a valid object.
static func ask(prompt: String, fields: Dictionary, temperature: float = 0.8, max_tokens: int = 900) -> Dictionary:
	var schema := {
		"type": "json_schema",
		"json_schema": {
			"name": "answer",
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
		push_warning("LlmJson: request failed: %s" % request.error)
		return {}
	return parse(request.text)


## The JSON object in the text, even when surrounded by other words or by ```json.
static func parse(text: String) -> Dictionary:
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return {}
	var data: Variant = JSON.parse_string(text.substr(start, end - start + 1))
	return data if data is Dictionary else {}
