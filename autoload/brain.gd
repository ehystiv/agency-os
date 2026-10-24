extends Node
## Interfaccia unica verso il modello linguistico.
## Ogni chiamata restituisce una BrainRequest con i propri segnali (pezzi di testo, fine, errore).
## Le impostazioni stanno in user://config/modello.cfg, una sezione per provider
## più [linea] provider = quello attivo. Si può modificare anche a mano.

signal settings_changed

const SETTINGS_PATH := "user://config/modello.cfg"
const ACTIVE_SECTION := "linea"
const PROVIDERS: Array[String] = ["locale", "huggingface", "claude"]
const PROVIDER_LABELS: Dictionary[String, String] = {"locale": "Locale", "huggingface": "Hugging Face", "claude": "Claude (Anthropic)"}
const DEFAULTS: Dictionary[String, Dictionary] = {
	"locale": {
		"server": "lmstudio",
		"url": "http://localhost:1234/v1",
		"modello": "qwen3.5-9b-mlx",
		"chiave": "",
		"temperatura": 0.9,
		## Token di contesto del modello: decide quanta conversazione entra nel prompt.
		"contesto": 8192,
		## Limite di token per risposta, ragionamento compreso. 0 = nessun limite.
		"max_risposta": 1024,
		## Fa saltare il ragionamento ai modelli che lo fanno (Qwen e simili): risposte molto più rapide.
		"salta_ragionamento": true,
	},
	"huggingface": {
		"url": HuggingFaceProvider.ROUTER_URL,
		"modello": "meta-llama/Llama-3.3-70B-Instruct",
		"chiave": "",
		"temperatura": 0.9,
		"contesto": 32768,
		"max_risposta": 1024,
		"salta_ragionamento": false,
	},
	"claude": {
		"url": ClaudeProvider.API_URL,
		"modello": "claude-sonnet-5-5",
		"chiave": "",
		"temperatura": 0.9,
		"contesto": 131072,
		"max_risposta": 1024,
		"salta_ragionamento": false,
	},
}

var _settings := ConfigFile.new()
var _provider: OpenAICompatibleProvider


func _ready() -> void:
	if _settings.load(SETTINGS_PATH) != OK:
		_settings.set_value(ACTIVE_SECTION, "provider", "locale")
		for key: String in DEFAULTS.locale:
			_settings.set_value("locale", key, DEFAULTS.locale[key])
		_settings.save(SETTINGS_PATH)
	_apply()


func provider_id() -> String:
	var id := str(_settings.get_value(ACTIVE_SECTION, "provider", "locale"))
	return id if id in PROVIDERS else "locale"


## Impostazione del provider indicato (vuoto = quello attivo).
func get_setting(key: String, provider: String = "") -> Variant:
	var section := provider if provider != "" else provider_id()
	# Senza un predefinito non nullo ConfigFile segnala errore per le chiavi assenti (es. "server" per Claude).
	return _settings.get_value(section, key, DEFAULTS.get(section, {}).get(key, ""))


## Salva i valori nella sezione del provider e lo rende quello attivo.
func save_settings(values: Dictionary, provider: String = "") -> void:
	var section := provider if provider != "" else provider_id()
	_settings.set_value(ACTIVE_SECTION, "provider", section)
	for key: String in values:
		_settings.set_value(section, key, values[key])
	var err := _settings.save(SETTINGS_PATH)
	if err != OK:
		push_error("Brain: impossibile salvare %s (%s)." % [SETTINGS_PATH, error_string(err)])
	_apply()
	settings_changed.emit()


func context_tokens() -> int:
	return int(get_setting("contesto"))


## messages: [{"role": "system"|"user"|"assistant", "content": "…"}]
## options: stream (default true), temperature, max_tokens, skip_reasoning: se mancano valgono le impostazioni.
func chat(messages: Array[Dictionary], options: Dictionary = {}) -> BrainRequest:
	var full := options.duplicate()
	if not full.has("temperature"):
		full["temperature"] = float(get_setting("temperatura"))
	if not full.has("max_tokens"):
		full["max_tokens"] = int(get_setting("max_risposta"))
	if not full.has("skip_reasoning"):
		full["skip_reasoning"] = bool(get_setting("salta_ragionamento"))
	return _provider.chat(messages, full)


## Il testo della risposta è l'elenco dei modelli, uno per riga.
func list_models() -> BrainRequest:
	return _provider.list_models()


## Prova di connessione con i parametri indicati, senza salvarli.
func probe(provider: String, url: String, model: String, key: String, skip_reasoning: bool) -> BrainRequest:
	var probe_provider := _make_provider(provider, url, model, key)
	add_child(probe_provider)
	var request := probe_provider.chat(
		[{"role": "user", "content": "Rispondi soltanto con la parola: pronto"}],
		{"stream": false, "temperature": 0.0, "max_tokens": int(get_setting("max_risposta", provider)), "skip_reasoning": skip_reasoning})
	request.finished.connect(probe_provider.queue_free)
	return request


## Elenco dei modelli con i parametri indicati, senza salvarli.
func probe_models(provider: String, url: String, key: String) -> BrainRequest:
	var probe_provider := _make_provider(provider, url, "", key)
	add_child(probe_provider)
	var request := probe_provider.list_models()
	request.finished.connect(probe_provider.queue_free)
	return request


## Una chiave che comincia con $ è il nome di una variabile d'ambiente (es. $ANTHROPIC_API_KEY).
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
	_provider = _make_provider(provider_id(), str(get_setting("url")), str(get_setting("modello")), str(get_setting("chiave")))
	_provider.name = "Provider"
	add_child(_provider)
