class_name TestDebriefView
extends GdUnitTestSuite
## NetworkSim.debrief_view() (task 1.30): null during play, filled once the
## mission is completed, and a snapshot of that moment.

const PATH: String = "res://scenarios/m1_vlan_ping.json"


func _data() -> Dictionary:
	var data: Dictionary = ScenarioRunner.read(PATH)
	assert_bool(data.is_empty()).is_false()
	return data


func _loaded(data: Dictionary = _data()) -> NetworkSim:
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(data).errors).is_empty()
	return sim


func _solve(sim: NetworkSim, data: Dictionary = _data()) -> void:
	assert_array(ScenarioRunner.apply_solution(sim, data)).is_empty()


func test_null_before_any_scenario() -> void:
	assert_object(NetworkSim.new().debrief_view()).is_null()


func test_null_during_play() -> void:
	var sim: NetworkSim = _loaded()
	assert_object(sim.debrief_view()).is_null()
	assert_bool(sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	assert_object(sim.debrief_view()).is_null()


func test_filled_after_mission_completed() -> void:
	var data: Dictionary = _data()
	var sim: NetworkSim = _loaded(data)
	var seen_at_signal: Array[DebriefView] = []
	sim.events.mission_completed.connect(
		func(_id: String) -> void: seen_at_signal.append(sim.debrief_view())
	)
	_solve(sim, data)

	var view: DebriefView = sim.debrief_view()
	assert_object(view).is_not_null()
	# Already there when listeners hear `mission_completed`.
	assert_int(seen_at_signal.size()).is_equal(1)
	assert_object(seen_at_signal[0]).is_same(view)
	assert_str(view.scenario_id()).is_equal("m1_vlan_ping")
	assert_str(view.title()).is_equal(data["title"])
	assert_bool(view.completed()).is_true()
	assert_str(view.text()).is_equal(data["debrief"])
	var ids: Array[String] = []
	for o: Dictionary in view.objectives():
		ids.append(o["id"])
		assert_bool(o["passed"]).is_true()
		assert_str(o["description"]).is_not_empty()
	assert_array(ids).is_equal(["ping_ab", "trunk", "sub10", "sub20", "parent_noip"])


func test_is_a_snapshot_of_the_end_of_the_mission() -> void:
	var sim: NetworkSim = _loaded()
	_solve(sim)
	assert_bool(sim.disconnect_link("PC-B:Eth0").ok).is_true()
	assert_bool(sim.objective_states()[0].passed).is_false()
	for o: Dictionary in sim.debrief_view().objectives():
		assert_bool(o["passed"]).is_true()


func test_accessors_return_copies() -> void:
	var sim: NetworkSim = _loaded()
	_solve(sim)
	var objectives: Array[Dictionary] = sim.debrief_view().objectives()
	objectives[0]["passed"] = false
	objectives.clear()
	assert_int(sim.debrief_view().objectives().size()).is_equal(5)
	assert_bool(sim.debrief_view().objectives()[0]["passed"]).is_true()


func test_reload_clears_it() -> void:
	var data: Dictionary = _data()
	var sim: NetworkSim = _loaded(data)
	_solve(sim, data)
	assert_array(sim.load_scenario(data).errors).is_empty()
	assert_object(sim.debrief_view()).is_null()


func test_scenario_without_debrief_text_gives_empty_text() -> void:
	var data: Dictionary = _data()
	data.erase("debrief")
	var sim: NetworkSim = _loaded(data)
	_solve(sim, data)
	assert_str(sim.debrief_view().text()).is_empty()
