class_name TestScenarioRunner
extends GdUnitTestSuite
## Tests for the smoke harness itself (`ScenarioRunner`), using the known-good
## M1 fixture and deliberately broken copies of it. Solution steps in the
## fixture: 0 = cable PC-B, 1 = S1 commands, 2 = R1 commands.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m1.json"
const ID: String = "m1_vlan_ping"


func _data() -> Dictionary:
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	assert_bool(data.is_empty()).override_failure_message("fixture did not parse").is_false()
	return data


func _loaded(data: Dictionary) -> NetworkSim:
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(data, ID).errors).is_empty()
	return sim


# --- file helpers ------------------------------------------------------------


func test_scenario_files_are_sorted_json_names_only() -> void:
	var names: Array[String] = ScenarioRunner.scenario_files()
	var sorted: Array[String] = names.duplicate()
	sorted.sort()
	assert_array(names).is_equal(sorted)
	for name: String in names:
		assert_str(name).ends_with(".json")


func test_file_id_drops_the_extension() -> void:
	assert_str(ScenarioRunner.file_id("m1_vlan_ping.json")).is_equal("m1_vlan_ping")


func test_read_returns_empty_for_missing_or_non_object_files() -> void:
	assert_dict(ScenarioRunner.read("res://scenarios/does_not_exist.json")).is_empty()
	assert_dict(ScenarioRunner.read("res://project.godot")).is_empty()


# --- apply_solution ------------------------------------------------------------


func test_apply_solution_replays_every_step() -> void:
	var data: Dictionary = _data()
	var sim: NetworkSim = _loaded(data)
	assert_array(ScenarioRunner.failing_ids(sim)).is_not_empty()
	assert_array(ScenarioRunner.apply_solution(sim, data)).is_empty()
	assert_array(ScenarioRunner.failing_ids(sim)).is_empty()


func test_apply_solution_reports_a_refused_command_and_stops() -> void:
	var data: Dictionary = _data()
	data["solution"][1]["commands"][2] = "vlan banana"
	var sim: NetworkSim = _loaded(_data())
	var errors: Array[String] = ScenarioRunner.apply_solution(sim, data)
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0]).starts_with("solution[1]: S1: 'vlan banana'")
	# Step 2 (the R1 commands) must not have run, so the subinterface was never made.
	assert_object(sim.interface_at("R1:Gi0/0.10")).is_null()


func test_apply_solution_reports_a_refused_link() -> void:
	var data: Dictionary = _data()
	# The validator would reject this file, so replay the bad solution on a good load.
	data["solution"][0]["link"]["a"] = "R1:Gi0/1"  # reserved by the scenario
	var errors: Array[String] = ScenarioRunner.apply_solution(_loaded(_data()), data)
	assert_array(errors).is_equal(["solution[0]: link R1:Gi0/1 <-> PC-B:Eth0 refused (PORT_RESERVED)"])


func test_apply_solution_reports_an_unknown_device_and_step_type() -> void:
	var sim: NetworkSim = _loaded(_data())
	var unknown_device: Dictionary = {"solution": [{"device": "X9", "commands": ["enable"]}]}
	assert_array(ScenarioRunner.apply_solution(sim, unknown_device)).is_equal(["solution[0]: unknown device 'X9'"])
	var unknown_step: Dictionary = {"solution": [{"nonsense": true}]}
	assert_array(ScenarioRunner.apply_solution(sim, unknown_step)).is_equal(
		["solution[0]: unsupported step type (has neither 'link' nor 'device')"])


# --- smoke ---------------------------------------------------------------------


func test_smoke_passes_for_the_known_good_scenario() -> void:
	assert_array(ScenarioRunner.smoke(_data(), ID)).is_empty()


func test_smoke_reports_load_errors_without_running_anything() -> void:
	var data: Dictionary = _data()
	data.erase("briefing")
	var problems: Array[String] = ScenarioRunner.smoke(data, ID)
	assert_array(problems).is_not_empty()
	assert_str(problems[0]).starts_with("load: ")


func test_smoke_flags_a_filename_that_does_not_match_the_id() -> void:
	var problems: Array[String] = ScenarioRunner.smoke(_data(), "some_other_name")
	assert_array(problems).is_not_empty()
	assert_str(problems[0]).starts_with("load: ")


func test_smoke_flags_a_mission_that_is_complete_at_the_start() -> void:
	# `parent_noip` (Gi0/0 has no IP) already holds before the player does anything.
	var data: Dictionary = _data()
	data["objectives"] = data["objectives"].filter(func(o: Dictionary) -> bool: return o["id"] == "parent_noip")
	var problems: Array[String] = ScenarioRunner.smoke(data, ID)
	assert_array(problems).is_equal(["start: every objective already passes, so the mission is trivial"])


func test_smoke_flags_a_solution_that_does_not_finish_the_mission() -> void:
	var data: Dictionary = _data()
	data["solution"].remove_at(2)  # never configures R1
	var problems: Array[String] = ScenarioRunner.smoke(data, ID)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).starts_with("after solution: objectives still failing: ")
	assert_str(problems[0]).contains("ping_ab")


func test_smoke_stops_at_a_refused_step_and_skips_the_end_check() -> void:
	var data: Dictionary = _data()
	data["solution"][1]["commands"][2] = "vlan banana"
	var problems: Array[String] = ScenarioRunner.smoke(data, ID)
	assert_int(problems.size()).is_equal(1)
	assert_str(problems[0]).starts_with("solution[1]: ")
