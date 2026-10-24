class_name BrainRequest
extends RefCounted
## Una richiesta al modello. Ogni richiesta ha i suoi segnali,
## così lo streaming della chat e un riassunto in parallelo non si mescolano.
## Si chiude sempre con completed oppure failed, poi finished.

## piece è il testo nuovo; text contiene tutto il visibile finora.
signal chunk_received(piece: String)
signal completed(text: String)
## message è già pronto da mostrare, in italiano.
signal failed(message: String)
signal finished

## Testo visibile ricevuto finora, senza i blocchi di ragionamento.
var text: String = ""
var error: String = ""
## Codice HTTP dell'errore, 0 se l'errore non viene dal server (spento, timeout…).
var http_status: int = 0
## Vero se la risposta è stata fermata a metà: text contiene la parte arrivata.
var cancelled: bool = false
var is_done: bool = false

var _cancel_requested: bool = false


func cancel() -> void:
	_cancel_requested = true


func is_cancel_requested() -> bool:
	return _cancel_requested


func ok() -> bool:
	return is_done and error == ""


## Usate solo dai provider.
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


## Chi ascolta lo streaming spesso cattura la richiesta stessa in una lambda:
## scollegare tutto alla fine rompe il ciclo e la richiesta viene liberata.
func _disconnect_all() -> void:
	for sig: Signal in [chunk_received, completed, failed, finished]:
		for connection: Dictionary in sig.get_connections():
			sig.disconnect(connection.callable)
