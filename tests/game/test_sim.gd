class_name TestSim
extends GdUnitTestSuite
## The `Sim` autoload (task 1.21). Instances are built straight from the script
## (never added to the tree), so each test gets its own fresh `NetworkSim`.

const SimScript: GDScript = preload("res://game/sim.gd")
const SCENARIO: String = "m1_vlan_ping"
const TEMP_DIR: String = "user://sim_test_scenarios"


func after_test() -> void:
	for name: String in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute("%s/%s" % [TEMP_DIR, name])


# --- helpers ----------------------------------------------------------------


func _sim() -> Node:
	return auto_free(SimScript.new())


func _loaded() -> Node:
	var sim: Node = _sim()
	var r: LoadResult = sim.load_scenario_id(SCENARIO)
	assert_array(r.errors).is_empty()
	return sim


## A Sim reading from the temp folder, which holds `<id>.json` with `text`.
func _sim_with_file(id: String, text: String) -> Node:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var f: FileAccess = FileAccess.open("%s/%s.json" % [TEMP_DIR, id], FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var sim: Node = _sim()
	sim.scenario_dir = TEMP_DIR
	return sim


## Appends "<name>:<args...>" to the returned array each time `sig` fires.
func _record(sig: Signal, tag: String, seen: Array[String]) -> void:
	sig.connect(func(a: Variant = null, b: Variant = null, c: Variant = null) -> void:
		var parts: Array[String] = [tag]
		for v: Variant in [a, b, c]:
			if v != null:
				parts.append(str(v))
		seen.append(":".join(parts)))


func _run(sim: Node, device: String, lines: Array[String]) -> void:
	var session: CliSession = sim.open_session(device)
	for line: String in lines:
		var r: CliResult = session.submit(line)
		assert_bool(r.ok).override_failure_message("%s: '%s' -> %s" % [device, line, r.output]).is_true()


func _solve(sim: Node) -> void:
	assert_bool(sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	_run(sim, "S1", ["enable", "configure terminal", "vlan 20", "name SALES", "exit",
		"interface fa0/2", "switchport mode access", "switchport access vlan 20", "exit",
		"interface gi0/1", "switchport mode trunk", "end"])
	_run(sim, "R1", ["enable", "configure terminal", "interface gi0/0", "no shutdown", "exit",
		"interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
		"interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end"])


# --- before anything is loaded ---------------------------------------------------


func test_there_is_nothing_to_read_before_a_scenario_loads() -> void:
	var sim: Node = _sim()
	assert_object(sim.scenario_view()).is_null()
	assert_object(sim.device_view("R1")).is_null()
	assert_array(sim.objective_states()).is_empty()
	assert_object(sim.open_session("R1")).is_null()


# --- loading by id -----------------------------------------------------------------


func test_loading_by_id_reads_the_scenario_file() -> void:
	var sim: Node = _sim()
	var r: LoadResult = sim.load_scenario_id(SCENARIO)
	assert_bool(r.ok).is_true()
	assert_str(sim.scenario_view().scenario_id()).is_equal(SCENARIO)
	assert_object(sim.device_view("R1")).is_not_null()
	assert_int(sim.spare_cables()).is_equal(1)
	assert_int(sim.objective_states().size()).is_equal(5)


func test_scenario_loaded_fires_once_on_success() -> void:
	var sim: Node = _sim()
	var seen: Array[String] = []
	_record(sim.scenario_loaded, "loaded", seen)
	sim.load_scenario_id(SCENARIO)
	assert_array(seen).is_equal(["loaded:m1_vlan_ping"])


func test_a_missing_file_fails_and_keeps_the_current_scenario() -> void:
	var sim: Node = _loaded()
	var seen: Array[String] = []
	_record(sim.scenario_loaded, "loaded", seen)
	var r: LoadResult = sim.load_scenario_id("no_such_mission")
	assert_bool(r.ok).is_false()
	assert_array(r.errors).is_equal(["res://scenarios/no_such_mission.json: no such scenario file"])
	assert_array(seen).is_empty()
	assert_str(sim.scenario_view().scenario_id()).is_equal(SCENARIO)


func test_ids_that_are_not_a_bare_file_stem_are_refused_without_touching_files() -> void:
	var sim: Node = _loaded()
	for bad: String in ["", "../project", "a/b", "M1_Vlan", "m1_vlan_ping.json", "m1 vlan", "..", "m1-vlan"]:
		var r: LoadResult = sim.load_scenario_id(bad)
		assert_bool(r.ok).override_failure_message("'%s' was accepted" % bad).is_false()
		assert_str(r.errors[0]).starts_with("scenario id '%s'" % bad)
	assert_str(sim.scenario_view().scenario_id()).is_equal(SCENARIO)


func test_bad_json_reports_the_line() -> void:
	var sim: Node = _sim_with_file("broken", "{\n  \"id\": \"broken\",\n  oops\n}")
	var r: LoadResult = sim.load_scenario_id("broken")
	assert_bool(r.ok).is_false()
	assert_int(r.errors.size()).is_equal(1)
	assert_str(r.errors[0]).starts_with("user://sim_test_scenarios/broken.json: line ")  # the number is the parser's
	assert_object(sim.scenario_view()).is_null()


func test_a_json_file_that_is_not_an_object_fails() -> void:
	var sim: Node = _sim_with_file("list", "[1, 2]")
	var r: LoadResult = sim.load_scenario_id("list")
	assert_array(r.errors).is_equal(["user://sim_test_scenarios/list.json: the top level must be a JSON object"])


func test_a_scenario_that_fails_validation_returns_all_its_errors() -> void:
	var sim: Node = _sim_with_file("empty", "{}")
	var seen: Array[String] = []
	_record(sim.scenario_loaded, "loaded", seen)
	var r: LoadResult = sim.load_scenario_id("empty")
	assert_bool(r.ok).is_false()
	assert_int(r.errors.size()).is_greater(1)
	assert_array(seen).is_empty()


func test_the_id_must_match_what_the_file_says() -> void:
	# A copy of the real scenario saved under another name: the validator ties id to file name.
	var text: String = FileAccess.get_file_as_string("res://scenarios/%s.json" % SCENARIO)
	var sim: Node = _sim_with_file("renamed", text)
	var r: LoadResult = sim.load_scenario_id("renamed")
	assert_bool(r.ok).is_false()


func test_reloading_resets_state_and_keeps_relaying_signals() -> void:
	var sim: Node = _loaded()
	assert_bool(sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	assert_int(sim.spare_cables()).is_equal(0)
	assert_bool(sim.load_scenario_id(SCENARIO).ok).is_true()
	assert_int(sim.spare_cables()).is_equal(1)
	assert_object(sim.device_view("PC-B").interface("Eth0")["peer"]).is_null()
	var seen: Array[String] = []
	_record(sim.link_changed, "link", seen)
	sim.connect_link("S1:Fa0/2", "PC-B:Eth0")
	assert_array(seen).is_equal(["link:S1:FastEthernet0/2:PC-B:Ethernet0:true"])


# --- signals --------------------------------------------------------------------------


func test_cabling_re_emits_link_and_interface_state_changes() -> void:
	var sim: Node = _loaded()
	var seen: Array[String] = []
	_record(sim.link_changed, "link", seen)
	_record(sim.interface_state_changed, "state", seen)
	assert_bool(sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	assert_array(seen).contains(["link:S1:FastEthernet0/2:PC-B:Ethernet0:true"])
	assert_array(seen.filter(func(s: String) -> bool: return s.begins_with("state:"))).is_not_empty()
	seen.clear()
	assert_bool(sim.disconnect_link("PC-B:Eth0").ok).is_true()
	assert_array(seen).contains(["link:PC-B:Ethernet0:S1:FastEthernet0/2:false"])


func test_cli_changes_re_emit_config_changed() -> void:
	var sim: Node = _loaded()
	var seen: Array[String] = []
	_record(sim.config_changed, "config", seen)
	_run(sim, "S1", ["enable", "configure terminal", "vlan 20"])
	assert_array(seen).is_equal(["config:S1"])


func test_solving_the_mission_re_emits_objective_updates_and_completion() -> void:
	var sim: Node = _loaded()
	var seen: Array[String] = []
	_record(sim.objective_updated, "obj", seen)
	_record(sim.mission_completed, "done", seen)
	_solve(sim)
	assert_array(seen).contains(["obj:ping_ab:true", "obj:trunk:true", "done:m1_vlan_ping"])
	assert_int(seen.filter(func(s: String) -> bool: return s.begins_with("done:")).size()).is_equal(1)
	assert_bool(sim.objective_states().all(func(o: ObjectiveState) -> bool: return o.passed)).is_true()


# --- pass-throughs ------------------------------------------------------------------------


func test_ping_runs_through_the_owned_network() -> void:
	var sim: Node = _loaded()
	assert_bool(sim.ping("PC-A", "192.168.20.10").success).is_false()
	_solve(sim)
	assert_bool(sim.ping("PC-A", "192.168.20.10").success).is_true()


func test_a_session_works_on_the_owned_network() -> void:
	var sim: Node = _loaded()
	var session: CliSession = sim.open_session("R1")
	assert_object(session).is_not_null()
	assert_bool(session.submit("enable").ok).is_true()
	assert_object(sim.open_session("nope")).is_null()


# --- the real autoload ------------------------------------------------------------------------


func test_the_autoload_is_registered_as_sim() -> void:
	var node: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sim")
	assert_object(node).is_not_null()
	assert_str(node.get_script().resource_path).is_equal("res://game/sim.gd")
