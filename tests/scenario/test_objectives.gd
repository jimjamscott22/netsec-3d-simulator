class_name TestObjectives
extends GdUnitTestSuite
## Objective evaluation on the known-good M1 fixture. The fixture's own
## `solution` is replayed step by step through the real CLI, so the signal order
## below is what the HUD would see while a player works through the mission.
## Indices into the solution: 0 = cable PC-B, 1 = S1 commands, 2 = R1 commands.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m1.json"
const FILE_ID: String = "m1_vlan_ping"

const LINK: int = 0
const S1_STEP: int = 1
const R1_STEP: int = 2


# --- helpers ----------------------------------------------------------------


func _data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_bool(parsed is Dictionary).override_failure_message("fixture did not parse").is_true()
	return parsed


func _load(data: Dictionary) -> NetworkSim:
	var sim := NetworkSim.new()
	var result: LoadResult = sim.load_scenario(data, FILE_ID)
	assert_array(result.errors).is_empty()
	return sim


func _sim() -> NetworkSim:
	return _load(_data())


## The fixture with its objectives replaced.
func _sim_with(objectives: Array) -> NetworkSim:
	var data: Dictionary = _data()
	data["objectives"] = objectives
	return _load(data)


func _config(id: String, device: String, path: Variant, equals: Variant) -> Dictionary:
	return {"id": id, "type": "config", "description": id, "device": device, "path": path, "equals": equals}


func _ping(id: String, from: String, to_ip: String, extra: Dictionary = {}) -> Dictionary:
	var obj: Dictionary = {"id": id, "type": "ping", "description": id, "from": from, "to_ip": to_ip}
	obj.merge(extra)
	return obj


## Applies one step of the fixture's solution.
func _apply(sim: NetworkSim, data: Dictionary, index: int) -> void:
	var step: Dictionary = data["solution"][index]
	if step.has("link"):
		var r: LinkResult = sim.connect_link(step["link"]["a"], step["link"]["b"])
		assert_bool(r.ok).override_failure_message("solution link rejected").is_true()
		return
	var session: CliSession = sim.open_session(step["device"])
	for line: String in step["commands"]:
		var result: CliResult = session.submit(line)
		assert_bool(result.ok).override_failure_message("%s: '%s' -> %s" % [step["device"], line, result.output]).is_true()


func _solve(sim: NetworkSim, data: Dictionary, order: Array[int] = [LINK, S1_STEP, R1_STEP]) -> void:
	for index in order:
		_apply(sim, data, index)


## Every objective_updated and mission_completed, in order, as "<id>:<passed>"
## and "completed:<scenario id>".
func _record(sim: NetworkSim) -> Array[String]:
	var seen: Array[String] = []
	sim.events.objective_updated.connect(func(id: String, passed: bool) -> void: seen.append("%s:%s" % [id, passed]))
	sim.events.mission_completed.connect(func(scenario_id: String) -> void: seen.append("completed:%s" % scenario_id))
	return seen


func _state(sim: NetworkSim, id: String) -> ObjectiveState:
	for s: ObjectiveState in sim.objective_states():
		if s.id == id:
			return s
	fail("no objective %s" % id)
	return null


func _passes(sim: NetworkSim, id: String) -> bool:
	return _state(sim, id).passed


# --- states and fields -------------------------------------------------------


func test_there_are_no_states_before_a_scenario_loads() -> void:
	assert_array(NetworkSim.new().objective_states()).is_empty()


func test_states_follow_file_order_and_carry_the_static_fields() -> void:
	var states: Array[ObjectiveState] = _sim().objective_states()
	assert_array(states.map(func(s: ObjectiveState) -> String: return s.id)).is_equal(["ping_ab", "trunk", "sub10", "sub20", "parent_noip"])
	assert_int(states[0].type).is_equal(ObjectiveState.Type.PING)
	assert_int(states[1].type).is_equal(ObjectiveState.Type.CONFIG)
	assert_str(states[0].description).is_equal("PC-A can ping PC-B through the router")
	for s in states:
		assert_int(s.order).is_equal(0)
		assert_bool(s.locked).is_false()
		assert_bool(s.failed).is_false()


