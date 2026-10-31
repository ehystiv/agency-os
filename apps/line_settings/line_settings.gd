extends AppContent
## Line settings: provider (local, Hugging Face, Claude), model and parameters,
## with a connection test. Each provider remembers its own values.

const CUSTOM := "custom"

var _presets: Array[String] = []
var _testing := false
## Provider shown in the fields (it becomes the active one only on Save).
var _shown_provider := ""

@onready var _provider: OptionButton = %Provider
@onready var _server_row: Array[Control] = [%ServerLabel, %Server]
@onready var _key_row: Array[Control] = [%KeyLabel, %Key]
@onready var _key: LineEdit = %Key
@onready var _server: OptionButton = %Server
@onready var _url: LineEdit = %Url
@onready var _model: LineEdit = %Model
@onready var _list: Button = %ListModels
@onready var _models_popup: PopupMenu = %ModelsPopup
@onready var _temperature: HSlider = %Temperature
@onready var _temperature_value: Label = %TemperatureValue
@onready var _context: SpinBox = %Context
@onready var _max_reply: SpinBox = %MaxReply
@onready var _skip_reasoning: CheckBox = %SkipReasoning
@onready var _report: Label = %Report
@onready var _test: Button = %Test
@onready var _save: Button = %Save
@onready var _saved: Label = %Saved


func _ready() -> void:
	for id in Brain.PROVIDERS:
		_provider.add_item(Brain.PROVIDER_LABELS[id])
	_provider.item_selected.connect(func(index: int) -> void: _load(Brain.PROVIDERS[index]))
	for key in LocalProvider.PRESET_LABELS:
		_presets.append(key)
		_server.add_item(LocalProvider.PRESET_LABELS[key])
	_server.item_selected.connect(_on_server_selected)
	_url.text_changed.connect(_on_url_changed)
	_list.pressed.connect(_on_list_pressed)
	_models_popup.id_pressed.connect(func(id: int) -> void: _model.text = _models_popup.get_item_text(id))
	_temperature.value_changed.connect(func(v: float) -> void: _temperature_value.text = "%.2f" % v)
	_test.pressed.connect(_on_test_pressed)
	_save.pressed.connect(_on_save_pressed)
	for field: LineEdit in [_url, _model, _key]:
		field.text_changed.connect(func(_t: String) -> void: _saved.hide())
	_load()


func on_opened(_args: Dictionary = {}) -> void:
	# Reopening (e.g. from the taskbar) keeps what was typed and not yet saved.
	if not _is_modified():
		_load()


## True if the fields differ from the saved settings of the provider shown.
func _is_modified() -> bool:
	var p := _shown_provider
	if p == "":
		return false
	if p == "local" and _server.selected != maxi(0, _presets.find(str(Brain.get_setting("server", p)))):
		return true
	return _url.text != str(Brain.get_setting("url", p)) \
			or _model.text != str(Brain.get_setting("model", p)) \
			or _key.text != str(Brain.get_setting("api_key", p)) \
			or absf(_temperature.value - float(Brain.get_setting("temperature", p))) > _temperature.step \
			or int(_context.value) != int(Brain.get_setting("context", p)) \
			or int(_max_reply.value) != int(Brain.get_setting("max_reply", p)) \
			or _skip_reasoning.button_pressed != bool(Brain.get_setting("skip_reasoning", p))


func _load(provider: String = "") -> void:
	_shown_provider = provider if provider != "" else Brain.provider_id()
	var p := _shown_provider
	_provider.select(Brain.PROVIDERS.find(p))
	var local := p == "local"
	for node in _server_row:
		node.visible = local
	for node in _key_row:
		node.visible = not local
	_server.select(maxi(0, _presets.find(str(Brain.get_setting("server", p)))))
	_url.text = str(Brain.get_setting("url", p))
	_model.text = str(Brain.get_setting("model", p))
	_key.text = str(Brain.get_setting("api_key", p))
	_temperature.value = float(Brain.get_setting("temperature", p))
	_temperature_value.text = "%.2f" % _temperature.value
	_context.value = int(Brain.get_setting("context", p))
	_max_reply.value = int(Brain.get_setting("max_reply", p))
	_skip_reasoning.button_pressed = bool(Brain.get_setting("skip_reasoning", p))
	_saved.hide()


func _on_server_selected(index: int) -> void:
	var key := _presets[index]
	if LocalProvider.PRESETS.has(key):
		_url.text = LocalProvider.PRESETS[key]
	_saved.hide()


## A hand-typed address that isn't a preset switches to "custom".
func _on_url_changed(text: String) -> void:
	var matching := CUSTOM
	for key in LocalProvider.PRESETS:
		if LocalProvider.PRESETS[key] == text.strip_edges():
			matching = key
	_server.select(_presets.find(matching))


func _on_list_pressed() -> void:
	_list.disabled = true
	var request := Brain.probe_models(_shown_provider, _url.text.strip_edges(), _key.text.strip_edges())
	await request.finished
	_list.disabled = false
	_models_popup.clear()
	if not request.ok():
		_report.text = "[!!] " + request.error
		return
	var ids := request.text.split("\n", false)
	if ids.is_empty():
		_report.text = "[!!] Il server non ha nessun modello disponibile."
		return
	for id in ids:
		_models_popup.add_item(id)
	var rect := _list.get_global_rect()
	_models_popup.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y)), Vector2i(int(rect.size.x), 0)))


func _on_test_pressed() -> void:
	if _testing:
		return
	_testing = true
	_test.disabled = true
	var url := _url.text.strip_edges()
	var model := _model.text.strip_edges()
	var lines: PackedStringArray = ["Contatto %s…" % url]
	_report.text = "\n".join(lines)
	var models := Brain.probe_models(_shown_provider, url, _key.text.strip_edges())
	await models.finished
	lines.remove_at(0)
	if not models.ok():
		lines.append("[!!] " + models.error)
		_finish_test(lines)
		return
	var ids := models.text.split("\n", false)
	lines.append("[OK] Server raggiunto, %d modelli disponibili." % ids.size())
	if not ids.is_empty() and not model in ids:
		lines.append("[??] «%s» non è nell'elenco del server: controlla il nome." % model)
	lines.append("Chiedo una risposta a «%s»… (il primo caricamento può richiedere tempo)" % model)
	_report.text = "\n".join(lines)
	var started := Time.get_ticks_msec()
	var reply := Brain.probe(_shown_provider, url, model, _key.text.strip_edges(), _skip_reasoning.button_pressed)
	await reply.finished
	lines.remove_at(lines.size() - 1)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	if reply.ok():
		lines.append("[OK] «%s» risponde in %.1f s: «%s»." % [model, seconds, reply.text.strip_edges().left(40)])
	else:
		lines.append("[!!] " + reply.error)
	_finish_test(lines)


func _finish_test(lines: PackedStringArray) -> void:
	_report.text = "\n".join(lines)
	_testing = false
	_test.disabled = false


func _on_save_pressed() -> void:
	Brain.save_settings({
		"server": _presets[_server.selected],
		"api_key": _key.text.strip_edges(),
		"url": _url.text.strip_edges(),
		"model": _model.text.strip_edges(),
		"temperature": snappedf(_temperature.value, 0.01),
		"context": int(_context.value),
		"max_reply": int(_max_reply.value),
		"skip_reasoning": _skip_reasoning.button_pressed,
	}, _shown_provider)
	_saved.show()
