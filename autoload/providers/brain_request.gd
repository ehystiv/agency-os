class_name BrainRequest
extends RefCounted
## A request to the model. Each request has its own signals,
## so the chat streaming and a parallel summary don't get mixed up.
## It always ends with completed or failed, then finished.

## piece is the new text; text holds everything visible so far.
signal chunk_received(piece: String)
signal completed(text: String)
## message is ready to be shown, in Italian.
signal failed(message: String)
signal finished

## Visible text received so far, without the reasoning blocks.
var text: String = ""
var error: String = ""
## HTTP status of the error, 0 if the error doesn't come from the server (off, timeout…).
var http_status: int = 0
## True if the reply was stopped halfway: text holds the part that arrived.
var cancelled: bool = false
## True if the reply is incomplete: the server hit the token limit or the stream ended early.
var truncated: bool = false
var is_done: bool = false

var _cancel_requested: bool = false


func cancel() -> void:
	_cancel_requested = true


func is_cancel_requested() -> bool:
	return _cancel_requested


func ok() -> bool:
	return is_done and error == ""


## Used only by the providers.
func push_text(visible_text: String) -> void:
	if visible_text == text:
		return
	var piece := visible_text.substr(text.length()) if visible_text.begins_with(text) else ""
	text = visible_text
	chunk_received.emit(piece)


func finish_ok() -> void:
	if is_done:
		return
	is_done = true
	completed.emit(text)
	finished.emit()
	_disconnect_all()


func finish_error(message: String) -> void:
	if is_done:
		return
	is_done = true
	error = message
	failed.emit(message)
	finished.emit()
	_disconnect_all()


## Streaming listeners often capture the request itself in a lambda:
## disconnecting everything at the end breaks the cycle and the request is freed.
func _disconnect_all() -> void:
	for sig: Signal in [chunk_received, completed, failed, finished]:
		for connection: Dictionary in sig.get_connections():
			sig.disconnect(connection.callable)