func test_states_at_the_start_of_the_mission() -> void:
	var sim := _sim()
	# parent_noip is already true: Gi0/0 has no address to begin with.
	assert_bool(_passes(sim, "ping_ab")).is_false()
	assert_bool(_passes(sim, "trunk")).is_false()
	assert_bool(_passes(sim, "sub10")).is_false()
	assert_bool(_passes(sim, "sub20")).is_false()
	assert_bool(_passes(sim, "parent_noip")).is_true()


func test_a_failing_ping_reports_the_resolver_reason_and_its_hint() -> void:
	var sim := _sim_with([_ping("b_to_a", "PC-B", "192.168.10.10")])
	# PC-B has no cable yet.
	var s: ObjectiveState = _state(sim, "b_to_a")
	assert_bool(s.passed).is_false()
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NO_LINK)
	assert_str(s.hint).is_equal("PC-B isn't cabled to anything yet.")


func test_a_failing_ping_whose_reason_has_no_hint_shows_none() -> void:
	var data: Dictionary = _data()
	data["hints"] = []
	data["objectives"] = [_ping("b_to_a", "PC-B", "192.168.10.10")]
	var s: ObjectiveState = _state(_load(data), "b_to_a")
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NO_LINK)
	assert_str(s.hint).is_equal("")


func test_config_objectives_have_no_fail_reason_or_hint() -> void:
	var s: ObjectiveState = _state(_sim(), "trunk")
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NONE)
	assert_str(s.hint).is_equal("")


func test_a_passing_ping_has_no_fail_reason_hint_or_detail() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	_solve(sim, data)
	var s: ObjectiveState = _state(sim, "ping_ab")
	assert_bool(s.passed).is_true()
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NONE)
	assert_str(s.hint).is_equal("")
	assert_str(s.detail).is_equal("")


func test_objective_states_are_fresh_copies() -> void:
	var sim := _sim()
	var first: Array[ObjectiveState] = sim.objective_states()
	first[0].passed = true
	first[0].description = "changed"
	first.clear()
	var again: Array[ObjectiveState] = sim.objective_states()
	assert_int(again.size()).is_equal(5)
	assert_bool(again[0].passed).is_false()
	assert_str(again[0].description).is_equal("PC-A can ping PC-B through the router")


# --- ping objectives ---------------------------------------------------------


func test_to_device_fails_when_another_device_answers_to_ip() -> void:
	var data: Dictionary = _data()
	data["objectives"] = [_ping("wrong_owner", "PC-A", "192.168.10.1", {"to_device": "PC-B"})]
	var sim := _load(data)
	_solve(sim, data)
	# R1's subinterface owns 192.168.10.1, so the ping succeeds, but not at PC-B.
	assert_bool(sim.ping("PC-A", "192.168.10.1").success).is_true()
	var s: ObjectiveState = _state(sim, "wrong_owner")
	assert_bool(s.passed).is_false()
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NONE)
	assert_str(s.detail).is_equal("reached, but R1 answered, not PC-B")


func test_to_device_passes_when_it_is_the_last_hop() -> void:
	var data: Dictionary = _data()
	data["objectives"] = [_ping("right_owner", "PC-A", "192.168.20.10", {"to_device": "PC-B"})]
	var sim := _load(data)
	_solve(sim, data)
	assert_bool(_passes(sim, "right_owner")).is_true()


