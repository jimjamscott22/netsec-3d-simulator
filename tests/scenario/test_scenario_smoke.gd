class_name TestScenarioSmoke
extends GdUnitTestSuite
## Smoke test for every file in `res://scenarios/` (task 1.20): it loads, at
## least one objective fails at the start, and after the file's own `solution`
## is applied every objective passes. A new scenario file is picked up
## automatically; there is nothing to register here.


func test_there_are_scenario_files_and_m1_is_one_of_them() -> void:
	# Guards against the folder scan silently finding nothing and passing vacuously.
	assert_array(ScenarioRunner.scenario_files()).contains(["m1_vlan_ping.json"])


func test_every_scenario_passes_the_smoke_test() -> void:
	var report: Array[String] = []
	for file_name: String in ScenarioRunner.scenario_files():
		var data: Dictionary = ScenarioRunner.read("%s/%s" % [ScenarioRunner.SCENARIO_DIR, file_name])
		if data.is_empty():
			report.append("%s: not a readable JSON object" % file_name)
			continue
		for problem: String in ScenarioRunner.smoke(data, ScenarioRunner.file_id(file_name)):
			report.append("%s: %s" % [file_name, problem])
	assert_array(report).is_empty()


# --- the `report` solution step (task 2.9) ----------------------------------------

const REPORT_FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"


func _report_fixture(steps: Array) -> Dictionary:
	var data: Dictionary = ScenarioRunner.read(REPORT_FIXTURE)
	# The fixture's config objective already holds at the start; only reports are open.
	data["solution"] = steps
	return data


func test_report_steps_play_the_report_and_complete_the_mission() -> void:
	var data: Dictionary = _report_fixture([
		{"report": {"field": "attacker_ip", "value": "203.0.113.45"}},
		{"report": {"field": "attack_type", "value": "brute force"}},
		{"report": {"field": "compromised_user", "value": "deploy"}},
	])
	assert_array(ScenarioRunner.smoke(data, "m2_fixture")).is_empty()


func test_a_wrong_report_step_is_reported() -> void:
	var data: Dictionary = _report_fixture([
		{"report": {"field": "attacker_ip", "value": "198.51.100.7"}},
	])
	var problems: Array[String] = ScenarioRunner.smoke(data, "m2_fixture")
	assert_str("\n".join(PackedStringArray(problems))).contains("was not the right answer")


func test_a_refused_report_step_is_reported() -> void:
	var data: Dictionary = _report_fixture([
		{"report": {"field": "attacker_ip", "value": "not an ip"}},
	])
	var problems: Array[String] = ScenarioRunner.smoke(data, "m2_fixture")
	assert_str("\n".join(PackedStringArray(problems))).contains("refused (INVALID_VALUE)")
