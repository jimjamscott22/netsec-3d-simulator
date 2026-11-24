class_name TestLogViewer
extends GdUnitTestSuite
## The SOC monitor's log viewer (task 2.7): the file list and lines come from the
## loaded mission, the filter keeps and highlights matching lines.

const VIEWER_SCENE: PackedScene = preload("res://ui/log_viewer.tscn")
const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const FIXTURE_ID: String = "m2_fixture"
const TEMP_DIR: String = "user://log_viewer_test_scenarios"
const MISSION: String = "m1_vlan_ping"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEMP_DIR, FIXTURE_ID], FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(FIXTURE))
	file.close()
	Sim.scenario_dir = TEMP_DIR
	assert_array(Sim.load_scenario_id(FIXTURE_ID).errors).is_empty()


func after_test() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	Sim.load_scenario_id(MISSION)
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		for name: String in DirAccess.get_files_at(TEMP_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEMP_DIR, name])


func _viewer() -> LogViewer:
	var viewer: LogViewer = auto_free(VIEWER_SCENE.instantiate()) as LogViewer
	add_child(viewer)
	return viewer


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	return k


# --- opening and closing ----------------------------------------------------------


func test_starts_hidden() -> void:
	var viewer: LogViewer = _viewer()
	assert_bool(viewer.visible).is_false()
	assert_bool(viewer.is_open()).is_false()


func test_open_lists_every_log_file_and_shows_the_first() -> void:
	var viewer: LogViewer = _viewer()
	var signals: Array[String] = []
	viewer.opened.connect(func() -> void: signals.append("opened"))
	assert_bool(viewer.open()).is_true()
	assert_bool(viewer.visible).is_true()
	assert_array(signals).is_equal(["opened"])
	assert_int(viewer.file_count()).is_equal(Sim.scenario_view().logs().size())
	assert_str(viewer.selected_file()["file"]).is_equal("/var/log/auth.log")
	assert_array(viewer.shown_line_numbers()).is_equal([1, 2, 3, 4, 5])
	assert_str(viewer.status_text()).is_equal("/var/log/auth.log  ·  5 of 5 lines")


func test_open_refuses_a_mission_without_logs() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	var viewer: LogViewer = _viewer()
	assert_bool(viewer.open()).is_false()
	assert_bool(viewer.visible).is_false()


func test_esc_closes_and_signals() -> void:
	var viewer: LogViewer = _viewer()
	var closed: Array[bool] = []
	viewer.closed.connect(func() -> void: closed.append(true))
	viewer.open()
	assert_bool(viewer.handle_key(_key(KEY_ESCAPE))).is_true()
	assert_bool(viewer.visible).is_false()
	assert_array(closed).has_size(1)


func test_loading_another_mission_closes_the_viewer() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	Sim.scenario_dir = Sim.SCENARIO_DIR
	Sim.load_scenario_id(MISSION)
	assert_bool(viewer.visible).is_false()


# --- files -------------------------------------------------------------------------


func test_selecting_a_file_shows_its_lines_with_their_own_numbers() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	viewer.select_file(1)
	assert_str(viewer.selected_file()["file"]).is_equal("/var/log/nginx/access.log")
	assert_array(viewer.shown_line_numbers()).is_equal([1, 2, 3])
	assert_str(viewer.output_text()).contains("GET /admin 403")


func test_up_and_down_move_between_files_and_stop_at_the_ends() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	viewer.handle_key(_key(KEY_UP))
	assert_int(viewer.file_count()).is_greater(2)
	assert_str(viewer.selected_file()["file"]).is_equal("/var/log/auth.log")
	viewer.handle_key(_key(KEY_DOWN))
	viewer.handle_key(_key(KEY_DOWN))
	assert_str(viewer.selected_file()["source"]).is_equal("DB1")
	for i: int in 5:
		viewer.handle_key(_key(KEY_DOWN))
	assert_str(viewer.selected_file()["source"]).is_equal("DB1")


# --- filter ------------------------------------------------------------------------


func test_filter_keeps_matching_lines_ignoring_case_and_keeps_file_line_numbers() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	viewer.set_filter_text("ACCEPTED")
	assert_array(viewer.shown_line_numbers()).is_equal([3, 4])
	assert_str(viewer.status_text()).is_equal("/var/log/auth.log  ·  2 of 5 lines")
	viewer.set_filter_text("")
	assert_array(viewer.shown_line_numbers()).is_equal([1, 2, 3, 4, 5])


