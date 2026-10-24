class_name OpenAICompatibleProvider
extends Node
## Provider per endpoint compatibili OpenAI (/v1/chat/completions, /v1/models).
## Fa avanzare tutte le richieste in corso a ogni frame.

## Precompila la risposta con un ragionamento vuoto: i modelli "che ragionano" (Qwen e simili)
## passano subito al testo. È l'unico metodo che LM Studio rispetta.
const EMPTY_THINK := "<think>\n\n</think>\n\n"

var base_url: String = ""
var api_key: String = ""
var model: String = ""

var _jobs: Array[OpenAIJob] = []
var _retired := false


func _ready() -> void:
	set_process(false)


## options: stream (bool), temperature (float), max_tokens (int, 0 = nessun limite),
## skip_reasoning (bool), extra (Dictionary).
func chat(messages: Array[Dictionary], options: Dictionary = {}) -> BrainRequest:
	var sent := messages
	var extra: Dictionary = options.get("extra", {}).duplicate()
	if bool(options.get("skip_reasoning", false)):
		sent = messages.duplicate()
		sent.append({"role": "assistant", "content": EMPTY_THINK})
		extra["chat_template_kwargs"] = {"enable_thinking": false}
	var body := {
		"model": model,
		"messages": sent,
		"stream": bool(options.get("stream", true)),
		"temperature": float(options.get("temperature", 0.8)),
	}
	var max_tokens := int(options.get("max_tokens", 0))
	if max_tokens > 0:
		body["max_tokens"] = max_tokens
	body.merge(extra, true)
	return _start("/chat/completions", HTTPClient.METHOD_POST, body)


## Il testo della risposta è l'elenco degli id dei modelli, uno per riga.
func list_models() -> BrainRequest:
	return _start("/models", HTTPClient.METHOD_GET, {}, _model_ids)


func _start(endpoint: String, method: HTTPClient.Method, body: Dictionary, on_json: Callable = Callable()) -> BrainRequest:
	var request := BrainRequest.new()
	var job := OpenAIJob.new(request, base_url, endpoint, method, _headers(), body, model, on_json)
	job.dialect = _dialect()
	_jobs.append(job)
	set_process(true)
	return request


func _headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + api_key]) if api_key != "" else PackedStringArray()


func _dialect() -> OpenAIJob.Dialect:
	return OpenAIJob.Dialect.OPENAI


## Il provider viene sostituito: finisce le richieste in corso e poi si libera.
func retire() -> void:
	_retired = true
	if _jobs.is_empty():
		queue_free()


func _process(_delta: float) -> void:
	for job in _jobs.duplicate():
		if job.poll():
			_jobs.erase(job)
	if _jobs.is_empty():
		set_process(false)
		if _retired:
			queue_free()


static func _model_ids(data: Dictionary) -> String:
	var ids: PackedStringArray = []
	for entry: Variant in data.get("data", []):
		if entry is Dictionary and entry.has("id"):
			ids.append(str(entry.id))
	return "\n".join(ids)
