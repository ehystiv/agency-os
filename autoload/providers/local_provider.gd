class_name LocalProvider
extends OpenAICompatibleProvider
## A model running on this computer: Ollama, LM Studio or llama.cpp server.

## Standard addresses of the most common local servers.
const PRESETS: Dictionary[String, String] = {
	"lmstudio": "http://localhost:1234/v1",
	"ollama": "http://localhost:11434/v1",
	"llamacpp": "http://localhost:8080/v1",
}
const PRESET_LABELS: Dictionary[String, String] = {
	"lmstudio": "LM Studio",
	"ollama": "Ollama",
	"llamacpp": "llama.cpp server",
	"custom": "Personalizzato",
}
