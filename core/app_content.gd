class_name AppContent
extends MarginContainer
## Base per il contenuto di ogni app. Parla con la sua finestra solo tramite segnali.

@warning_ignore("unused_signal")
signal title_changed(title: String)
@warning_ignore("unused_signal")
## action, se non è vuota, è {"app": id, "args": {...}}: l'app da aprire cliccando il fumetto.
signal notification_requested(title: String, text: String, action: Dictionary)
## Chiede di aprire un'altra app; args arriva a on_opened() di quell'app,
## es. &"linea", {"colloquio": 3}.
@warning_ignore("unused_signal")
signal app_requested(id: StringName, args: Dictionary)
## Comando di sistema per la scrivania, es. &"riordina_finestre", &"allinea_icone".
@warning_ignore("unused_signal")
signal command_requested(command: StringName)
## L'app chiede di chiudere la propria finestra (es. ESCI nel prompt dei comandi).
@warning_ignore("unused_signal")
signal close_requested

## Assegnata dalla finestra prima che il contenuto entri nell'albero.
var app: AppInfo
## Vero quando la finestra dell'app è in primo piano (aggiornato dalla finestra).
var window_active: bool = false


## Chiamata a ogni apertura, anche quando la finestra torna da ridotta.
## args viene da chi ha chiesto l'apertura; vuoto per icone, menu Start e barra.
func on_opened(_args: Dictionary = {}) -> void:
	pass


## Chiamata prima che la finestra venga distrutta.
func on_closed() -> void:
	pass
