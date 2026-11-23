class_name MissionCard
extends CanvasLayer
## Ticket-style briefing and debrief cards (SPEC §7.2, §8.3). The briefing
## reads `Sim.scenario_view()`; the debrief reads `Sim.debrief_view()`, which is
## null until the mission has ended. The card holds no state of its own beyond
## which one is showing.
##
## A mission that ended by failing gets the same card in a failed form
## (SPEC §7.2 step 6): which objective failed, the report's answers and the log
## lines that were the evidence, and two choices, Retry and Main menu. Esc does
## not dismiss it, so the player picks one.
##
## While a card is open it takes every key and click, so nothing behind it
## reacts. Enter, Esc or the button closes it and hands the mouse back to the
## player.

signal closed(kind: Kind)
## The failed card's Retry: the mission should reload from its start.
signal retry_requested
## The failed card's Main menu.
signal menu_requested

enum Kind { NONE, BRIEFING, DEBRIEF, FAILED }

const BRIEFING_LABEL: String = "NEW TICKET"
const DEBRIEF_LABEL: String = "TICKET RESOLVED"
const BRIEFING_BUTTON: String = "Start"
const DEBRIEF_BUTTON: String = "Continue"
const FAILED_LABEL: String = "TICKET FAILED"
const RETRY_BUTTON: String = "Retry"
const MENU_BUTTON: String = "Main menu"
const FAILED_NOTE: String = "You ran out of attempts, so this ticket cannot be resolved. Here is what the answers were and where the evidence was."
const REPORT_HEIGHT: float = 220.0
const WIDTH: float = 720.0
const PAPER: Color = Color(0.95, 0.93, 0.87)
const INK: Color = Color(0.12, 0.13, 0.15)
const MUTED_INK: Color = Color(0.40, 0.40, 0.42)
const STAMP: Color = Color(0.70, 0.18, 0.15)
const PASSED_INK: Color = Color(0.15, 0.45, 0.20)

var _kind: Kind = Kind.NONE

var _label: Label
var _heading: Label
var _results: Label
var _body: Label
var _report_scroll: ScrollContainer
var _report: Label
var _button: Button
var _secondary: Button


func _ready() -> void:
	layer = 20
	_build()
	hide()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null:
		return
	# Keys never reach the world or HUD behind the card. Mark the event handled
	# before closing: closing can switch scenes, and this node then has no viewport.
	get_viewport().set_input_as_handled()
	if not key.pressed or key.echo:
		return
	if _kind == Kind.FAILED:
		# Esc cannot dismiss it: the player picks Retry or Main menu.
		if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_choose(not _secondary.has_focus())
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		close()


# --- public ---------------------------------------------------------------------


## Shows the loaded scenario's ticket. False (and nothing shown) before a
## scenario has loaded.
func show_briefing() -> bool:
	var view: ScenarioView = Sim.scenario_view()
	if view == null:
		return false
	_label.text = BRIEFING_LABEL
	_label.add_theme_color_override("font_color", MUTED_INK)
	_heading.text = view.title()
	_results.text = ""
	_results.hide()
	_body.text = view.briefing()
	_button.text = BRIEFING_BUTTON
	_set_report("")
	_secondary.hide()
	_open(Kind.BRIEFING)
	return true


## Shows how the mission ended: the resolved ticket, or the failed card when
## the mission was failed. False (and nothing shown) while it is still being played.
func show_debrief() -> bool:
	var view: DebriefView = Sim.debrief_view()
	if view == null:
		return false
	_heading.text = view.title()
	_results.text = results_lines(view.objectives())
	_results.visible = not view.objectives().is_empty()
	_set_report(report_text(view.report_fields()))
	if view.completed():
		_label.text = DEBRIEF_LABEL
		_label.add_theme_color_override("font_color", STAMP)
		_body.text = view.text()
		_button.text = DEBRIEF_BUTTON
		_secondary.hide()
		_open(Kind.DEBRIEF)
	else:
		_label.text = FAILED_LABEL
		_label.add_theme_color_override("font_color", STAMP)
		_body.text = failed_note(view.objectives())
		_button.text = RETRY_BUTTON
		_secondary.text = MENU_BUTTON
		_secondary.show()
		_open(Kind.FAILED)
	return true


