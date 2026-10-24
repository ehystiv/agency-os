class_name LocalProvider
extends OpenAICompatibleProvider
## Modello che gira su questo computer: Ollama, LM Studio o llama.cpp server.

## Indirizzi standard dei server locali più comuni.
const PRESETS: Dictionary[String, String] = {
	"lmstudio": "http://localhost:1234/v1",
	"ollama": "http://localhost:11434/v1",
	"llamacpp": "http://localhost:8080/v1",
}
const PRESET_LABELS: Dictionary[String, String] = {
	"lmstudio": "LM Studio",
	"ollama": "Ollama",
	"llamacpp": "llama.cpp server",
	"personalizzato": "Personalizzato",
}
