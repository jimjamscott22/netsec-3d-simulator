class_name TestSimCatalog
extends GdUnitTestSuite
## `Sim.scenario_catalog()` (task 2.10): reads every file in the scenario folder.
## Instances are built from the script, so each test has its own `Sim`.

const SimScript: GDScript = preload("res://game/sim.gd")
const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const TEMP_DIR: String = "user://sim_catalog_test_scenarios"


func before_test() -> void:
	_clear()
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)


func after_test() -> void:
	_clear()


func _clear() -> void:
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		for name: String in DirAccess.get_files_at(TEMP_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEMP_DIR, name])


func _sim(dir: String = TEMP_DIR) -> Node:
	var sim: Node = auto_free(SimScript.new())
	sim.scenario_dir = dir
	return sim


func _write(file_name: String, text: String) -> void:
	var f: FileAccess = FileAccess.open("%s/%s" % [TEMP_DIR, file_name], FileAccess.WRITE)
	f.store_string(text)
	f.close()


## The M2 fixture saved as `<id>.json` with this `id` and `sequence`.
func _write_scenario(id: String, sequence: int) -> void:
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	data["id"] = id
	data["sequence"] = sequence
	data["title"] = "Title of %s" % id
	_write(id + ".json", JSON.stringify(data))


func _ids(missions: Array[ScenarioSummary]) -> Array[String]:
	var ids: Array[String] = []
	for m: ScenarioSummary in missions:
		ids.append(m.id)
	return ids


func test_the_real_folder_lists_the_missions_in_order() -> void:
	var sim: Node = _sim(SimScript.SCENARIO_DIR)
	var ids: Array[String] = _ids(sim.scenario_catalog())
	assert_array(ids.slice(0, 2)).is_equal(["m1_vlan_ping", "m2_log_triage"])
	assert_array(sim.catalog_problems()).is_empty()


func test_summaries_carry_the_title_and_sequence() -> void:
	_write_scenario("m2_b", 2)
	_write_scenario("m1_a", 1)
	var missions: Array[ScenarioSummary] = _sim().scenario_catalog()
	assert_array(_ids(missions)).is_equal(["m1_a", "m2_b"])
	assert_str(missions[1].title).is_equal("Title of m2_b")
	assert_int(missions[1].sequence).is_equal(2)


func test_invalid_files_are_skipped_and_reported() -> void:
	_write_scenario("m1_a", 1)
	_write("broken.json", "{ not json")
	_write("list.json", "[1, 2]")
	_write("empty_obj.json", "{}")
	_write("notes.txt", "not a scenario")
	var sim: Node = _sim()
	assert_array(_ids(sim.scenario_catalog())).is_equal(["m1_a"])
	var problems: Array[String] = sim.catalog_problems()
	assert_int(problems.size()).is_equal(3)
	var joined: String = "\n".join(PackedStringArray(problems))
	assert_str(joined).contains("broken.json is not a valid scenario")
	assert_str(joined).contains("list.json is not a valid scenario")
	assert_str(joined).contains("empty_obj.json is not a valid scenario")
	assert_str(joined).not_contains("notes")


func test_a_file_whose_name_is_not_its_id_is_skipped() -> void:
	_write_scenario("m1_a", 1)
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	data["id"] = "something_else"
	_write("m2_b.json", JSON.stringify(data))
	var sim: Node = _sim()
	assert_array(_ids(sim.scenario_catalog())).is_equal(["m1_a"])
	assert_int(sim.catalog_problems().size()).is_equal(1)


func test_a_duplicate_sequence_leaves_both_files_out_and_reports_it() -> void:
	_write_scenario("m1_a", 1)
	_write_scenario("m2_a", 2)
	_write_scenario("m2_b", 2)
	_write_scenario("m3_a", 3)
	var sim: Node = _sim()
	assert_array(_ids(sim.scenario_catalog())).is_equal(["m1_a", "m3_a"])
	assert_array(sim.catalog_problems()).is_equal(["sequence 2 is used by m2_a.json and m2_b.json; none of them is listed"])


func test_an_empty_or_missing_folder_gives_no_missions() -> void:
	assert_array(_sim().scenario_catalog()).is_empty()
	assert_array(_sim("user://no_such_scenario_folder").scenario_catalog()).is_empty()


func test_problems_are_for_the_last_call_only() -> void:
	_write("broken.json", "{")
	var sim: Node = _sim()
	sim.scenario_catalog()
	assert_int(sim.catalog_problems().size()).is_equal(1)
	_clear()
	sim.scenario_catalog()
	assert_array(sim.catalog_problems()).is_empty()


func test_reading_the_catalog_does_not_touch_the_loaded_mission() -> void:
	_write_scenario("m1_a", 1)
	var sim: Node = _sim()
	assert_array(sim.load_scenario_id("m1_a").errors).is_empty()
	sim.scenario_catalog()
	assert_str(sim.scenario_view().scenario_id()).is_equal("m1_a")


func test_the_facade_answers_the_lock_question() -> void:
	_write_scenario("m1_a", 1)
	_write_scenario("m2_b", 2)
	var sim: Node = _sim()
	var missions: Array[ScenarioSummary] = sim.scenario_catalog()
	assert_bool(sim.is_mission_locked(missions, 0, [])).is_false()
	assert_bool(sim.is_mission_locked(missions, 1, [])).is_true()
	assert_bool(sim.is_mission_locked(missions, 1, ["m1_a"])).is_false()
