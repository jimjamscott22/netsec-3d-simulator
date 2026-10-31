class_name TestScenarioLoader
extends GdUnitTestSuite
## Loads the known-good M1 fixture (a copy of the schema's full example; the
## real scenarios/m1_vlan_ping.json arrives in task 1.19) through
## NetworkSim.load_scenario and checks what the world and UI would see.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m1.json"
const FILE_ID: String = "m1_vlan_ping"

const R1: int = 0
const S1: int = 1


# --- helpers ----------------------------------------------------------------


func _data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_bool(parsed is Dictionary).override_failure_message("fixture did not parse").is_true()
	return parsed


func _loaded(data: Dictionary = _data()) -> NetworkSim:
	var sim := NetworkSim.new()
	var result: LoadResult = sim.load_scenario(data, FILE_ID)
	assert_array(result.errors).is_empty()
	assert_bool(result.ok).is_true()
	return sim


func _entry(view: ScenarioView, id: String) -> Dictionary:
	for e: Dictionary in view.devices():
		if e["id"] == id:
			return e
	fail("no device %s in the scenario view" % id)
	return {}


# --- loading ----------------------------------------------------------------


func test_the_m1_example_loads() -> void:
	var sim := _loaded()
	assert_array(sim.device_ids()).is_equal(["PC-A", "PC-B", "R1", "S1"])
	assert_int(sim.spare_cables()).is_equal(1)
	assert_int(sim.get_device("R1").kind()).is_equal(Device.Kind.ROUTER)
	assert_int(sim.get_device("PC-A").kind()).is_equal(Device.Kind.HOST)


func test_a_broken_file_leaves_the_sim_empty() -> void:
	var data: Dictionary = _data()
	data.erase("title")
	data["links"][0]["a"] = "R9:Gi0/0"
	var sim := NetworkSim.new()
	var result: LoadResult = sim.load_scenario(data, FILE_ID)
	assert_bool(result.ok).is_false()
	assert_array(result.errors).is_equal(ScenarioValidator.validate(data, FILE_ID))
	assert_array(result.errors).has_size(2)
	assert_array(sim.device_ids()).is_empty()
	assert_int(sim.spare_cables()).is_equal(0)
	assert_object(sim.scenario_view()).is_null()


func test_a_broken_file_does_not_disturb_a_loaded_scenario() -> void:
	var sim := _loaded()
	var data: Dictionary = _data()
	data["devices"].clear()
	assert_bool(sim.load_scenario(data, FILE_ID).ok).is_false()
	assert_array(sim.device_ids()).is_equal(["PC-A", "PC-B", "R1", "S1"])
	assert_str(sim.scenario_view().title()).is_equal("Day One: Get Them Talking")


func test_a_file_id_that_does_not_match_the_id_is_rejected() -> void:
	var sim := NetworkSim.new()
	assert_bool(sim.load_scenario(_data(), "other_name").ok).is_false()
	assert_array(sim.device_ids()).is_empty()


func test_loading_again_replaces_the_state_instead_of_adding_to_it() -> void:
	var sim := _loaded()
	assert_bool(sim.connect_link("PC-B:Eth0", "S1:Fa0/2").ok).is_true()
	assert_int(sim.spare_cables()).is_equal(0)
	assert_bool(sim.load_scenario(_data(), FILE_ID).ok).is_true()
	assert_array(sim.device_ids()).is_equal(["PC-A", "PC-B", "R1", "S1"])
	assert_int(sim.spare_cables()).is_equal(1)
	assert_object(sim.device_view("PC-B").interface("Eth0")["peer"]).is_null()


func test_loading_emits_no_signals() -> void:
	var sim := NetworkSim.new()
	var seen: Array[String] = []
	sim.events.link_changed.connect(func(_a: String, _b: String, _up: bool) -> void: seen.append("link"))
	sim.events.config_changed.connect(func(_id: String) -> void: seen.append("config"))
	sim.events.interface_state_changed.connect(func(_p: String, _up: bool) -> void: seen.append("state"))
	sim.load_scenario(_data(), FILE_ID)
	assert_array(seen).is_empty()


