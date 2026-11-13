class_name TestProgress
extends GdUnitTestSuite
## The `Progress` autoload (task 1.31). Most tests build fresh instances from
## the script, pointed at a temp file. The last section checks the real autoload
## marks a mission done when `Sim` reports it completed.

const ProgressScript: GDScript = preload("res://game/progress.gd")
const TEMP_DIR: String = "user://progress_test"
const SAVE: String = TEMP_DIR + "/progress.json"
const MISSION: String = "m1_vlan_ping"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_delete_save()


func after_test() -> void:
	_delete_save()
	Progress.close()
	Sim.load_scenario_id(MISSION)


func _delete_save() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)


func _progress() -> Node:
	return auto_free(ProgressScript.new())


func _opened() -> Node:
	var p: Node = _progress()
	p.open(SAVE)
	return p


func _write(text: String) -> void:
	var f: FileAccess = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _saved() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SAVE)) as Dictionary


# --- memory only ----------------------------------------------------------------


func test_starts_in_memory_with_defaults_and_writes_nothing() -> void:
	var p: Node = _progress()
	assert_bool(p.is_open()).is_false()
	assert_array(p.completed_ids()).is_empty()
	assert_float(p.look_sensitivity()).is_equal(1.0)
	assert_bool(p.fullscreen()).is_false()
	assert_float(p.volume()).is_equal(0.8)
	p.mark_completed(MISSION)
	p.set_volume(0.3)
	assert_bool(p.is_completed(MISSION)).is_true()
	assert_float(p.volume()).is_equal(0.3)
	assert_bool(FileAccess.file_exists(SAVE)).is_false()


# --- reading --------------------------------------------------------------------


func test_a_missing_save_is_a_fresh_start_and_is_not_created_until_a_change() -> void:
	var p: Node = _opened()
	assert_bool(p.is_open()).is_true()
	assert_str(p.path()).is_equal(SAVE)
	assert_array(p.completed_ids()).is_empty()
	assert_bool(FileAccess.file_exists(SAVE)).is_false()


func test_reads_completed_missions_and_settings() -> void:
	_write('{"version": 1, "completed": ["m1_vlan_ping"], '
		+ '"settings": {"look_sensitivity": 1.5, "fullscreen": true, "volume": 0.25}}')
	var p: Node = _opened()
	assert_bool(p.is_completed(MISSION)).is_true()
	assert_bool(p.is_completed("m2_log_triage")).is_false()
	assert_float(p.look_sensitivity()).is_equal(1.5)
	assert_bool(p.fullscreen()).is_true()
	assert_float(p.volume()).is_equal(0.25)


func test_a_corrupt_save_starts_fresh() -> void:
	_write("{not json")
	var p: Node = _opened()
	assert_array(p.completed_ids()).is_empty()
	assert_float(p.look_sensitivity()).is_equal(1.0)


func test_bad_values_are_ignored_and_out_of_range_ones_clamped() -> void:
	_write('{"completed": ["m1_vlan_ping", 7, "", "m1_vlan_ping"], '
		+ '"settings": {"look_sensitivity": 99, "fullscreen": "yes", "volume": -2}}')
	var p: Node = _opened()
	assert_array(p.completed_ids()).contains_exactly([MISSION])
	assert_float(p.look_sensitivity()).is_equal(3.0)
	assert_bool(p.fullscreen()).is_false()
	assert_float(p.volume()).is_equal(0.0)


func test_settings_that_are_not_an_object_keep_the_defaults() -> void:
	_write('{"completed": "m1_vlan_ping", "settings": [1, 2]}')
	var p: Node = _opened()
	assert_array(p.completed_ids()).is_empty()
	assert_float(p.volume()).is_equal(0.8)


func test_opening_replaces_whatever_was_in_memory() -> void:
	var p: Node = _progress()
	p.mark_completed(MISSION)
	p.open(SAVE)
	assert_bool(p.is_completed(MISSION)).is_false()


# --- saving ---------------------------------------------------------------------


func test_completing_a_mission_saves_it_once() -> void:
	var p: Node = _opened()
	p.mark_completed(MISSION)
	p.mark_completed(MISSION)
	assert_array(_saved()["completed"]).contains_exactly([MISSION])
	assert_int(int(_saved()["version"])).is_equal(1)

	var again: Node = _progress()
	again.open(SAVE)
	assert_bool(again.is_completed(MISSION)).is_true()


func test_changing_a_setting_saves_it_and_emits_once() -> void:
	var p: Node = _opened()
	var count: Array[int] = [0]
	p.settings_changed.connect(func() -> void: count[0] += 1)
	p.set_look_sensitivity(2.0)
	p.set_look_sensitivity(2.0)
	p.set_fullscreen(true)
	p.set_volume(0.5)
	assert_int(count[0]).is_equal(3)
	var settings: Dictionary = _saved()["settings"]
	assert_float(settings["look_sensitivity"]).is_equal(2.0)
	assert_bool(settings["fullscreen"]).is_true()
	assert_float(settings["volume"]).is_equal(0.5)

	var again: Node = _progress()
	again.open(SAVE)
	assert_float(again.look_sensitivity()).is_equal(2.0)
	assert_bool(again.fullscreen()).is_true()
	assert_float(again.volume()).is_equal(0.5)


func test_setters_clamp() -> void:
	var p: Node = _progress()
	p.set_look_sensitivity(0.0)
	assert_float(p.look_sensitivity()).is_equal(0.25)
	p.set_look_sensitivity(10.0)
	assert_float(p.look_sensitivity()).is_equal(3.0)
	p.set_volume(1.5)
	assert_float(p.volume()).is_equal(1.0)


func test_volume_drives_the_master_bus() -> void:
	var p: Node = _progress()
	var master: int = AudioServer.get_bus_index("Master")
	p.set_volume(0.5)
	assert_float(AudioServer.get_bus_volume_db(master)).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_bool(AudioServer.is_bus_mute(master)).is_false()
	p.set_volume(0.0)
	assert_bool(AudioServer.is_bus_mute(master)).is_true()
	p.set_volume(0.8)


func test_close_goes_back_to_memory_with_defaults() -> void:
	var p: Node = _opened()
	p.mark_completed(MISSION)
	p.close()
	assert_bool(p.is_open()).is_false()
	assert_bool(p.is_completed(MISSION)).is_false()
	p.set_volume(0.1)
	assert_float(_saved()["settings"]["volume"]).is_equal(0.8)


# --- the autoload ---------------------------------------------------------------


func test_the_autoload_saves_a_completed_mission() -> void:
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	Progress.open(SAVE)
	assert_bool(Progress.is_completed(MISSION)).is_false()
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	for pair: Array in [
		["S1", ["enable", "configure terminal", "vlan 20", "name SALES", "exit",
			"interface fa0/2", "switchport mode access", "switchport access vlan 20", "exit",
			"interface gi0/1", "switchport mode trunk", "end"]],
		["R1", ["enable", "configure terminal", "interface gi0/0", "no shutdown", "exit",
			"interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
			"interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end"]],
	]:
		var session: CliSession = Sim.open_session(pair[0])
		for line: String in pair[1]:
			assert_bool(session.submit(line).ok).override_failure_message(line).is_true()
	assert_object(Sim.debrief_view()).is_not_null()
	assert_bool(Progress.is_completed(MISSION)).is_true()
	assert_array(_saved()["completed"]).contains_exactly([MISSION])
