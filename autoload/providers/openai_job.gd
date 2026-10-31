class_name OpenAIJob
extends RefCounted
## A single HTTP call to an OpenAI-compatible endpoint, without threads:
## the provider calls poll() every frame until it returns true.
## Handles both SSE streaming and whole JSON replies, in the OpenAI format
## or in that of Anthropic's Messages API (dialect = ANTHROPIC).

enum Phase { CONNECTING, REQUESTING, READING, DONE }
enum Dialect { OPENAI, ANTHROPIC }

const CONNECT_TIMEOUT_MS := 5000
## A local model can take a long time to load into memory the first time.
const FIRST_TOKEN_TIMEOUT_MS := 90000
const IDLE_TIMEOUT_MS := 30000

var request: BrainRequest
var dialect := Dialect.OPENAI

var _http := HTTPClient.new()
var _phase := Phase.CONNECTING
var _base_url: String
var _host: String
var _port: int
var _tls: bool
var _path: String
var _method: HTTPClient.Method
var _headers: PackedStringArray
var _body: String
var _streaming: bool
var _model: String

var _started_ms: int
var _last_data_ms: int
var _got_first_data := false
var _buffer := PackedByteArray()
var _raw_body := PackedByteArray()
var _raw_text := ""
## True once the stream has signalled its end ([DONE], message_stop or a finish_reason).
var _saw_end := false
var _on_json: Callable


## on_json, if valid, receives the whole JSON reply (not streaming) and decides the text:
## used for calls like the model list.
func _init(target: BrainRequest, base_url: String, endpoint: String, method: HTTPClient.Method,
		headers: PackedStringArray, body: Dictionary, model: String, on_json: Callable = Callable()) -> void:
	request = target
	_base_url = base_url
	_method = method
	_headers = headers
	_model = model
	_on_json = on_json
	_streaming = bool(body.get("stream", false))
	_body = JSON.stringify(body) if not body.is_empty() else ""
	_parse_url(base_url.trim_suffix("/") + endpoint)
	_started_ms = Time.get_ticks_msec()
	_last_data_ms = _started_ms
	var tls_options: TLSOptions = TLSOptions.client() if _tls else null
	var err := _http.connect_to_host(_host, _port, tls_options)
	if err != OK:
		_fail(_unreachable_message())


## Returns true when the work is over (well or badly).
func poll() -> bool:
	if _phase == Phase.DONE:
		return true
	if request.is_cancel_requested():
		_finish_cancelled()
		return true
	_http.poll()
	var status := _http.get_status()
	var now := Time.get_ticks_msec()
	match _phase:
		Phase.CONNECTING:
			if status == HTTPClient.STATUS_CONNECTED:
				_send()
			elif status in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
				_fail(_unreachable_message())
			elif now - _started_ms > CONNECT_TIMEOUT_MS:
				_fail(_unreachable_message())
		Phase.REQUESTING:
			if status == HTTPClient.STATUS_BODY or (status == HTTPClient.STATUS_CONNECTED and _http.has_response()):
				_phase = Phase.READING
				_last_data_ms = now
			elif status == HTTPClient.STATUS_REQUESTING:
				if now - _last_data_ms > FIRST_TOKEN_TIMEOUT_MS:
					_fail("Il modello non ha risposto entro %d secondi. Forse si sta ancora caricando: riprova tra poco." % (FIRST_TOKEN_TIMEOUT_MS / 1000))
			elif status in [HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_DISCONNECTED]:
				# On some systems the connection looks open even if nobody is listening:
				# the refusal only comes when the request is sent.
				_fail(_unreachable_message())
			else:
				_fail("La connessione con il server del modello si è interrotta.")
		Phase.READING:
			_read(now)
	return _phase == Phase.DONE


func _send() -> void:
	var headers := _headers.duplicate()
	if _body != "":
		headers.append("Content-Type: application/json")
	if _streaming:
		headers.append("Accept: text/event-stream")
	var err := _http.request(_method, _path, headers, _body)
	if err != OK:
		_fail(_unreachable_message())
		return
	_phase = Phase.REQUESTING
	_last_data_ms = Time.get_ticks_msec()


func _read(now: int) -> void:
	var code := _http.get_response_code()
	while _http.get_status() == HTTPClient.STATUS_BODY:
		var chunk := _http.read_response_body_chunk()
		if chunk.is_empty():
			break
		_last_data_ms = now
		if code != 200 or not _streaming:
			_raw_body.append_array(chunk)
		else:
			_buffer.append_array(chunk)
			_consume_sse_lines()
			if _phase == Phase.DONE:
				return
		_http.poll()
	if _http.get_status() == HTTPClient.STATUS_BODY:
		var limit := IDLE_TIMEOUT_MS if _got_first_data else FIRST_TOKEN_TIMEOUT_MS
		if now - _last_data_ms > limit:
			if _got_first_data:
				_fail("La linea è caduta a metà risposta.")
			else:
				_fail("Il modello non ha risposto entro %d secondi. Forse si sta ancora caricando: riprova tra poco." % (limit / 1000))
		return
	# Body finished.
	if code != 200:
		request.http_status = code
		_fail(_http_error_message(code, _raw_body.get_string_from_utf8()))
	elif _streaming:
		# A last line without the final newline is still a line.
		_buffer.append(10)
		_consume_sse_lines()
		if _phase == Phase.DONE:
			return
		if not _saw_end:
			# The connection closed before the end: what arrived is only part of the reply.
			request.truncated = true
		_finish_text()
	else:
		_finish_json(_raw_body.get_string_from_utf8())


