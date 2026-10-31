extends AppContent
## Online help, like Windows 98's HTML Help: Contents, Index and Search on the left,
## the topic on the right. Opened with {"topic": id} (an app's id) on that topic.

const DATA_PATH := "res://data/help.json"
const TITLE_SIZE := 20

var _chapters: Array = []
## [{id, chapter, title, keywords, body}]
var _topics: Array = []
var _shown := ""

@onready var _tabs: TabContainer = %Tabs
@onready var _contents: Tree = %ContentsTree
@onready var _index_text: LineEdit = %IndexText
@onready var _index: Tree = %IndexList
@onready var _search_text: LineEdit = %SearchText
@onready var _results: Tree = %SearchList
@onready var _page: RichTextLabel = %PageText


func _ready() -> void:
	_load()
	for i in 3:
		_tabs.set_tab_title(i, tr(["Sommario", "Indice", "Cerca"][i]))
	_build_contents()
	_fill_index("")
	for tree: Tree in [_contents, _index, _results]:
		tree.item_selected.connect(func() -> void: _show_selected(tree))
	_index_text.text_changed.connect(_fill_index)
	_index_text.text_submitted.connect(func(_t: String) -> void: _show_selected(_index))
	_search_text.text_submitted.connect(func(_t: String) -> void: _search())
	%SearchButton.pressed.connect(_search)


func on_opened(args: Dictionary = {}) -> void:
	var wanted := str(args.get("topic", ""))
	if wanted != "" and _find(wanted) != null:
		_tabs.current_tab = 0
		_select_in_contents(wanted)
	elif _shown == "":
		_select_in_contents("intro")


func _load() -> void:
	var file := FileAccess.open(Locale.data_path(DATA_PATH), FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		_chapters = data.get("chapters", [])
		_topics = data.get("topics", [])


func _build_contents() -> void:
	var root := _contents.create_item()
	var books: Array[TreeItem] = []
	for chapter: String in _chapters:
		var book := _contents.create_item(root)
		book.set_text(0, chapter)
		book.set_selectable(0, false)
		books.append(book)
	for topic: Dictionary in _topics:
		var item := _contents.create_item(books[clampi(int(topic.chapter), 0, books.size() - 1)])
		item.set_text(0, str(topic.title))
		item.set_metadata(0, topic.id)


## Every keyword (and every title) that starts with the text, sorted, each pointing to its topic.
func _fill_index(text: String) -> void:
	var entries: Array[Array] = []
	var wanted := text.strip_edges()
	for topic: Dictionary in _topics:
		for word: String in [str(topic.title)] + Array(topic.get("keywords", [])):
			if wanted == "" or word.to_lower().begins_with(wanted.to_lower()):
				entries.append([word, topic.id])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]).naturalnocasecmp_to(str(b[0])) < 0)
	_fill_list(_index, entries)
	if wanted != "" and not entries.is_empty():
		_index.get_root().get_first_child().select(0)


## Topics containing all the words typed, in their title, keywords or text.
func _search() -> void:
	var words := _search_text.text.strip_edges().split(" ", false)
	var entries: Array[Array] = []
	if not words.is_empty():
		for topic: Dictionary in _topics:
			var haystack := "%s %s %s" % [topic.title, " ".join(topic.get("keywords", [])), topic.body]
			if Array(words).all(func(word: String) -> bool: return haystack.containsn(word)):
				entries.append([str(topic.title), topic.id])
	_fill_list(_results, entries)
	if entries.is_empty():
		var item := _results.create_item(_results.get_root())
		item.set_text(0, tr("Nessun argomento trovato."))
		item.set_selectable(0, false)


func _fill_list(tree: Tree, entries: Array[Array]) -> void:
	tree.clear()
	var root := tree.create_item()
	for entry in entries:
		var item := tree.create_item(root)
		item.set_text(0, str(entry[0]))
		item.set_metadata(0, entry[1])


func _show_selected(tree: Tree) -> void:
	var item := tree.get_selected()
	if item != null and item.get_metadata(0) != null:
		_show(str(item.get_metadata(0)))


func _select_in_contents(id: String) -> void:
	var item := _contents.get_root().get_first_child()
	while item != null:
		for child in item.get_children():
			if str(child.get_metadata(0)) == id:
				child.select(0)
				# Deferred: on the first opening the tree has no size yet.
				_contents.scroll_to_item.call_deferred(child, true)
				_show(id)
				return
		item = item.get_next()


func _show(id: String) -> void:
	var topic: Variant = _find(id)
	if topic == null:
		return
	_shown = id
	_page.text = "[font_size=%d][b]%s[/b][/font_size]\n\n%s" % [TITLE_SIZE, topic.title, topic.body]
	_page.scroll_to_line(0)


func _find(id: String) -> Variant:
	for topic: Dictionary in _topics:
		if topic.id == id:
			return topic
	return null