# --- starting state seen through device_view ---------------------------------


func test_links_load_with_reciprocal_peers() -> void:
	var sim := _loaded()
	var r1_gi0: Dictionary = sim.device_view("R1").interface("Gi0/0")
	var s1_gi1: Dictionary = sim.device_view("S1").interface("Gi0/1")
	assert_str(r1_gi0["peer"]).is_equal("S1:GigabitEthernet0/1")
	assert_str(s1_gi1["peer"]).is_equal("R1:GigabitEthernet0/0")
	assert_str(sim.device_view("S1").interface("Fa0/1")["peer"]).is_equal("PC-A:Ethernet0")
	assert_str(sim.device_view("PC-A").interface("Eth0")["peer"]).is_equal("S1:FastEthernet0/1")
	assert_object(sim.device_view("R1").interface("Gi0/1")["peer"]).is_null()
	assert_object(sim.device_view("PC-B").interface("Eth0")["peer"]).is_null()


func test_admin_and_oper_state_are_correct_straight_after_loading() -> void:
	var sim := _loaded()
	# A router's physical ports start shut, so the R1 to S1 trunk is down even
	# though it is cabled and the switch end is admin up.
	var r1_gi0: Dictionary = sim.device_view("R1").interface("Gi0/0")
	assert_bool(r1_gi0["admin_up"]).is_false()
	assert_bool(r1_gi0["oper_up"]).is_false()
	var s1_gi1: Dictionary = sim.device_view("S1").interface("Gi0/1")
	assert_bool(s1_gi1["admin_up"]).is_true()
	assert_bool(s1_gi1["oper_up"]).is_false()
	# PC-A to S1 is cabled with both ends admin up.
	assert_bool(sim.device_view("S1").interface("Fa0/1")["oper_up"]).is_true()
	assert_bool(sim.device_view("PC-A").interface("Eth0")["oper_up"]).is_true()
	# PC-B has no cable yet.
	var pc_b: Dictionary = sim.device_view("PC-B").interface("Eth0")
	assert_bool(pc_b["admin_up"]).is_true()
	assert_bool(pc_b["oper_up"]).is_false()


func test_starting_config_is_applied() -> void:
	var sim := _loaded()
	var s1: DeviceView = sim.device_view("S1")
	assert_str(s1.hostname()).is_equal("Switch")
	assert_dict(s1.vlans()).is_equal({1: "default", 10: "ACCOUNTING"})
	var fa1: Dictionary = s1.interface("Fa0/1")
	assert_int(fa1["mode"]).is_equal(Interface.Mode.ACCESS)
	assert_int(fa1["access_vlan"]).is_equal(10)
	assert_str(sim.device_view("R1").hostname()).is_equal("Router")
	var pc_a: DeviceView = sim.device_view("PC-A")
	assert_str(pc_a.interface("Eth0")["ip"]).is_equal("192.168.10.10")
	assert_str(pc_a.interface("Eth0")["mask"]).is_equal("255.255.255.0")
	assert_str(pc_a.gateway()).is_equal("192.168.10.1")
	assert_bool(pc_a.locked()).is_true()
	assert_bool(sim.device_view("PC-B").locked()).is_true()


