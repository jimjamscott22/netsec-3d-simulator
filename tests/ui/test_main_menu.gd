class_name TestMainMenu
extends GdUnitTestSuite
## The main menu and its settings panel (task 1.31). Each test opens a temp
## save first, so the menu never opens the player's real one.

const MENU_SCENE: PackedScene = preload("res://ui/main_menu.tscn")
const TEMP_DIR: String = "user://main_menu_test"
const SAVE: String = TEMP_DIR + "/progress.json"
const MISSION: String = "m1_vlan_ping"
const SECOND: String = "m2_log_triage"
const EMPTY_DIR: String = "user://main_menu_test_no_scenarios"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	Progress.open(SAVE)


func after_test() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	Progress.close()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	Sim.load_scenario_id(MISSION)


func _menu() -> MainMenu:
	var menu: MainMenu = auto_free(MENU_SCENE.instantiate()) as MainMenu
	add_child(menu)
	return menu


func test_keeps_a_save_that_is_already_open() -> void:
	_menu()
	assert_str(Progress.path()).is_equal(SAVE)


func test_lists_the_missions_in_sequence_order() -> void:
	var menu: MainMenu = _menu()
	assert_array(menu.mission_ids()).starts_with([MISSION, SECOND])
	assert_str(menu.mission_title_text(1)).is_equal("Who Knocked?")


func test_shows_the_first_mission_not_started() -> void:
	var menu: MainMenu = _menu()
	assert_str(menu.mission_title_text()).is_equal("Day One: Get Them Talking")
	assert_str(menu.mission_status_text()).is_equal("Not started")
	assert_bool(menu.start_button().disabled).is_false()
	assert_str(menu.error_text()).is_empty()
	assert_bool(menu.settings_open()).is_false()


func test_shows_a_completed_mission() -> void:
	Progress.mark_completed(MISSION)
	var menu: MainMenu = _menu()
	assert_str(menu.mission_status_text()).is_equal("Completed")


func test_the_next_mission_is_locked_until_the_one_before_is_completed() -> void:
	var menu: MainMenu = _menu()
	assert_bool(menu.is_mission_locked(0)).is_false()
	assert_bool(menu.is_mission_locked(1)).is_true()
	assert_str(menu.mission_status_text(1)).is_equal("Locked")
	assert_bool(menu.start_button(1).disabled).is_true()

	Progress.mark_completed(MISSION)
	menu.refresh_missions()
	assert_bool(menu.is_mission_locked(1)).is_false()
	assert_str(menu.mission_status_text(1)).is_equal("Not started")
	assert_bool(menu.start_button(1).disabled).is_false()


func test_a_locked_mission_cannot_be_started() -> void:
	var menu: MainMenu = _menu()
	var started: Array[String] = []
	menu.start_requested.connect(started.append)
	assert_bool(menu.start_mission(SECOND)).is_false()
	assert_array(started).is_empty()


func test_an_unknown_mission_cannot_be_started() -> void:
	var menu: MainMenu = _menu()
	assert_bool(menu.start_mission("no_such_mission")).is_false()


func test_starting_the_unlocked_second_mission_loads_it() -> void:
	Progress.mark_completed(MISSION)
	var menu: MainMenu = _menu()
	var started: Array[String] = []
	menu.start_requested.connect(started.append)
	menu.start_button(1).pressed.emit()
	assert_array(started).contains_exactly([SECOND])
	assert_str(Sim.scenario_view().scenario_id()).is_equal(SECOND)


func test_start_reloads_the_mission_from_scratch_and_announces_it() -> void:
	var menu: MainMenu = _menu()
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	var started: Array[String] = []
	menu.start_requested.connect(started.append)

	assert_bool(menu.start_mission()).is_true()
	assert_array(started).contains_exactly([MISSION])
	# The fresh load dropped the cable plugged in above.
	assert_object(Sim.device_view("PC-B").interface("Ethernet0")["peer"]).is_null()


func test_start_button_starts_the_mission() -> void:
	var menu: MainMenu = _menu()
	var started: Array[String] = []
	menu.start_requested.connect(started.append)
	menu.start_button().pressed.emit()
	assert_array(started).contains_exactly([MISSION])


func test_with_no_scenario_files_the_menu_says_so() -> void:
	DirAccess.make_dir_recursive_absolute(EMPTY_DIR)
	Sim.scenario_dir = EMPTY_DIR
	var menu: MainMenu = _menu()
	assert_array(menu.mission_ids()).is_empty()
	assert_str(menu.error_text()).starts_with("No missions found.")
	assert_bool(menu.start_mission()).is_false()
	assert_object(menu.start_button()).is_null()


func test_settings_open_and_close() -> void:
	var menu: MainMenu = _menu()
	menu.open_settings()
	assert_bool(menu.settings_open()).is_true()
	menu.close_settings()
	assert_bool(menu.settings_open()).is_false()


func test_esc_closes_settings() -> void:
	var menu: MainMenu = _menu()
	menu.open_settings()
	var esc := InputEventAction.new()
	esc.action = "cancel"
	esc.pressed = true
	menu._unhandled_input(esc)
	assert_bool(menu.settings_open()).is_false()


# --- settings panel ---------------------------------------------------------------


func test_settings_show_the_saved_values() -> void:
	Progress.set_look_sensitivity(1.5)
	Progress.set_fullscreen(true)
	Progress.set_volume(0.25)
	var panel: SettingsPanel = _menu().settings_panel()
	assert_float(panel.look_slider().value).is_equal(1.5)
	assert_bool(panel.fullscreen_toggle().button_pressed).is_true()
	assert_float(panel.volume_slider().value).is_equal(0.25)
	assert_str(panel.look_value_text()).is_equal("1.50x")
	assert_str(panel.volume_value_text()).is_equal("25%")


func test_moving_the_controls_changes_and_saves_the_settings() -> void:
	var panel: SettingsPanel = _menu().settings_panel()
	panel.look_slider().value = 2.0
	panel.fullscreen_toggle().button_pressed = true
	panel.volume_slider().value = 0.4
	assert_float(Progress.look_sensitivity()).is_equal(2.0)
	assert_bool(Progress.fullscreen()).is_true()
	assert_float(Progress.volume()).is_equal(0.4)
	assert_str(panel.look_value_text()).is_equal("2.00x")
	assert_str(panel.volume_value_text()).is_equal("40%")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	assert_float(saved["settings"]["volume"]).is_equal(0.4)
	Progress.set_fullscreen(false)


func test_the_panel_follows_changes_made_elsewhere() -> void:
	var panel: SettingsPanel = _menu().settings_panel()
	Progress.set_volume(0.1)
	assert_float(panel.volume_slider().value).is_equal(0.1)
	assert_str(panel.volume_value_text()).is_equal("10%")