func _consume_sse_lines() -> void:
	while true:
		var newline := _buffer.find(10)
		if newline < 0:
			return
		var line := _buffer.slice(0, newline).get_string_from_utf8().strip_edges()
		_buffer = _buffer.slice(newline + 1)
		if not line.begins_with("data:"):
			continue
		var payload := line.substr(5).strip_edges()
		if payload == "[DONE]":
			_saw_end = true
			_finish_text()
			return
		var data: Variant = JSON.parse_string(payload)
		if not data is Dictionary:
			continue
		if data.has("error") or data.get("type", "") == "error":
			_fail(_http_error_message(500, payload))
			return
		var content: Variant = null
		if dialect == Dialect.ANTHROPIC:
			var type := str(data.get("type", ""))
			if type == "message_stop":
				_saw_end = true
				_finish_text()
				return
			if type == "message_delta":
				_note_stop_reason(data.get("delta", {}).get("stop_reason"))
			if type == "content_block_delta":
				content = data.get("delta", {}).get("text")
		else:
			var choices: Array = data.get("choices", [])
			if choices.is_empty():
				continue
			var choice: Dictionary = choices[0]
			_note_stop_reason(choice.get("finish_reason"))
			content = choice.get("delta", {}).get("content")
		_got_first_data = true
		if content is String and content != "":
			_raw_text += content
			request.push_text(ThinkFilter.visible(_raw_text, false))


func _finish_json(body: String) -> void:
	var data: Variant = JSON.parse_string(body)
	if not data is Dictionary:
		_fail("Il server del modello ha mandato una risposta che non capisco.")
		return
	if _on_json.is_valid():
		request.push_text(str(_on_json.call(data)))
		_close()
		request.finish_ok()
		return
	if dialect == Dialect.ANTHROPIC:
		_note_stop_reason(data.get("stop_reason"))
		for block: Variant in data.get("content", []):
			if block is Dictionary and block.get("type", "") == "text":
				_raw_text += str(block.get("text", ""))
	else:
		var choices: Array = data.get("choices", [])
		if not choices.is_empty():
			var choice: Dictionary = choices[0]
			_note_stop_reason(choice.get("finish_reason"))
			var content: Variant = choice.get("message", {}).get("content")
			# content is null when the model only reasoned, or refused.
			_raw_text = content if content is String else ""
	_finish_text()


## finish_reason (OpenAI) or stop_reason (Anthropic): any value means the reply is over,
## and "length" / "max_tokens" means it was cut by the token limit.
func _note_stop_reason(reason: Variant) -> void:
	if not reason is String or reason == "":
		return
	_saw_end = true
	if reason in ["length", "max_tokens"]:
		request.truncated = true


func _finish_text() -> void:
	request.push_text(ThinkFilter.visible(_raw_text, true).strip_edges())
	_close()
	if request.text == "":
		if request.truncated and _streaming and not _saw_end:
			request.finish_error("La linea è caduta a metà risposta.")
		else:
			request.finish_error("L'Entità è rimasta in silenzio. Riprova.")
	else:
		request.finish_ok()


func _finish_cancelled() -> void:
	request.cancelled = true
	request.push_text(ThinkFilter.visible(_raw_text, true).strip_edges())
	_close()
	request.finish_ok()


func _fail(message: String) -> void:
	_close()
	request.finish_error(message)


func _close() -> void:
	_phase = Phase.DONE
	_http.close()


func _unreachable_message() -> String:
	if _host in ["127.0.0.1", "localhost"]:
		return "Il server del modello non risponde su %s. È acceso?" % _base_url
	return "Non riesco a raggiungere %s. Controlla la connessione a internet." % _host


func _http_error_message(code: int, body: String) -> String:
	var detail := body.to_lower()
	if code == 401 or code == 403:
		return "Il server ha rifiutato la chiave di accesso (errore %d)." % code
	if code == 404 or "not found" in detail or "no models loaded" in detail:
		return "Il server non trova il modello «%s». Controlla il nome nelle impostazioni della linea." % _model
	if "context" in detail and ("length" in detail or "exceed" in detail or "overflow" in detail):
		return "Il colloquio è diventato troppo lungo per il contesto del modello. Riduci il contesto nelle impostazioni o termina la sessione."
	var excerpt := body.strip_edges().left(160)
	return "Il server del modello ha risposto con un errore (%d). %s" % [code, excerpt]


func _parse_url(url: String) -> void:
	_tls = url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.left(slash)
	_path = "/" if slash < 0 else rest.substr(slash)
	var colon := host_port.rfind(":")
	if colon > 0:
		_host = host_port.left(colon)
		_port = int(host_port.substr(colon + 1))
	else:
		_host = host_port
		_port = 443 if _tls else 80
	# Godot resolves "localhost" to IPv6, but LM Studio and other servers listen only on IPv4.
	if _host == "localhost":
		_host = "127.0.0.1"
