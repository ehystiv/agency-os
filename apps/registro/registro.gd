extends AppContent
## Visualizzatore eventi di AgencyOS, in sola lettura.

const SEVERITY_ICONS := {
	"i": preload("res://ui/icons/evento_info.svg"),
	"w": preload("res://ui/icons/evento_avviso.svg"),
	"e": preload("res://ui/icons/evento_errore.svg"),
}
const SEVERITY_NAMES := {"i": "Informazione", "w": "Avviso", "e": "Errore"}

@onready var _tree: Tree = %Events
@onready var _count: Label = %Count


func _ready() -> void:
	_tree.set_column_title(0, "Data e ora")
	_tree.set_column_title(1, "Origine")
	_tree.set_column_title(2, "Evento")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 118)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 140)
	for column in 3:
		_tree.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)
	Campaign.colloqui_changed.connect(_refresh)
	Campaign.colloquio_updated.connect(func(_c: Colloquio) -> void: _refresh())
	Campaign.correspondence.mail_changed.connect(_refresh)
	Campaign.correspondence.files_changed.connect(_refresh)
	_refresh()


func on_opened(_args: Dictionary = {}) -> void:
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree() and _tree.get_root() != null:
		return
	_tree.clear()
	var root := _tree.create_item()
	var events := EventLog.collect()
	for event in events:
		var row := _tree.create_item(root)
		row.set_text(0, "%s %s" % [ItalianDate.numeric(event.ora), ItalianDate.time(event.ora)])
		row.set_icon(1, SEVERITY_ICONS[event.gravita])
		row.set_text(1, event.origine)
		row.set_tooltip_text(1, SEVERITY_NAMES[event.gravita])
		row.set_text(2, event.testo)
		row.set_tooltip_text(2, event.testo)
	_count.text = "%d %s" % [events.size(), "evento" if events.size() == 1 else "eventi"]