func test_router_and_switch_starting_config_covers_every_field() -> void:
	var data: Dictionary = _data()
	data["devices"][R1]["config"] = {
		"enable_secret": "cisco",
		"interfaces": {
			"Gi0/0": {"admin_up": true},
			"Gi0/0.10": {"dot1q_vlan": 10, "ip": "192.168.10.1", "mask": "255.255.255.0"},
			"Gi0/1": {"ip": "10.0.0.1", "mask": "255.255.255.252"},
		},
		"routes": [{"network": "172.16.0.0", "mask": "255.255.0.0", "next_hop": "10.0.0.2"}],
	}
	data["devices"][S1]["config"]["interfaces"]["Gi0/1"] = {"mode": "trunk", "trunk_allowed": [10, 20], "admin_up": false}
	var sim := _loaded(data)

	var r1: DeviceView = sim.device_view("R1")
	assert_bool(r1.interface("g0/0")["admin_up"]).is_true()
	assert_bool(r1.interface("g0/1")["admin_up"]).is_false()
	assert_str(r1.interface("g0/1")["ip"]).is_equal("10.0.0.1")
	assert_str(r1.interface("g0/1")["mask"]).is_equal("255.255.255.252")
	var sub: Dictionary = r1.interface("Gi0/0.10")
	assert_str(sub["name"]).is_equal("GigabitEthernet0/0.10")
	assert_str(sub["parent"]).is_equal("GigabitEthernet0/0")
	assert_int(sub["dot1q_vlan"]).is_equal(10)
	assert_str(sub["ip"]).is_equal("192.168.10.1")
	assert_bool(sub["admin_up"]).is_true()
	assert_array(r1.static_routes()).is_equal([{"network": "172.16.0.0", "mask": "255.255.0.0", "next_hop": "10.0.0.2"}])
	assert_str(sim.get_device("R1").enable_secret).is_equal("cisco")

	var trunk: Dictionary = sim.device_view("S1").interface("Gi0/1")
	assert_int(trunk["mode"]).is_equal(Interface.Mode.TRUNK)
	assert_bool(trunk["trunk_allowed_all"]).is_false()
	assert_array(trunk["trunk_allowed"]).is_equal([10, 20])
	assert_bool(trunk["admin_up"]).is_false()

	# R1 Gi0/0 up and cabled to a shut S1 port: still not oper up, and the
	# subinterface follows its parent.
	assert_bool(r1.interface("Gi0/0")["oper_up"]).is_false()
	assert_bool(sub["oper_up"]).is_false()


func test_locked_links_cannot_be_unplugged_and_unlocked_links_can() -> void:
	var data: Dictionary = _data()
	data["links"][1]["locked"] = false
	var sim := _loaded(data)
	assert_int(sim.disconnect_link("R1:Gi0/0").reason).is_equal(LinkResult.Reason.LOCKED)
	assert_bool(sim.disconnect_link("PC-A:Eth0").ok).is_true()
	assert_int(sim.spare_cables()).is_equal(2)


func test_a_link_without_locked_is_not_locked() -> void:
	var data: Dictionary = _data()
	data["links"][1].erase("locked")
	var sim := _loaded(data)
	assert_bool(sim.disconnect_link("S1:Fa0/1").ok).is_true()


func test_reserved_ports_reject_cables_during_play() -> void:
	var sim := _loaded()
	var result: LinkResult = sim.connect_link("PC-B:Eth0", "R1:Gi0/1")
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(LinkResult.Reason.PORT_RESERVED)
	assert_int(sim.spare_cables()).is_equal(1)
	assert_bool(sim.connect_link("PC-B:Eth0", "S1:Fa0/2").ok).is_true()


# --- scenario_view ----------------------------------------------------------


func test_scenario_view_is_null_before_a_scenario_loads() -> void:
	assert_object(NetworkSim.new().scenario_view()).is_null()


func test_scenario_view_header_and_hints() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	assert_str(view.scenario_id()).is_equal("m1_vlan_ping")
	assert_str(view.title()).is_equal("Day One: Get Them Talking")
	assert_str(view.briefing()).starts_with("Accounting (PC-A) and Sales (PC-B)")
	assert_int(view.spare_cables()).is_equal(1)
	assert_array(view.hints()).is_equal([
		{"reason": PingResult.FailReason.NO_LINK, "text": "PC-B isn't cabled to anything yet."},
		{"reason": PingResult.FailReason.NO_GATEWAY, "text": "Hosts in different subnets need a router to reach each other."},
		{"reason": PingResult.FailReason.VLAN_MISMATCH, "text": "Check which VLAN each switch port is in."},
	])


