class_name MissionHud
extends CanvasLayer
## The mission HUD (SPEC §7.2, §8.3): the objective list with live ticks, the
## spare cable count and the hint key prompt.
##
## It holds no network truth. Every refresh reads `Sim.objective_states()` and
## `Sim.spare_cables()` again, on each Sim signal that can change them.
##
## Keys: H shows or hides a hint, Tab shows or hides the objective list. A hint
## is never shown until asked for. Once shown it stays while it still applies,
## and hides itself when the state changes so that it no longer does.

const PASSED_MARK: String = "[x]"
const OPEN_MARK: String = "[ ]"
const FAILED_MARK: String = "[!]"
const NEXT_STEP: String = "Next step: "
const NO_HINT: String = "No hint for this step. Check the objectives' details."
const ALL_DONE: String = "Every objective is complete."
const PROMPT: String = "H hint · Tab objectives"
const WIDTH: float = 380.0
const TEXT_COLOR: Color = Color(0.92, 0.94, 0.92)
const PASSED_COLOR: Color = Color(0.55, 0.88, 0.55)
const FAILED_COLOR: Color = Color(0.95, 0.45, 0.40)
const LOCKED_COLOR: Color = Color(0.55, 0.57, 0.58)
const HINT_COLOR: Color = Color(1.0, 0.85, 0.45)

var _hint_shown: bool = false

var _title: Label
var _objectives: VBoxContainer
var _spare: Label
var _prompt: Label
var _hint: Label


func _ready() -> void:
	_build()
	Sim.objective_updated.connect(_refresh.unbind(2))
	Sim.config_changed.connect(_refresh.unbind(1))
	Sim.link_changed.connect(_refresh.unbind(3))
	Sim.interface_state_changed.connect(_refresh.unbind(2))
	Sim.scenario_loaded.connect(_on_scenario_loaded)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("hint"):
		toggle_hint()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_objectives"):
		toggle_objectives()
		get_viewport().set_input_as_handled()


# --- public ---------------------------------------------------------------------


func toggle_hint() -> void:
	_hint_shown = not _hint_shown
	_refresh()


func toggle_objectives() -> void:
	_objectives.visible = not _objectives.visible


func objectives_visible() -> bool:
	return _objectives.visible


func is_hint_shown() -> bool:
	return _hint_shown


func title_text() -> String:
	return _title.text


## One line of text per objective, in scenario order.
func objective_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for label: Label in _objective_labels():
		out.append(label.text)
	return out


## The colour each objective line is drawn in, in scenario order.
func objective_colors() -> Array[Color]:
	var out: Array[Color] = []
	for label: Label in _objective_labels():
		out.append(label.get_theme_color("font_color"))
	return out


func spare_text() -> String:
	return _spare.text


func prompt_text() -> String:
	return _prompt.text


## The hint on screen, or "" while none is shown.
func hint_text() -> String:
	return _hint.text if _hint.visible else ""


## The text of one objective line. Locked steps read as a "next step" with no
## status detail; an open step adds its detail (for example "reached, but not
## through R1") when it has one.
static func line_text(s: ObjectiveState) -> String:
	if s.locked:
		return "%s %s%s" % [OPEN_MARK, NEXT_STEP, s.description]
	var mark: String = PASSED_MARK if s.passed else (FAILED_MARK if s.failed else OPEN_MARK)
	var text: String = "%s %s" % [mark, s.description]
	if not s.passed and not s.detail.is_empty():
		text += " (%s)" % s.detail
	return text


static func line_color(s: ObjectiveState) -> Color:
	if s.locked:
		return LOCKED_COLOR
	if s.passed:
		return PASSED_COLOR
	if s.failed:
		return FAILED_COLOR
	return TEXT_COLOR


## The hint for the first unlocked objective that hasn't passed and has one, or
## NO_HINT. ALL_DONE once every objective has passed.
static func hint_for(states: Array[ObjectiveState]) -> String:
	var all_passed: bool = not states.is_empty()
	for s in states:
		if s.passed:
			continue
		all_passed = false
		if not s.locked and not s.hint.is_empty():
			return s.hint
	return ALL_DONE if all_passed else NO_HINT


# --- internals ------------------------------------------------------------------


func _on_scenario_loaded(_scenario_id: String) -> void:
	_hint_shown = false
	_objectives.visible = true
	_refresh()


func _refresh() -> void:
	var view: ScenarioView = Sim.scenario_view()
	_title.text = view.title() if view != null else ""
	var states: Array[ObjectiveState] = Sim.objective_states()
	_sync_labels(states.size())
	var labels: Array[Label] = _objective_labels()
	for i in states.size():
		labels[i].text = line_text(states[i])
		labels[i].add_theme_color_override("font_color", line_color(states[i]))
	_spare.text = "Spare cables: %d" % Sim.spare_cables()
	_refresh_hint(states)


## A shown hint stays only while it still matches the state; once the problem
## it described is gone it hides, and the player asks again with H.
func _refresh_hint(states: Array[ObjectiveState]) -> void:
	if not _hint_shown:
		_hint.hide()
		_hint.text = ""
		return
	var text: String = hint_for(states)
	if _hint.visible and _hint.text != text:
		_hint_shown = false
		_hint.hide()
		_hint.text = ""
		return
	_hint.text = text
	_hint.show()


func _objective_labels() -> Array[Label]:
	var out: Array[Label] = []
	for child: Node in _objectives.get_children():
		out.append(child as Label)
	return out


func _sync_labels(count: int) -> void:
	while _objectives.get_child_count() > count:
		var last: Node = _objectives.get_child(_objectives.get_child_count() - 1)
		_objectives.remove_child(last)
		last.free()
	while _objectives.get_child_count() < count:
		var label: Label = _label(TEXT_COLOR)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_objectives.add_child(label)


func _build() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -WIDTH - 16.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_title = _label(TEXT_COLOR)
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)

	_objectives = VBoxContainer.new()
	_objectives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_objectives)

	_spare = _label(TEXT_COLOR)
	box.add_child(_spare)

	_hint = _label(HINT_COLOR)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.hide()
	box.add_child(_hint)

	_prompt = _label(LOCKED_COLOR)
	_prompt.text = PROMPT
	box.add_child(_prompt)


func _label(color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size.x = WIDTH - 20.0
	label.add_theme_color_override("font_color", color)
	return label
