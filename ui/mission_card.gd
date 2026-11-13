class_name MissionCard
extends CanvasLayer
## Ticket-style briefing and debrief cards (SPEC §7.2, §8.3). The briefing
## reads `Sim.scenario_view()`; the debrief reads `Sim.debrief_view()`, which is
## null until the mission has ended. The card holds no state of its own beyond
## which one is showing.
##
## While a card is open it takes every key and click, so nothing behind it
## reacts. Enter, Esc or the button closes it and hands the mouse back to the
## player.

signal closed(kind: Kind)

enum Kind { NONE, BRIEFING, DEBRIEF }

const BRIEFING_LABEL: String = "NEW TICKET"
const DEBRIEF_LABEL: String = "TICKET RESOLVED"
const BRIEFING_BUTTON: String = "Start"
const DEBRIEF_BUTTON: String = "Continue"
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
var _button: Button


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
	if key.pressed and not key.echo and key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		close()
	# Keys never reach the world or HUD behind the card.
	get_viewport().set_input_as_handled()


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
	_open(Kind.BRIEFING)
	return true


## Shows how the mission ended. False (and nothing shown) while it is still
## being played.
func show_debrief() -> bool:
	var view: DebriefView = Sim.debrief_view()
	if view == null:
		return false
	_label.text = DEBRIEF_LABEL
	_label.add_theme_color_override("font_color", STAMP)
	_heading.text = view.title()
	var lines: PackedStringArray = []
	for o: Dictionary in view.objectives():
		lines.append("%s %s" % ["[x]" if o["passed"] else "[ ]", o["description"]])
	_results.text = "\n".join(lines)
	_results.visible = not lines.is_empty()
	_body.text = view.text()
	_button.text = DEBRIEF_BUTTON
	_open(Kind.DEBRIEF)
	return true


func close() -> void:
	if _kind == Kind.NONE:
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


func button_text() -> String:
	return _button.text


# --- internals ------------------------------------------------------------------


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

	_button = Button.new()
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.custom_minimum_size = Vector2(120.0, 36.0)
	_button.pressed.connect(close)
	box.add_child(_button)


func _text_label(color: Color, size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 48.0
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
