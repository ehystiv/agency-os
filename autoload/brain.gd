extends Node
## Single interface to the language model.
## Every call returns a BrainRequest with its own signals (text pieces, end, error).
## Settings live in user://config/model.cfg, one section per provider
## plus [line] provider = the active one. It can also be edited by hand.

signal settings_changed

const SETTINGS_PATH := "user://config/model.cfg"
const ACTIVE_SECTION := "line"
const PROVIDERS: Array[String] = ["local", "huggingface", "claude"]
const PROVIDER_LABELS: Dictionary[String, String] = {"local": "Locale", "huggingface": "Hugging Face", "claude": "Claude (Anthropic)"}
const DEFAULTS: Dictionary[String, Dictionary] = {
	"local": {
		"server": "lmstudio",
		"url": "http://localhost:1234/v1",
		"model": "qwen3.5-9b-mlx",
		"api_key": "",
		"temperature": 0.9,
		## The model's context tokens: decides how much conversation fits in the prompt.
		"context": 8192,
		## Token limit per reply, reasoning included. 0 = no limit.
		"max_reply": 1024,
		## Makes reasoning models (Qwen and the like) skip reasoning: much faster replies.
		"skip_reasoning": true,
	},
	"huggingface": {
		"url": HuggingFaceProvider.ROUTER_URL,
		"model": "meta-llama/Llama-3.3-70B-Instruct",
		"api_key": "",
		"temperature": 0.9,
		"context": 32768,
		"max_reply": 1024,
		"skip_reasoning": false,
	},
	"claude": {
		"url": ClaudeProvider.API_URL,
		"model": "claude-sonnet-5-5",
		"api_key": "",
		"temperature": 0.9,
		"context": 131072,
		"max_reply": 1024,
		"skip_reasoning": false,
	},
}

var _settings := ConfigFile.new()
var _provider: OpenAICompatibleProvider


func _ready() -> void:
	if _settings.load(SETTINGS_PATH) != OK:
		_settings.set_value(ACTIVE_SECTION, "provider", "local")
		for key: String in DEFAULTS.local:
			_settings.set_value("local", key, DEFAULTS.local[key])
		_settings.save(SETTINGS_PATH)
	_apply()


func provider_id() -> String:
	var id := str(_settings.get_value(ACTIVE_SECTION, "provider", "local"))
	return id if id in PROVIDERS else "local"


## A setting of the given provider (empty = the active one).
func get_setting(key: String, provider: String = "") -> Variant:
	var section := provider if provider != "" else provider_id()
	# Without a non-null default ConfigFile reports an error for missing keys (e.g. "server" for Claude).
	return _settings.get_value(section, key, DEFAULTS.get(section, {}).get(key, ""))


## Saves the values in the provider's section and makes it the active one.
func save_settings(values: Dictionary, provider: String = "") -> void:
	var section := provider if provider != "" else provider_id()
	_settings.set_value(ACTIVE_SECTION, "provider", section)
	for key: String in values:
		_settings.set_value(section, key, values[key])
	var err := _settings.save(SETTINGS_PATH)
	if err != OK:
		push_error("Brain: can't save %s (%s)." % [SETTINGS_PATH, error_string(err)])
	_apply()
	settings_changed.emit()


func context_tokens() -> int:
	return int(get_setting("context"))


## messages: [{"role": "system"|"user"|"assistant", "content": "…"}]
## options: stream (default true), temperature, max_tokens, skip_reasoning: missing ones come from the settings.
func chat(messages: Array[Dictionary], options: Dictionary = {}) -> BrainRequest:
	var full := options.duplicate()
	if not full.has("temperature"):
		full["temperature"] = float(get_setting("temperature"))
	if not full.has("max_tokens"):
		full["max_tokens"] = int(get_setting("max_reply"))
	if not full.has("skip_reasoning"):
		full["skip_reasoning"] = bool(get_setting("skip_reasoning"))
	return _provider.chat(messages, full)


## The reply text is the list of models, one per line.
func list_models() -> BrainRequest:
	return _provider.list_models()


## Connection test with the given parameters, without saving them.
func probe(provider: String, url: String, model: String, key: String, skip_reasoning: bool) -> BrainRequest:
	var probe_provider := _make_provider(provider, url, model, key)
	add_child(probe_provider)
	var request := probe_provider.chat(
		[{"role": "user", "content": "Rispondi soltanto con la parola: pronto"}],
		# Streaming, so a server that hangs fails after FIRST_TOKEN_TIMEOUT_MS and not after minutes.
		{"stream": true, "temperature": 0.0, "max_tokens": int(get_setting("max_reply", provider)), "skip_reasoning": skip_reasoning})
	request.finished.connect(probe_provider.queue_free)
	return request


## List of models with the given parameters, without saving them.
func probe_models(provider: String, url: String, key: String) -> BrainRequest:
	var probe_provider := _make_provider(provider, url, "", key)
	add_child(probe_provider)
	var request := probe_provider.list_models()
	request.finished.connect(probe_provider.queue_free)
	return request


## A key starting with $ is the name of an environment variable (e.g. $ANTHROPIC_API_KEY).
static func resolve_key(key: String) -> String:
	return OS.get_environment(key.substr(1)) if key.begins_with("$") else key


func _make_provider(provider: String, url: String, model: String, key: String) -> OpenAICompatibleProvider:
	var made: OpenAICompatibleProvider
	match provider:
		"huggingface":
			made = HuggingFaceProvider.new()
		"claude":
			made = ClaudeProvider.new()
		_:
			made = LocalProvider.new()
	made.base_url = url
	made.model = model
	made.api_key = resolve_key(key)
	return made


func _apply() -> void:
	if _provider != null:
		_provider.retire()
	_provider = _make_provider(provider_id(), str(get_setting("url")), str(get_setting("model")), str(get_setting("api_key")))
	_provider.name = "Provider"
	add_child(_provider)
