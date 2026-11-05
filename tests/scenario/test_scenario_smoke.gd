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