func test_via_fails_when_the_ping_succeeds_without_the_named_router() -> void:
	# PC-B is moved into PC-A's subnet and VLAN, so a pure L2 path works with the
	# router still shut down.
	var data: Dictionary = _data()
	data["devices"][3]["config"]["ip"] = "192.168.10.20"
	data["devices"][1]["config"]["interfaces"]["Fa0/2"] = {"mode": "access", "access_vlan": 10}
	data["links"].append({"a": "S1:Fa0/2", "b": "PC-B:Eth0", "locked": true})
	data["objectives"] = [_ping("l2_only", "PC-A", "192.168.10.20", {"to_device": "PC-B", "via": "R1"})]
	var sim := _load(data)
	assert_bool(sim.ping("PC-A", "192.168.10.20").success).is_true()
	var s: ObjectiveState = _state(sim, "l2_only")
	assert_bool(s.passed).is_false()
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NONE)
	assert_str(s.detail).is_equal("reached, but not through R1")


func test_via_passes_when_the_router_is_on_the_path() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	_solve(sim, data)
	assert_bool(_passes(sim, "ping_ab")).is_true()


# --- config objectives -------------------------------------------------------


func test_config_values_that_match_at_the_start() -> void:
	var sim := _sim_with([
		_config("hostname_word", "R1", "hostname", "Router"),
		_config("hostname_list", "R1", ["hostname"], "Router"),
		_config("short_name", "R1", ["interfaces", "g0/0", "admin_up"], false),
		_config("absent_sub", "R1", ["interfaces", "Gi0/0.10"], null),
		_config("object_with_nulls", "R1", ["interfaces", "Gi0/0"], {"ip": null, "mask": null, "admin_up": false}),
		_config("access_port", "S1", ["interfaces", "Fa0/1"], {"mode": "access", "access_vlan": 10}),
		_config("allows_all", "S1", ["interfaces", "Gi0/1", "trunk_allowed"], null),
		_config("vlan_name", "S1", ["vlans", "10"], "ACCOUNTING"),
		_config("vlan_absent", "S1", ["vlans", "20"], null),
		_config("host_gateway", "PC-A", ["gateway"], "192.168.10.1"),
		_config("host_ip", "PC-A", ["ip"], "192.168.10.10"),
		_config("host_mask", "PC-B", ["mask"], "255.255.255.0"),
		_config("host_locked", "PC-A", ["locked"], true),
	])
	for s in sim.objective_states():
		assert_bool(s.passed).override_failure_message("%s should pass" % s.id).is_true()


func test_config_values_that_do_not_match_at_the_start() -> void:
	var sim := _sim_with([
		_config("wrong_hostname", "R1", "hostname", "Switch"),
		_config("wrong_vlan", "S1", ["interfaces", "Fa0/1", "access_vlan"], 20),
		_config("wrong_vlan_name", "S1", ["vlans", "10"], "SALES"),
		_config("vlan_not_absent", "S1", ["vlans", "10"], null),
		_config("not_unlocked", "PC-A", ["locked"], false),
		_config("wrong_ip", "R1", ["interfaces", "Gi0/0"], {"ip": "1.2.3.4"}),
		_config("sub_missing", "R1", ["interfaces", "Gi0/0.10"], {"dot1q_vlan": 10}),
		_config("not_restricted", "S1", ["interfaces", "Gi0/1", "trunk_allowed"], [10]),
		_config("port_not_absent", "R1", ["interfaces", "Gi0/0"], null),
		_config("not_trunk", "S1", ["interfaces", "Gi0/1", "mode"], "trunk"),
	])
	for s in sim.objective_states():
		assert_bool(s.passed).override_failure_message("%s should not pass" % s.id).is_false()


func test_an_object_equals_matches_when_every_key_matches() -> void:
	var data: Dictionary = _data()
	data["objectives"] = [
		_config("subset", "R1", ["interfaces", "Gi0/0.10"], {"ip": "192.168.10.1"}),
		_config("all_keys", "R1", ["interfaces", "Gi0/0.10"], {"dot1q_vlan": 10, "ip": "192.168.10.1", "mask": "255.255.255.0"}),
		_config("one_wrong", "R1", ["interfaces", "Gi0/0.10"], {"dot1q_vlan": 20, "ip": "192.168.10.1"}),
	]
	var sim := _load(data)
	_apply(sim, data, R1_STEP)
	assert_bool(_passes(sim, "subset")).is_true()
	assert_bool(_passes(sim, "all_keys")).is_true()
	assert_bool(_passes(sim, "one_wrong")).is_false()