func test_filter_with_no_match_says_so() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	viewer.set_filter_text("zzz")
	assert_array(viewer.shown_line_numbers()).is_empty()
	assert_str(viewer.status_text()).contains("no lines contain \"zzz\"")


func test_filter_stays_when_the_file_changes_and_resets_when_reopened() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	viewer.set_filter_text("/admin")
	assert_array(viewer.shown_line_numbers()).is_empty()
	viewer.select_file(1)
	assert_str(viewer.filter_text()).is_equal("/admin")
	assert_array(viewer.shown_line_numbers()).is_equal([2])
	viewer.close()
	viewer.open()
	assert_str(viewer.filter_text()).is_empty()
	assert_array(viewer.shown_line_numbers()).is_equal([1, 2, 3, 4, 5])


func test_output_shows_numbers_and_full_text_without_markup() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	var first: String = viewer.output_text().split("\n")[0]
	assert_str(first).contains("1  2026-03-14T02:11:05Z sshd[811]: Failed password for root")
	assert_str(first).not_contains("[color")


# --- highlight ---------------------------------------------------------------------


func test_split_matches_alternates_plain_and_match_ignoring_case() -> void:
	var parts: Array[String] = LogViewer.split_matches("Failed ok FAILED", "failed")
	assert_array(parts).is_equal(["", "Failed", " ok ", "FAILED", ""])
	assert_str("".join(parts)).is_equal("Failed ok FAILED")


func test_split_matches_without_a_needle_or_a_match_is_one_part() -> void:
	assert_array(LogViewer.split_matches("a plain line", "")).is_equal(["a plain line"])
	assert_array(LogViewer.split_matches("a plain line", "zzz")).is_equal(["a plain line"])


func test_brackets_in_log_text_and_needle_are_shown_as_written() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	viewer.set_filter_text("[811]")
	assert_array(viewer.shown_line_numbers()).is_equal([1, 2])
	assert_str(viewer.output_text().split("\n")[0]).contains("sshd[811]: Failed password")
	assert_array(LogViewer.split_matches("x [color=red]bad[/color]", "bad")).is_equal(
		["x [color=red]", "bad", "[/color]"]
	)


# --- wired into the game -----------------------------------------------------------

const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")


func test_aiming_at_the_soc_monitor_and_interacting_opens_the_viewer() -> void:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	var room: Room = main.get_node("Room") as Room
	var monitor: SocMonitor = room.soc_monitor()
	assert_bool(monitor.is_online()).is_true()
	var viewer: LogViewer = main.get_node("LogViewer") as LogViewer
	(main.get_node("Player") as Player).interacted.emit(monitor.target())
	assert_bool(viewer.is_open()).is_true()
	assert_bool((main.get_node("MissionHUD") as CanvasLayer).visible).is_false()
	viewer.close()
	assert_bool((main.get_node("MissionHUD") as CanvasLayer).visible).is_true()


func test_servers_are_placed_in_the_rack_with_a_console() -> void:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	var server: DeviceModel = main.get_node("Room/RoomBuilder/Devices/WEB1") as DeviceModel
	assert_int(server.socket_markers().size()).is_equal(1)
	assert_str(server.socket_markers()[0].port_id()).is_equal("WEB1:Ethernet0")
	assert_str(str(server.console_target().get_meta("console_device"))).is_equal("WEB1")


func test_report_is_offered_only_for_a_mission_with_a_report_and_f2_asks_for_it() -> void:
	var viewer: LogViewer = _viewer()
	var asked: Array[bool] = []
	viewer.report_requested.connect(func() -> void: asked.append(true))
	viewer.open()
	assert_bool(viewer.report_offered()).is_true()
	var f2 := InputEventKey.new()
	f2.pressed = true
	f2.keycode = KEY_F2
	assert_bool(viewer.handle_key(f2)).is_true()
	assert_array(asked).has_size(1)


func test_every_file_label_names_the_device_path_and_line_count() -> void:
	var viewer: LogViewer = _viewer()
	viewer.open()
	assert_str(viewer.file_label(0)).is_equal("WEB1  /var/log/auth.log  (5)")
	assert_str(viewer.file_label(1)).is_equal("WEB1  /var/log/nginx/access.log  (3)")
	assert_str(viewer.file_label(2)).is_equal("DB1  /var/log/auth.log  (2)")
	assert_str(viewer.file_label(9)).is_empty()
