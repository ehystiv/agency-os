extends AppContent
## Line settings: provider (local, Hugging Face, Claude), model and parameters,
## with a connection test. Each provider remembers its own values.

const CUSTOM := "custom"

var _presets: Array[String] = []
var _testing := false
## Provider shown in the fields (it becomes the active one only on Save).
var _shown_provider := ""
## Every model the server listed, sorted; the popup shows the ones matching the search.
var _all_models: Array[String] = []

@onready var _provider: OptionButton = %Provider
@onready var _server_row: Array[Control] = [%ServerLabel, %Server]
@onready var _key_row: Array[Control] = [%KeyLabel, %Key]
@onready var _key: LineEdit = %Key
@onready var _server: OptionButton = %Server
@onready var _url: LineEdit = %Url
@onready var _model: LineEdit = %Model
@onready var _list: Button = %ListModels
@onready var _models_popup: PopupPanel = %ModelsPopup
@onready var _model_search: LineEdit = %ModelSearch
@onready var _model_list: Tree = %ModelList
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
		_provider.add_item(tr(Brain.PROVIDER_LABELS[id]))
	_provider.item_selected.connect(func(index: int) -> void: _load(Brain.PROVIDERS[index]))
	for key in LocalProvider.PRESET_LABELS:
		_presets.append(key)
		_server.add_item(tr(LocalProvider.PRESET_LABELS[key]))
	_server.item_selected.connect(_on_server_selected)
	_url.text_changed.connect(_on_url_changed)
	_list.pressed.connect(_on_list_pressed)
	_model_search.text_changed.connect(_fill_models)
	_model_search.text_submitted.connect(func(_t: String) -> void: _pick_model(_model_list.get_selected()))
	_model_search.gui_input.connect(_on_model_search_input)
	_model_list.item_activated.connect(func() -> void: _pick_model(_model_list.get_selected()))
	_model_list.item_mouse_selected.connect(func(_p: Vector2, _b: int) -> void: _pick_model(_model_list.get_selected()))
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
	if not request.ok():
		_report.text = "[!!] " + request.error
		return
	_all_models.assign(request.text.split("\n", false))
	if _all_models.is_empty():
		_report.text = tr("[!!] Il server non ha nessun modello disponibile.")
		return
	# Servers list them in their own order.
	_all_models.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	_model_search.text = ""
	_fill_models("")
	# As wide as the model field and its button, right below them.
	var row := _model.get_parent() as Control
	var rect := row.get_global_rect()
	_models_popup.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y)), Vector2i(maxi(int(rect.size.x), 320), 300)))
	_model_search.grab_focus()


## Arrow keys in the search box move the selection in the list below.
func _on_model_search_input(event: InputEvent) -> void:
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step == 0:
		return
	_model_search.accept_event()
	var item := _model_list.get_selected()
	if item == null:
		return
	var next := item.get_next_visible() if step > 0 else item.get_prev_visible()
	if next:
		next.select(0)
		_model_list.scroll_to_item(next)


## Shows the models whose name contains the filter, the first one selected.
func _fill_models(filter: String) -> void:
	_model_list.clear()
	var root := _model_list.create_item()
	var needle := filter.strip_edges()
	for id in _all_models:
		if needle == "" or id.containsn(needle):
			_model_list.create_item(root).set_text(0, id)
	var first := root.get_first_child()
	if first:
		first.select(0)
		_model_list.scroll_to_item(first)


func _pick_model(item: TreeItem) -> void:
	if item == null:
		return
	_model.text = item.get_text(0)
	_models_popup.hide()


func _on_test_pressed() -> void:
	if _testing:
		return
	_testing = true
	_test.disabled = true
	var url := _url.text.strip_edges()
	var model := _model.text.strip_edges()
	var lines: PackedStringArray = [tr("Contatto %s…") % url]
	_report.text = "\n".join(lines)
	var models := Brain.probe_models(_shown_provider, url, _key.text.strip_edges())
	await models.finished
	lines.remove_at(0)
	if not models.ok():
		lines.append("[!!] " + models.error)
		_finish_test(lines)
		return
	var ids := models.text.split("\n", false)
	lines.append(tr("[OK] Server raggiunto, %d modelli disponibili.") % ids.size())
	if not ids.is_empty() and not model in ids:
		lines.append(tr("[??] «%s» non è nell'elenco del server: controlla il nome.") % model)
	lines.append(tr("Chiedo una risposta a «%s»… (il primo caricamento può richiedere tempo)") % model)
	_report.text = "\n".join(lines)
	var started := Time.get_ticks_msec()
	var reply := Brain.probe(_shown_provider, url, model, _key.text.strip_edges(), _skip_reasoning.button_pressed)
	await reply.finished
	lines.remove_at(lines.size() - 1)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	if reply.ok():
		lines.append(tr("[OK] «%s» risponde in %.1f s: «%s».") % [model, seconds, reply.text.strip_edges().left(40)])
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
