class_name ClaudeProvider
extends OpenAICompatibleProvider
## Claude tramite l'API Messages di Anthropic. Traduce i messaggi in stile OpenAI:
## il prompt di sistema va a parte, la temperatura sta tra 0 e 1, max_tokens è obbligatorio.

const API_URL := "https://api.anthropic.com/v1"
const API_VERSION := "2023-06-01"
const DEFAULT_MAX_TOKENS := 1024


func chat(messages: Array[Dictionary], options: Dictionary = {}) -> BrainRequest:
	var system: PackedStringArray = []
	var turns: Array[Dictionary] = []
	for message in messages:
		if message.role == "system":
			system.append(str(message.content))
		else:
			turns.append({"role": message.role, "content": str(message.content)})
	# La risposta precompilata non può finire con uno spazio.
	if not turns.is_empty() and turns.back().role == "assistant":
		turns.back().content = str(turns.back().content).strip_edges(false, true)
	var max_tokens := int(options.get("max_tokens", 0))
	var body := {
		"model": model,
		"max_tokens": max_tokens if max_tokens > 0 else DEFAULT_MAX_TOKENS,
		"messages": turns,
		"stream": bool(options.get("stream", true)),
		"temperature": clampf(float(options.get("temperature", 0.8)), 0.0, 1.0),
	}
	if not system.is_empty():
		body["system"] = "\n\n".join(system)
	# response_format è di OpenAI: qui lo ignoro e i JSON si cercano nel testo.
	return _start("/messages", HTTPClient.METHOD_POST, body)


func _headers() -> PackedStringArray:
	return PackedStringArray(["x-api-key: " + api_key, "anthropic-version: " + API_VERSION])


func _dialect() -> OpenAIJob.Dialect:
	return OpenAIJob.Dialect.ANTHROPIC
