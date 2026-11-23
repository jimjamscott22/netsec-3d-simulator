class_name LogViewer
extends CanvasLayer
## The SOC monitor's log viewer (SPEC §8.3, task 2.7). A full-screen window with
## the mission's log files on the left and the selected file on the right: line
## numbers (report evidence cites them), a scrolling monospace view, and a
## filter box that keeps the lines containing the text and highlights each match.
##
## It owns no network truth. The file list comes from `Sim.scenario_view().logs()`
## and the lines from `Sim.query_logs`, so a mission needs nothing here.
##
## Keys: type to filter, Up/Down pick the previous or next file, PageUp/PageDown
## scroll, Esc closes.

signal opened
signal closed

const FONT_NAMES: PackedStringArray = ["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Menlo", "monospace"]
const FONT_SIZE: int = 15
const BACKGROUND: Color = Color(0.03, 0.04, 0.05, 0.97)
const TEXT_COLOR: Color = Color(0.80, 0.92, 0.82)
const DIM_COLOR: Color = Color(0.55, 0.62, 0.58)
const MATCH_COLOR: String = "#101010"
const MATCH_BACKGROUND: String = "#e8c547"
const LIST_WIDTH: float = 340.0
const TITLE: String = "SOC monitor  ·  log viewer"
const FOOTER: String = "Type to filter · ↑/↓ file · PgUp/PgDn scroll · Esc close"
const NO_FILES: String = "No log files in this mission."

## `{source: String, file: String, lines: int}` for each file, in list order.
var _files: Array[Dictionary] = []
var _selected: int = -1
var _filter_text: String = ""
var _shown: Array[LogLine] = []

var _list: ItemList
var _filter: LineEdit
var _status: Label
var _output: RichTextLabel


func _ready() -> void:
	layer = 10
	_build()
	hide()
	Sim.scenario_loaded.connect(_on_scenario_loaded)


## Esc is caught before the GUI so it works wherever the focus is.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- public ---------------------------------------------------------------------


## Opens the viewer on the first file. Returns false (and stays closed) when the
## mission has no logs.
func open() -> bool:
	var scenario: ScenarioView = Sim.scenario_view()
	if scenario == null or scenario.logs().is_empty():
		return false
	_files.clear()
	_files.assign(scenario.logs())
	_list.clear()
	for entry: Dictionary in _files:
		_list.add_item("%s\n%s  (%d lines)" % [entry["source"], entry["file"], entry["lines"]])
	_filter.clear()
	_filter_text = ""
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	select_file(0)
	_filter.grab_focus()
	opened.emit()
	return true


func close() -> void:
	if not visible:
		return
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func is_open() -> bool:
	return visible


func file_count() -> int:
	return _files.size()


## Shows file `index` of the list, keeping the filter text.
func select_file(index: int) -> void:
	if index < 0 or index >= _files.size():
		return
	_selected = index
	_list.select(index)
	_list.ensure_current_is_visible()
	_refresh()


## `{source, file, lines}` of the file on show, or an empty dictionary.
func selected_file() -> Dictionary:
	if _selected < 0 or _selected >= _files.size():
		return {}
	return _files[_selected]


## Keeps only the lines containing `text`, ignoring case. Empty shows every line.
func set_filter_text(text: String) -> void:
	_filter_text = text
	if _filter.text != text:
		_filter.text = text
	_refresh()


func filter_text() -> String:
	return _filter_text


## Line numbers (as in the file) of the lines on show.
func shown_line_numbers() -> Array[int]:
	var numbers: Array[int] = []
	for line: LogLine in _shown:
		numbers.append(line.number())
	return numbers


## "12 of 240 lines", or a note when nothing matches.
func status_text() -> String:
	return _status.text


## The view as plain text, one line per row: the line number, then the line.
func output_text() -> String:
	return _output.get_parsed_text()


## Handles a key the way the window does, for tests too. True when it was used.
func handle_key(key: InputEventKey) -> bool:
	if not key.pressed:
		return false
	match key.keycode:
		KEY_ESCAPE:
			close()
		KEY_UP:
			select_file(maxi(_selected - 1, 0))
		KEY_DOWN:
			select_file(mini(_selected + 1, _files.size() - 1))
		KEY_PAGEUP:
			_scroll(-1)
		KEY_PAGEDOWN:
			_scroll(1)
		_:
			return false
	return true