func test_trunk_allowed_matches_as_a_set() -> void:
	var data: Dictionary = _data()
	data["devices"][1]["config"]["interfaces"]["Gi0/1"] = {"mode": "trunk", "trunk_allowed": [20, 10]}
	data["objectives"] = [
		_config("same_set", "S1", ["interfaces", "Gi0/1", "trunk_allowed"], [10, 20]),
		_config("subset", "S1", ["interfaces", "Gi0/1", "trunk_allowed"], [10]),
		_config("superset", "S1", ["interfaces", "Gi0/1", "trunk_allowed"], [10, 20, 30]),
		_config("not_all", "S1", ["interfaces", "Gi0/1", "trunk_allowed"], null),
	]
	var sim := _load(data)
	assert_bool(_passes(sim, "same_set")).is_true()
	assert_bool(_passes(sim, "subset")).is_false()
	assert_bool(_passes(sim, "superset")).is_false()
	assert_bool(_passes(sim, "not_all")).is_false()


func test_a_subinterface_objective_follows_the_player_creating_it() -> void:
	var sim := _sim_with([_config("absent_sub", "R1", ["interfaces", "Gi0/0.10"], null)])
	assert_bool(_passes(sim, "absent_sub")).is_true()
	sim.create_subinterface("R1", "Gi0/0.10")
	assert_bool(_passes(sim, "absent_sub")).is_false()


# --- signals -----------------------------------------------------------------


func test_loading_emits_no_objective_signals() -> void:
	var sim := NetworkSim.new()
	var seen: Array[String] = _record(sim)
	sim.load_scenario(_data(), FILE_ID)
	assert_array(seen).is_empty()


func test_solving_the_mission_emits_each_change_once_then_completes() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	var seen: Array[String] = _record(sim)
	_solve(sim, data)
	# Within one evaluation, changes come in file order: ping_ab before sub20.
	assert_array(seen).is_equal([
		"trunk:true",
		"sub10:true",
		"ping_ab:true",
		"sub20:true",
		"completed:m1_vlan_ping",
	])


func test_cabling_a_port_re_evaluates_the_objectives() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	_solve(sim, data, [S1_STEP, R1_STEP])
	var seen: Array[String] = _record(sim)
	assert_bool(_passes(sim, "ping_ab")).is_false()
	_apply(sim, data, LINK)
	assert_array(seen).is_equal(["ping_ab:true", "completed:m1_vlan_ping"])


func test_unplugging_a_cable_re_evaluates_the_objectives() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	_solve(sim, data)
	var seen: Array[String] = _record(sim)
	assert_bool(sim.disconnect_link("PC-B:Eth0").ok).is_true()
	assert_array(seen).is_equal(["ping_ab:false"])
	assert_bool(_passes(sim, "ping_ab")).is_false()


func test_a_change_that_flips_nothing_emits_nothing() -> void:
	var sim := _sim()
	var seen: Array[String] = _record(sim)
	sim.set_hostname("S1", "Renamed")
	sim.set_admin_up("R1:Gi0/1", true)
	assert_array(seen).is_empty()


func test_mission_completed_fires_once_even_if_config_keeps_changing() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	_solve(sim, data)
	var seen: Array[String] = _record(sim)
	sim.set_hostname("S1", "Renamed")
	sim.set_hostname("R1", "Renamed")
	sim.create_vlan("S1", 30)
	assert_array(seen).is_empty()


