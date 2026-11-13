class_name MainMenu
extends Control
## The startup screen (SPEC §7.2 step 1, task 1.31): the M1 mission with its
## completion mark, Start mission, Settings and Quit. Mission select with locked
## missions replaces the single mission row in M2 (task 2.10).
##
## It opens the player's save (`Progress.open()`) the first time it appears,
## unless something opened one already (tests open a temp file first).

## The player chose to start a mission and it loaded. When the menu is the
## running scene it then switches to the game scene itself.
signal start_requested(scenario_id: String)

const FIRST_MISSION: String = "m1_vlan_ping"
const GAME_SCENE: String = "res://game/main.tscn"
const GAME_TITLE: String = "NetSec 3D Simulator"
const BACKGROUND: Color = Color(0.07, 0.08, 0.10)
const PANEL: Color = Color(0.12, 0.14, 0.17)
const TEXT: Color = Color(0.85, 0.88, 0.90)
const MUTED: Color = Color(0.55, 0.58, 0.62)
const DONE: Color = Color(0.35, 0.75, 0.40)
const ERROR: Color = Color(0.90, 0.40, 0.35)
const WIDTH: float = 560.0

var _mission_title: Label
var _mission_status: Label
var _error: Label
var _buttons: VBoxContainer
var _start: Button
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
	_show_mission()
	_start.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and settings_open():
		close_settings()
		get_viewport().set_input_as_handled()


# --- public ---------------------------------------------------------------------


## Loads the mission and announces it. On a load error the menu stays, shows
## the problem and returns false.
func start_mission() -> bool:
	var result: LoadResult = Sim.load_scenario_id(FIRST_MISSION)
	if not result.ok:
		_show_error(result.errors)
		return false
	start_requested.emit(FIRST_MISSION)
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


func mission_title_text() -> String:
	return _mission_title.text


func mission_status_text() -> String:
	return _mission_status.text


func error_text() -> String:
	return _error.text


func start_button() -> Button:
	return _start


func quit_button() -> Button:
	return _quit


# --- internals ------------------------------------------------------------------


## Loading the mission is the only way to read its title without touching
## scenario JSON here. Starting it loads it again from scratch.
func _show_mission() -> void:
	var result: LoadResult = Sim.load_scenario_id(FIRST_MISSION)
	if not result.ok:
		_mission_title.text = FIRST_MISSION
		_mission_status.text = ""
		_start.disabled = true
		_show_error(result.errors)
		return
	_mission_title.text = Sim.scenario_view().title()
	var done: bool = Progress.is_completed(FIRST_MISSION)
	_mission_status.text = "Completed" if done else "Not started"
	_mission_status.add_theme_color_override("font_color", DONE if done else MUTED)


func _show_error(errors: Array[String]) -> void:
	_error.text = "Could not load the mission:\n" + "\n".join(errors)
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

	column.add_child(_mission_row())

	_error = _label("", ERROR, 14)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	column.add_child(_error)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_buttons)
	_start = _button("Start mission", start_mission)
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


func _mission_row() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_content_margin_all(16.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(_label("MISSION 1", MUTED, 12))
	_mission_title = _label("", TEXT, 20)
	text.add_child(_mission_title)
	_mission_status = _label("", MUTED, 14)
	_mission_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_mission_status)
	return panel


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