## `text` as BBCode with every case-insensitive occurrence of `needle` marked.
## Square brackets in the log text are escaped, so a line can never inject markup.
static func highlight(text: String, needle: String) -> String:
	if needle.is_empty():
		return _escape(text)
	var out: String = ""
	var from: int = 0
	while true:
		var at: int = text.findn(needle, from)
		if at < 0:
			break
		out += _escape(text.substr(from, at - from))
		out += "[bgcolor=%s][color=%s]%s[/color][/bgcolor]" % [
			MATCH_BACKGROUND, MATCH_COLOR, _escape(text.substr(at, needle.length()))
		]
		from = at + needle.length()
	return out + _escape(text.substr(from))


# --- internals ------------------------------------------------------------------


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _refresh() -> void:
	var file: Dictionary = selected_file()
	_shown.clear()
	_output.clear()
	if file.is_empty():
		_status.text = NO_FILES
		return
	var total: int = file["lines"]
	# One filter criterion: the text as typed, ignoring case (an empty one keeps all).
	_shown.assign(Sim.query_logs(file["source"], file["file"], LogFilter.contains_ignore_case(_filter_text)))
	var width: int = str(maxi(total, 1)).length()
	for line: LogLine in _shown:
		_output.append_text("[color=#8a9a90]%s[/color]  %s\n" % [
			str(line.number()).lpad(width), highlight(line.full_text(), _filter_text)
		])
	if _shown.is_empty():
		_status.text = "%s  ·  no lines contain \"%s\"" % [file["file"], _filter_text]
	else:
		_status.text = "%s  ·  %d of %d lines" % [file["file"], _shown.size(), total]
	_output.scroll_to_line(0)


func _scroll(pages: int) -> void:
	var bar: VScrollBar = _output.get_v_scroll_bar()
	bar.value = clampf(bar.value + pages * bar.page, bar.min_value, bar.max_value)


func _on_scenario_loaded(_scenario_id: String) -> void:
	close()


func _on_filter_changed(text: String) -> void:
	set_filter_text(text)


func _on_filter_gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and handle_key(key):
		_filter.accept_event()


func _on_file_picked(index: int) -> void:
	select_file(index)
	_filter.grab_focus()


func _build() -> void:
	var font := SystemFont.new()
	font.font_names = FONT_NAMES
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_color("default_color", "RichTextLabel", TEXT_COLOR)
	theme.set_color("font_color", "LineEdit", TEXT_COLOR)
	theme.set_color("caret_color", "LineEdit", TEXT_COLOR)
	theme.set_color("font_color", "ItemList", TEXT_COLOR)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)

	var root := Panel.new()
	root.name = "Root"
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = BACKGROUND
	root.add_theme_stylebox_override("panel", bg)
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	root.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = TITLE
	title.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(title)
	column.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	_list = ItemList.new()
	_list.name = "Files"
	_list.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_list.auto_height = false
	_list.focus_mode = Control.FOCUS_NONE
	_list.item_selected.connect(_on_file_picked)
	body.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)

	var filter_row := HBoxContainer.new()
	right.add_child(filter_row)
	var prompt := Label.new()
	prompt.text = "Filter: "
	filter_row.add_child(prompt)
	_filter = LineEdit.new()
	_filter.name = "Filter"
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.placeholder_text = "text to find (ignores case)"
	_filter.context_menu_enabled = false
	_filter.text_changed.connect(_on_filter_changed)
	_filter.gui_input.connect(_on_filter_gui_input)
	filter_row.add_child(_filter)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_color_override("font_color", DIM_COLOR)
	right.add_child(_status)

	_output = RichTextLabel.new()
	_output.name = "Output"
	_output.bbcode_enabled = true
	_output.focus_mode = Control.FOCUS_NONE
	_output.scroll_active = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_output)

	column.add_child(HSeparator.new())
	var footer := Label.new()
	footer.text = FOOTER
	footer.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(footer)