## One line per objective: `[x]` passed, `[!]` failed for good, `[ ]` otherwise.
static func results_lines(objectives: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	for o: Dictionary in objectives:
		var mark: String = "[x]" if o["passed"] else ("[!]" if o["failed"] else "[ ]")
		lines.append("%s %s" % [mark, o["description"]])
	return "\n".join(lines)


## Says which objective ended the mission, then why the answers follow.
static func failed_note(objectives: Array[Dictionary]) -> String:
	for o: Dictionary in objectives:
		if o["failed"]:
			return "Failed: %s\n%s" % [o["description"], FAILED_NOTE]
	return FAILED_NOTE


## The report block: per field its label, the right answer (and what the player
## filed), and the log lines that showed it. "" when there are no fields.
static func report_text(fields: Array[Dictionary]) -> String:
	var blocks: PackedStringArray = []
	for f: Dictionary in fields:
		var lines: PackedStringArray = [f["label"]]
		var filed: String = f["last_value"]
		if f["solved"]:
			lines.append("  Answer: %s  (solved)" % f["answer"])
		elif filed.is_empty():
			lines.append("  Answer: %s  (not filed)" % f["answer"])
		else:
			lines.append("  Answer: %s  (you filed: %s)" % [f["answer"], filed])
		for e: Dictionary in f["evidence"]:
			lines.append("  Evidence: %s %s line %d: %s" % [e["source"], e["file"], e["line"], e["text"]])
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)


func close() -> void:
	if _kind == Kind.NONE:
		return
	if _kind == Kind.FAILED:
		# Closing it any other way is the same as leaving for the menu.
		_choose(false)
		return
	var was: Kind = _kind
	_kind = Kind.NONE
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit(was)


func kind() -> Kind:
	return _kind


func is_open() -> bool:
	return _kind != Kind.NONE


func label_text() -> String:
	return _label.text


func heading_text() -> String:
	return _heading.text


## The debrief's objective results, one line each; "" on a briefing.
func results_text() -> String:
	return _results.text


func body_text() -> String:
	return _body.text


## The answers and evidence block, "" when the card has none.
func report_block_text() -> String:
	return _report.text


## The second button's text, "" while it is not shown.
func secondary_button_text() -> String:
	return _secondary.text if _secondary.visible else ""


func button_text() -> String:
	return _button.text


# --- internals ------------------------------------------------------------------


func _set_report(text: String) -> void:
	_report.text = text
	_report_scroll.visible = not text.is_empty()


func _on_primary() -> void:
	if _kind == Kind.FAILED:
		_choose(true)
	else:
		close()


## Leaves the failed card for Retry or the main menu.
func _choose(retry: bool) -> void:
	if _kind != Kind.FAILED:
		return
	_kind = Kind.NONE
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if retry:
		retry_requested.emit()
	else:
		menu_requested.emit()


func _open(kind_: Kind) -> void:
	_kind = kind_
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_button.grab_focus.call_deferred()


func _build() -> void:
	# A full-screen shade that also swallows clicks meant for the world.
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_content_margin_all(24.0)
	style.set_corner_radius_all(3)
	style.border_color = Color(0.80, 0.77, 0.70)
	style.set_border_width_all(1)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_label = _text_label(MUTED_INK, 13)
	box.add_child(_label)
	_heading = _text_label(INK, 24)
	box.add_child(_heading)
	box.add_child(HSeparator.new())
	_results = _text_label(PASSED_INK, 15)
	box.add_child(_results)
	_body = _text_label(INK, 15)
	box.add_child(_body)

	_report_scroll = ScrollContainer.new()
	_report_scroll.custom_minimum_size = Vector2(WIDTH - 48.0, REPORT_HEIGHT)
	_report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_report_scroll)
	_report = _text_label(INK, 13)
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report_scroll.add_child(_report)
	_report_scroll.hide()

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(120.0, 36.0)
	_button.pressed.connect(_on_primary)
	buttons.add_child(_button)
	_secondary = Button.new()
	_secondary.custom_minimum_size = Vector2(120.0, 36.0)
	_secondary.pressed.connect(_choose.bind(false))
	buttons.add_child(_secondary)
	_secondary.hide()


func _text_label(color: Color, size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 48.0
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
