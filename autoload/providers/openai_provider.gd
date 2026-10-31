class_name OpenAICompatibleProvider
extends Node
## Provider for OpenAI-compatible endpoints (/v1/chat/completions, /v1/models).
## Advances all the running requests every frame.

## Prefills the reply with empty reasoning: "thinking" models (Qwen and the like)
## go straight to the text. It's the only method LM Studio respects.
const EMPTY_THINK := "<think>\n\n</think>\n\n"

var base_url: String = ""
var api_key: String = ""
var model: String = ""
## Name of the environment variable the key should come from, when it turned out empty.
var missing_key_variable: String = ""

var _jobs: Array[OpenAIJob] = []
var _retired := false


func _ready() -> void:
	set_process(false)


## options: stream (bool), temperature (float), max_tokens (int, 0 = no limit),
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


## The reply text is the list of model ids, one per line.
func list_models() -> BrainRequest:
	return _start("/models", HTTPClient.METHOD_GET, {}, _model_ids)


func _start(endpoint: String, method: HTTPClient.Method, body: Dictionary, on_json: Callable = Callable()) -> BrainRequest:
	var request := BrainRequest.new()
	if missing_key_variable != "":
		# Otherwise the server's 401 would blame a key that was never sent.
		request.finish_error("La variabile d'ambiente %s è vuota. Le app aperte dal Finder non vedono le variabili della shell: incolla la chiave nelle impostazioni della linea, o avvia AgencyOS dal Terminale." % missing_key_variable)
		return request
	var job := OpenAIJob.new(request, base_url, endpoint, method, _headers(), body, model, on_json)
	job.dialect = _dialect()
	_jobs.append(job)
	set_process(true)
	return request


func _headers() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + api_key]) if api_key != "" else PackedStringArray()


func _dialect() -> OpenAIJob.Dialect:
	return OpenAIJob.Dialect.OPENAI


## The provider is being replaced: finishes the running requests, then frees itself.
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
