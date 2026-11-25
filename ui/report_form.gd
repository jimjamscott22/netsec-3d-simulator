class_name ReportForm
extends CanvasLayer
## The incident report form (SPEC §8.3, task 2.8). One row per field in
## `Sim.scenario_view().report_fields()`: a text box, an IPv4 box or a choice
## list by the field's kind, a Submit button, and the attempts left, which
## come live from `Sim.report_view()`. Nothing here knows a mission's fields or
## answers; the sim judges every value.
##
## Keys: Enter in a box submits that field, Esc closes.

signal opened
signal closed

const FONT_NAMES: PackedStringArray = ["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Menlo", "monospace"]
const FONT_SIZE: int = 16
const BACKGROUND: Color = Color(0.03, 0.04, 0.05, 0.97)
const TEXT_COLOR: Color = Color(0.80, 0.92, 0.82)
const DIM_COLOR: Color = Color(0.55, 0.62, 0.58)
const GOOD_COLOR: Color = Color(0.45, 0.85, 0.50)
const BAD_COLOR: Color = Color(0.95, 0.55, 0.45)
const TITLE: String = "Incident report"
const FOOTER: String = "Enter submit the field · wrong answers cost an attempt · Esc close"
const LOCKED_NOTE: String = "No attempts left"
const SOLVED_NOTE: String = "Solved"
const CORRECT_NOTE: String = "Correct."
const WRONG_NOTE: String = "Not correct."

## Per field id: `{kind, options, input, button, status, feedback_label, feedback}`.
var _rows: Dictionary[String, Dictionary] = {}
var _order: Array[String] = []

var _subtitle: Label
var _box: VBoxContainer


func _ready() -> void:
	layer = 10
	_build()
	hide()
	Sim.scenario_loaded.connect(_on_scenario_loaded)
	Sim.report_submitted.connect(_on_report_submitted)


## Esc is caught before the GUI so it works wherever the focus is.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- public ---------------------------------------------------------------------


## Opens the form on the loaded mission's report fields. Returns false (and stays
## closed) when the mission has no report.
func open() -> bool:
	var scenario: ScenarioView = Sim.scenario_view()
	if scenario == null or not scenario.has_report():
		return false
	_subtitle.text = "%s  ·  %d wrong answers allowed per field" % [
		scenario.title(), scenario.report_max_attempts()
	]
	_rebuild(scenario.report_fields())
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_all()
	_focus_first_open_field()
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


## The field ids in file order.
func field_ids() -> Array[String]:
	return _order.duplicate()


## Types `value` into a field's box, or picks it from a choice field's list. A
## value that is not one of a choice's options leaves it unpicked.
func set_value(field: String, value: String) -> void:
	var row: Dictionary = _rows.get(field, {})
	if row.is_empty():
		return
	if row["kind"] == ReportState.Kind.CHOICE:
		var options: Array = row["options"]
		(row["input"] as OptionButton).select(options.find(value))
	else:
		(row["input"] as LineEdit).text = value


## What a field's box holds: the typed text, or the picked option ("" if none).
func value_of(field: String) -> String:
	var row: Dictionary = _rows.get(field, {})
	if row.is_empty():
		return ""
	if row["kind"] == ReportState.Kind.CHOICE:
		var picked: int = (row["input"] as OptionButton).selected
		var options: Array = row["options"]
		return options[picked] if picked >= 0 else ""
	return (row["input"] as LineEdit).text


## Files a field's value with the sim, and shows what came back. A choice with
## nothing picked, or an empty box, is not sent: it costs nothing either way.
func submit(field: String) -> ReportResult:
	var row: Dictionary = _rows.get(field, {})
	if row.is_empty():
		return ReportResult.refused(ReportResult.Reason.UNKNOWN_FIELD)
	var value: String = value_of(field)
	var result: ReportResult
	if value.strip_edges().is_empty():
		result = ReportResult.refused(ReportResult.Reason.INVALID_VALUE)
	else:
		result = Sim.submit_report(field, value)
	row["feedback"] = feedback_text(result, row["kind"])
	row["feedback_good"] = result.ok and result.correct
	_refresh_row(field)
	return result


## The attempts line of a field: "3 attempts left", "Solved" or "No attempts left".
func status_text(field: String) -> String:
	var row: Dictionary = _rows.get(field, {})
	return (row["status"] as Label).text if not row.is_empty() else ""


## The answer to the last submit of a field, or "" before one.
func feedback(field: String) -> String:
	var row: Dictionary = _rows.get(field, {})
	return row["feedback"] if not row.is_empty() else ""


## True when the field takes no more input (solved or out of attempts).
func is_locked(field: String) -> bool:
	var row: Dictionary = _rows.get(field, {})
	return row.is_empty() or (row["button"] as Button).disabled


