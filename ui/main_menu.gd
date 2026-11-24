class_name MainMenu
extends Control
## The startup screen (SPEC §7.2 step 1, tasks 1.31 and 2.10): mission select,
## Settings and Quit. One row per mission from `Sim.scenario_catalog()`, in
## `sequence` order, each with its status (Completed, Not started, or Locked until
## the mission before it is completed in the saved progress) and a Start button.
##
## It opens the player's save (`Progress.open()`) the first time it appears,
## unless something opened one already (tests open a temp file first).

## The player chose to start a mission and it loaded. When the menu is the
## running scene it then switches to the game scene itself.
signal start_requested(scenario_id: String)

const GAME_SCENE: String = "res://game/main.tscn"
const GAME_TITLE: String = "NetSec 3D Simulator"
const BACKGROUND: Color = Color(0.07, 0.08, 0.10)
const PANEL: Color = Color(0.12, 0.14, 0.17)
const TEXT: Color = Color(0.85, 0.88, 0.90)
const MUTED: Color = Color(0.55, 0.58, 0.62)
const DONE: Color = Color(0.35, 0.75, 0.40)
const ERROR: Color = Color(0.90, 0.40, 0.35)
const WIDTH: float = 560.0

## One entry per listed mission: `{id, title, locked, title_label, status_label, button}`.
var _rows: Array[Dictionary] = []
var _missions_box: VBoxContainer
var _error: Label
var _buttons: VBoxContainer
var _settings_button: Button
var _quit: Button
var _settings: VBoxContainer
var _settings_panel: SettingsPanel
var _back: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Progress.is_open():
		Progress.open()
	_build()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_missions()
	_focus_first_open_mission()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and settings_open():
		close_settings()
		get_viewport().set_input_as_handled()


# --- public ---------------------------------------------------------------------


## Reads the catalog and the saved progress again and redraws the mission rows.
func refresh_missions() -> void:
	for row: Dictionary in _rows:
		(row["panel"] as Node).free()
	_rows.clear()
	_error.hide()
	var missions: Array[ScenarioSummary] = Sim.scenario_catalog()
	var completed: Array[String] = Progress.completed_ids()
	for index: int in missions.size():
		_add_row(missions[index], index, ScenarioCatalog.is_locked(missions, index, completed), completed)
	var problems: Array[String] = Sim.catalog_problems()
	if missions.is_empty():
		_show_error("No missions found.", problems)
	elif not problems.is_empty():
		_show_error("Some scenario files were left out:", problems)


## Loads a mission and announces it; `scenario_id` "" means the first mission in
## the list. A locked or unknown mission is refused. On a load error the menu stays,
## shows the problem and returns false.
func start_mission(scenario_id: String = "") -> bool:
	var row: Dictionary = _row_for(scenario_id)
	if row.is_empty() or row["locked"]:
		return false
	var id: String = row["id"]
	var result: LoadResult = Sim.load_scenario_id(id)
	if not result.ok:
		_show_error("Could not load the mission:", result.errors)
		return false
	start_requested.emit(id)
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(GAME_SCENE)
	return true


func open_settings() -> void:
	_buttons.hide()
	_settings.show()
	_back.grab_focus.call_deferred()


func close_settings() -> void:
	_settings.hide()
	_buttons.show()
	_settings_button.grab_focus.call_deferred()


func settings_open() -> bool:
	return _settings.visible


func settings_panel() -> SettingsPanel:
	return _settings_panel


## The ids of the listed missions, in order.
func mission_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in _rows:
		ids.append(row["id"])
	return ids


## Title of the mission at `index` in the list ("" if there is none).
func mission_title_text(index: int = 0) -> String:
	return (_rows[index]["title_label"] as Label).text if index < _rows.size() else ""


## "Completed", "Not started" or "Locked" for the mission at `index`.
func mission_status_text(index: int = 0) -> String:
	return (_rows[index]["status_label"] as Label).text if index < _rows.size() else ""


func is_mission_locked(index: int) -> bool:
	return index < _rows.size() and _rows[index]["locked"]


func error_text() -> String:
	return _error.text


## The Start button of the mission at `index`, or null if there is none.
func start_button(index: int = 0) -> Button:
	return _rows[index]["button"] if index < _rows.size() else null


func quit_button() -> Button:
	return _quit


# --- internals ------------------------------------------------------------------


func _row_for(scenario_id: String) -> Dictionary:
	for row: Dictionary in _rows:
		if scenario_id.is_empty() or row["id"] == scenario_id:
			return row
	return {}


func _focus_first_open_mission() -> void:
	for row: Dictionary in _rows:
		if not row["locked"]:
			(row["button"] as Button).grab_focus.call_deferred()
			return
	_settings_button.grab_focus.call_deferred()


func _show_error(heading: String, lines: Array[String]) -> void:
	_error.text = "\n".join([heading] + lines)
	_error.show()


func _build() -> void:
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = WIDTH
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	var title := _label(GAME_TITLE, TEXT, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var tagline := _label("Cable it. Configure it. Defend it.", MUTED, 16)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline)

	_missions_box = VBoxContainer.new()
	_missions_box.add_theme_constant_override("separation", 10)
	column.add_child(_missions_box)

	_error = _label("", ERROR, 14)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	column.add_child(_error)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_buttons)
	_settings_button = _button("Settings", open_settings)
	_quit = _button("Quit", get_tree().quit)
	# A browser tab can't be quit from inside the page.
	_quit.visible = not OS.has_feature("web")

	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 18)
	_settings.hide()
	column.add_child(_settings)
	_settings.add_child(_label("Settings", TEXT, 22))
	_settings_panel = SettingsPanel.new()
	_settings.add_child(_settings_panel)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(120.0, 36.0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_END
	_back.pressed.connect(close_settings)
	_settings.add_child(_back)


func _add_row(mission: ScenarioSummary, index: int, locked: bool, completed: Array[String]) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_content_margin_all(16.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_missions_box.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(_label("MISSION %d" % mission.sequence, MUTED, 12))
	var title: Label = _label(mission.title, MUTED if locked else TEXT, 20)
	text.add_child(title)

	var done: bool = completed.has(mission.id)
	var status_text: String = "Locked" if locked else ("Completed" if done else "Not started")
	var status: Label = _label(status_text, DONE if done else MUTED, 14)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)

	var button := Button.new()
	button.text = "Start"
	button.custom_minimum_size = Vector2(90.0, 36.0)
	button.disabled = locked
	button.pressed.connect(start_mission.bind(mission.id))
	row.add_child(button)

	_rows.append({
		"id": mission.id, "title": mission.title, "locked": locked, "panel": panel,
		"title_label": title, "status_label": status, "button": button,
	})


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(on_press)
	_buttons.add_child(button)
	return button


func _label(text: String, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label