func test_loading_again_lets_the_mission_complete_again() -> void:
	var data: Dictionary = _data()
	var sim := _load(data)
	var seen: Array[String] = _record(sim)
	_solve(sim, data)
	assert_bool(sim.load_scenario(data, FILE_ID).ok).is_true()
	_solve(sim, data)
	var completions: Array = seen.filter(func(e: String) -> bool: return e.begins_with("completed:"))
	assert_int(completions.size()).is_equal(2)


# --- order locking -----------------------------------------------------------


func _ordered_sim() -> NetworkSim:
	var data: Dictionary = _data()
	# trunk (1) unlocks parent_noip (2), which is already true at the start.
	data["objectives"][1]["order"] = 1
	data["objectives"][4]["order"] = 2
	return _load(data)


func test_an_ordered_objective_that_is_already_true_stays_locked() -> void:
	var sim := _ordered_sim()
	var trunk: ObjectiveState = _state(sim, "trunk")
	assert_int(trunk.order).is_equal(1)
	assert_bool(trunk.locked).is_false()
	var parent: ObjectiveState = _state(sim, "parent_noip")
	assert_int(parent.order).is_equal(2)
	assert_bool(parent.locked).is_true()
	assert_bool(parent.passed).is_false()


func test_an_ordered_objective_unlocks_and_re_locks_with_the_one_before_it() -> void:
	var sim := _ordered_sim()
	var seen: Array[String] = _record(sim)
	var session: CliSession = sim.open_session("S1")
	for line in ["enable", "configure terminal", "interface gi0/1", "switchport mode trunk"]:
		session.submit(line)
	assert_array(seen).is_equal(["trunk:true", "parent_noip:true"])
	assert_bool(_state(sim, "parent_noip").locked).is_false()
	assert_bool(_state(sim, "parent_noip").passed).is_true()

	session.submit("switchport mode access")
	assert_array(seen).is_equal(["trunk:true", "parent_noip:true", "trunk:false", "parent_noip:false"])
	assert_bool(_state(sim, "parent_noip").locked).is_true()
	assert_bool(_state(sim, "parent_noip").passed).is_false()


func test_a_locked_objective_blocks_the_ones_after_it() -> void:
	var data: Dictionary = _data()
	data["objectives"][1]["order"] = 1  # trunk, fails at the start
	data["objectives"][4]["order"] = 2  # parent_noip, true but locked behind trunk
	data["objectives"][3]["order"] = 3  # sub20 waits for parent_noip, which can't pass yet
	var sim := _load(data)
	assert_bool(_state(sim, "parent_noip").locked).is_true()
	assert_bool(_state(sim, "sub20").locked).is_true()


func test_a_locked_ping_objective_shows_no_reason_or_hint() -> void:
	var data: Dictionary = _data()
	data["objectives"][0]["order"] = 2  # ping_ab, which fails at the start
	data["objectives"][1]["order"] = 1
	var s: ObjectiveState = _state(_load(data), "ping_ab")
	assert_bool(s.locked).is_true()
	assert_bool(s.passed).is_false()
	assert_int(s.fail_reason).is_equal(PingResult.FailReason.NONE)
	assert_str(s.hint).is_equal("")


func test_objectives_without_order_are_never_locked() -> void:
	var states: Array[ObjectiveState] = _ordered_sim().objective_states()
	for s in states:
		if s.order == 0:
			assert_bool(s.locked).is_false()


func test_a_mission_with_ordered_objectives_completes_in_the_usual_way() -> void:
	var data: Dictionary = _data()
	data["objectives"][1]["order"] = 1
	data["objectives"][4]["order"] = 2
	var sim := _load(data)
	var seen: Array[String] = _record(sim)
	_solve(sim, data)
	assert_array(seen).is_equal([
		"trunk:true",
		"parent_noip:true",
		"sub10:true",
		"ping_ab:true",
		"sub20:true",
		"completed:m1_vlan_ping",
	])
