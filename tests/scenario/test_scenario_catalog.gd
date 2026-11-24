class_name TestScenarioCatalog
extends GdUnitTestSuite
## summarize_scenario and the pure catalog rules behind mission select (task 2.10).

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const M1: String = "res://scenarios/m1_vlan_ping.json"


func _summary(id: String, sequence: int, title: String = "T") -> ScenarioSummary:
	return ScenarioSummary.valid(id, id, title, sequence)


func _bad(source: String) -> ScenarioSummary:
	return ScenarioSummary.invalid(source, ["devices: required"])


func _ids(missions: Array[ScenarioSummary]) -> Array[String]:
	var ids: Array[String] = []
	for m: ScenarioSummary in missions:
		ids.append(m.id)
	return ids


# --- summarize_scenario ---------------------------------------------------------------


func test_a_valid_scenario_is_summarized_with_its_id_title_and_sequence() -> void:
	var summary: ScenarioSummary = NetworkSim.summarize_scenario(ScenarioRunner.read(M1), "m1_vlan_ping")
	assert_bool(summary.ok()).is_true()
	assert_str(summary.id).is_equal("m1_vlan_ping")
	assert_str(summary.title).is_equal("Day One: Get Them Talking")
	assert_int(summary.sequence).is_equal(1)
	assert_str(summary.source).is_equal("m1_vlan_ping")
	assert_array(summary.errors).is_empty()


func test_the_file_name_is_optional() -> void:
	var summary: ScenarioSummary = NetworkSim.summarize_scenario(ScenarioRunner.read(FIXTURE))
	assert_bool(summary.ok()).is_true()
	assert_int(summary.sequence).is_equal(2)


func test_an_invalid_scenario_carries_its_errors_and_no_title() -> void:
	var data: Dictionary = ScenarioRunner.read(M1)
	data.erase("devices")
	var summary: ScenarioSummary = NetworkSim.summarize_scenario(data, "m1_vlan_ping")
	assert_bool(summary.ok()).is_false()
	assert_array(summary.errors).contains(["devices: required"])
	assert_str(summary.title).is_empty()
	assert_str(summary.id).is_empty()


func test_a_file_name_that_is_not_the_id_is_invalid() -> void:
	var summary: ScenarioSummary = NetworkSim.summarize_scenario(ScenarioRunner.read(M1), "other_name")
	assert_bool(summary.ok()).is_false()


func test_summarizing_changes_nothing() -> void:
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(ScenarioRunner.read(M1)).errors).is_empty()
	NetworkSim.summarize_scenario(ScenarioRunner.read(FIXTURE))
	assert_str(sim.scenario_view().scenario_id()).is_equal("m1_vlan_ping")


# --- the catalog ----------------------------------------------------------------------


func test_missions_are_sorted_by_sequence() -> void:
	var catalog: ScenarioCatalog = ScenarioCatalog.build([_summary("c", 3), _summary("a", 1), _summary("b", 2)])
	assert_array(_ids(catalog.missions)).is_equal(["a", "b", "c"])
	assert_array(catalog.problems).is_empty()


func test_an_invalid_file_is_left_out_and_reported() -> void:
	var catalog: ScenarioCatalog = ScenarioCatalog.build([_summary("a", 1), _bad("broken")])
	assert_array(_ids(catalog.missions)).is_equal(["a"])
	assert_array(catalog.problems).is_equal([
		"broken.json is not a valid scenario and is left out: devices: required"
	])


func test_files_sharing_a_sequence_are_all_left_out_and_reported_once() -> void:
	var catalog: ScenarioCatalog = ScenarioCatalog.build([
		_summary("a", 1), _summary("x", 2), _summary("y", 2), _summary("c", 3),
	])
	assert_array(_ids(catalog.missions)).is_equal(["a", "c"])
	assert_array(catalog.problems).is_equal(["sequence 2 is used by x.json and y.json; none of them is listed"])


func test_an_empty_folder_gives_an_empty_catalog() -> void:
	var catalog: ScenarioCatalog = ScenarioCatalog.build([])
	assert_array(catalog.missions).is_empty()
	assert_array(catalog.problems).is_empty()


# --- locking --------------------------------------------------------------------------


func test_the_first_mission_is_never_locked() -> void:
	var list: Array[ScenarioSummary] = [_summary("a", 1), _summary("b", 2)]
	assert_bool(ScenarioCatalog.is_locked(list, 0, [])).is_false()


func test_a_mission_waits_for_the_one_before_it() -> void:
	var list: Array[ScenarioSummary] = [_summary("a", 1), _summary("b", 2), _summary("c", 3)]
	assert_bool(ScenarioCatalog.is_locked(list, 1, [])).is_true()
	assert_bool(ScenarioCatalog.is_locked(list, 1, ["a"])).is_false()
	# Finishing an earlier mission does not skip the one in between.
	assert_bool(ScenarioCatalog.is_locked(list, 2, ["a"])).is_true()
	assert_bool(ScenarioCatalog.is_locked(list, 2, ["a", "b"])).is_false()
	# Finishing a later one does not unlock an earlier one.
	assert_bool(ScenarioCatalog.is_locked(list, 1, ["c"])).is_true()


func test_an_index_outside_the_list_is_not_locked() -> void:
	var list: Array[ScenarioSummary] = [_summary("a", 1)]
	assert_bool(ScenarioCatalog.is_locked(list, 5, [])).is_false()
	assert_bool(ScenarioCatalog.is_locked(list, -1, [])).is_false()