## One line saying what a submission did. Static so the wording is testable.
static func feedback_text(result: ReportResult, kind: int) -> String:
	if result.ok:
		return CORRECT_NOTE if result.correct else WRONG_NOTE
	match result.reason:
		ReportResult.Reason.INVALID_VALUE:
			match kind:
				ReportState.Kind.IPV4:
					return "That is not a valid IPv4 address."
				ReportState.Kind.CHOICE:
					return "Pick one of the options first."
				_:
					return "Type an answer first."
		ReportResult.Reason.ALREADY_SOLVED:
			return "Already solved."
		ReportResult.Reason.OUT_OF_ATTEMPTS:
			return LOCKED_NOTE + "."
		ReportResult.Reason.MISSION_OVER:
			return "The mission is over."
	return "That field does not exist."


static func attempts_text(left: int) -> String:
	return "%d attempt%s left" % [left, "" if left == 1 else "s"]


# --- internals ------------------------------------------------------------------


func _rebuild(fields: Array) -> void:
	for child: Node in _box.get_children():
		child.free()
	_rows.clear()
	_order.clear()
	for entry: Dictionary in fields:
		_add_row(entry)


func _add_row(entry: Dictionary) -> void:
	var id: String = entry["id"]
	var kind: int = entry["kind"]
	var options: Array = entry["options"]

	var column := VBoxContainer.new()
	column.name = id
	_box.add_child(column)
	var label := Label.new()
	label.text = "%s  ·  %s" % [entry["label"], _kind_hint(kind)]
	column.add_child(label)

	var line := HBoxContainer.new()
	column.add_child(line)
	var input: Control
	if kind == ReportState.Kind.CHOICE:
		var list := OptionButton.new()
		list.fit_to_longest_item = true
		for option: String in options:
			list.add_item(option)
		list.select(-1)
		input = list
	else:
		var box := LineEdit.new()
		box.placeholder_text = "e.g. 10.0.0.1" if kind == ReportState.Kind.IPV4 else "answer"
		box.custom_minimum_size = Vector2(320, 0)
		box.text_submitted.connect(func(_text: String) -> void: submit(id))
		input = box
	input.name = "Input"
	line.add_child(input)
	var button := Button.new()
	button.name = "Submit"
	button.text = "Submit"
	button.pressed.connect(func() -> void: submit(id))
	line.add_child(button)
	var status := Label.new()
	status.name = "Status"
	status.add_theme_color_override("font_color", DIM_COLOR)
	line.add_child(status)

	var feedback_label := Label.new()
	feedback_label.name = "Feedback"
	column.add_child(feedback_label)
	_box.add_child(HSeparator.new())

	_rows[id] = {
		"kind": kind, "options": options, "input": input, "button": button,
		"status": status, "feedback_label": feedback_label,
		"feedback": "", "feedback_good": false,
	}
	_order.append(id)


static func _kind_hint(kind: int) -> String:
	match kind:
		ReportState.Kind.IPV4:
			return "an IPv4 address"
		ReportState.Kind.CHOICE:
			return "pick one"
	return "short text"


func _refresh_all() -> void:
	for id: String in _order:
		_refresh_row(id)


func _refresh_row(id: String) -> void:
	var row: Dictionary = _rows[id]
	var state: Dictionary = Sim.report_view().field(id)
	var solved: bool = state.get("solved", false)
	var left: int = state.get("attempts_left", 0)
	var locked: bool = solved or left <= 0
	(row["button"] as Button).disabled = locked
	if row["kind"] == ReportState.Kind.CHOICE:
		(row["input"] as OptionButton).disabled = locked
	else:
		(row["input"] as LineEdit).editable = not locked
	if solved:
		set_value(id, state.get("last_value", ""))
	var status: Label = row["status"]
	status.text = SOLVED_NOTE if solved else (LOCKED_NOTE if left <= 0 else attempts_text(left))
	var shown: Label = row["feedback_label"]
	shown.text = row["feedback"]
	shown.add_theme_color_override("font_color", GOOD_COLOR if row["feedback_good"] else BAD_COLOR)


func _focus_first_open_field() -> void:
	for id: String in _order:
		if not is_locked(id):
			(_rows[id]["input"] as Control).grab_focus()
			return


func _on_scenario_loaded(_scenario_id: String) -> void:
	close()


func _on_report_submitted(_field: String, _correct: bool) -> void:
	if visible:
		_refresh_all()


func _build() -> void:
	var font := SystemFont.new()
	font.font_names = FONT_NAMES
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_color("font_color", "LineEdit", TEXT_COLOR)
	theme.set_color("caret_color", "LineEdit", TEXT_COLOR)

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
	column.add_child(title)
	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(_subtitle)
	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_box = VBoxContainer.new()
	_box.name = "Fields"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)

	column.add_child(HSeparator.new())
	var footer := Label.new()
	footer.text = FOOTER
	footer.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(footer)