func test_scenario_view_lists_every_device_with_its_placement() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	assert_array(view.devices().map(func(e: Dictionary) -> String: return e["id"])).is_equal(["R1", "S1", "PC-A", "PC-B"])
	var r1: Dictionary = _entry(view, "R1")
	assert_int(r1["kind"]).is_equal(Device.Kind.ROUTER)
	assert_str(r1["model"]).is_equal("router_2port")
	assert_str(r1["hostname"]).is_equal("Router")
	assert_str(r1["rack"]).is_equal("rack_a")
	assert_int(r1["slot"]).is_equal(1)
	assert_str(r1["desk"]).is_equal("")
	var s1: Dictionary = _entry(view, "S1")
	assert_int(s1["slot"]).is_equal(3)
	var pc_b: Dictionary = _entry(view, "PC-B")
	assert_int(pc_b["kind"]).is_equal(Device.Kind.HOST)
	assert_str(pc_b["model"]).is_equal("pc")
	assert_str(pc_b["desk"]).is_equal("desk_2")
	assert_str(pc_b["rack"]).is_equal("")
	assert_int(pc_b["slot"]).is_equal(0)


func test_scenario_view_interface_lists_are_canonical_and_in_socket_order() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	assert_array(_entry(view, "R1")["interfaces"]).is_equal(["GigabitEthernet0/0", "GigabitEthernet0/1"])
	assert_array(_entry(view, "PC-A")["interfaces"]).is_equal(["Ethernet0"])
	var s1: Array = _entry(view, "S1")["interfaces"]
	assert_int(s1.size()).is_equal(26)
	assert_str(s1[0]).is_equal("FastEthernet0/1")
	assert_str(s1[23]).is_equal("FastEthernet0/24")
	assert_str(s1[24]).is_equal("GigabitEthernet0/1")
	assert_str(s1[25]).is_equal("GigabitEthernet0/2")


func test_scenario_view_interface_list_leaves_out_starting_subinterfaces() -> void:
	# Subinterfaces have no socket, so they are not part of the socket order.
	var data: Dictionary = _data()
	data["devices"][R1]["config"] = {"interfaces": {"Gi0/0.10": {"dot1q_vlan": 10}}}
	var view: ScenarioView = _loaded(data).scenario_view()
	assert_array(_entry(view, "R1")["interfaces"]).is_equal(["GigabitEthernet0/0", "GigabitEthernet0/1"])


func test_scenario_view_links_and_reserved_ports_are_canonical() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	assert_array(view.links()).is_equal([
		{"a": "R1:GigabitEthernet0/0", "b": "S1:GigabitEthernet0/1", "locked": true},
		{"a": "S1:FastEthernet0/1", "b": "PC-A:Ethernet0", "locked": true},
	])
	assert_array(view.reserved_ports()).is_equal(["R1:GigabitEthernet0/1"])


func test_scenario_view_has_no_answers_or_solution() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	var everything: String = JSON.stringify([
		view.scenario_id(), view.title(), view.briefing(), view.hints(),
		view.devices(), view.links(), view.reserved_ports(), view.spare_cables(),
	])
	for leak: String in ["switchport", "encapsulation", "no shutdown", "parent_noip", "sub10", "objective", "solution", "dot1q_vlan", "192.168.20.1"]:
		assert_bool(everything.contains(leak)).override_failure_message("scenario view leaks \"%s\"" % leak).is_false()
	for method: Dictionary in view.get_method_list():
		var name: String = method["name"]
		assert_bool(["solution", "objectives", "debrief", "config"].has(name)).is_false()


func test_scenario_view_hands_out_copies() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	view.devices()[0]["id"] = "hacked"
	view.devices()[0]["interfaces"].clear()
	view.links().clear()
	view.reserved_ports().clear()
	view.hints().clear()
	assert_str(view.devices()[0]["id"]).is_equal("R1")
	assert_array(view.devices()[0]["interfaces"]).has_size(2)
	assert_array(view.links()).has_size(2)
	assert_array(view.reserved_ports()).has_size(1)
	assert_array(view.hints()).has_size(3)
