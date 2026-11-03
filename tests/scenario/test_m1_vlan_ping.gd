class_name TestM1VlanPing
extends GdUnitTestSuite
## Shortcut regressions for the real `scenarios/m1_vlan_ping.json` (task 1.19).
## Each test takes a known bypass and checks the mission stays incomplete.

const PATH: String = "res://scenarios/m1_vlan_ping.json"
const FILE_ID: String = "m1_vlan_ping"


# --- helpers ----------------------------------------------------------------


func _data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_bool(parsed is Dictionary).override_failure_message("scenario did not parse").is_true()
	return parsed


func _sim() -> NetworkSim:
	var sim := NetworkSim.new()
	var result: LoadResult = sim.load_scenario(_data(), FILE_ID)
	assert_array(result.errors).is_empty()
	return sim


## Runs lines on a device's CLI; every line must be accepted.
func _cli(sim: NetworkSim, device: String, lines: Array[String]) -> void:
	var session: CliSession = sim.open_session(device)
	for line: String in lines:
		var r: CliResult = session.submit(line)
		assert_bool(r.ok).override_failure_message("%s: '%s' -> %s" % [device, line, r.output]).is_true()


func _passes(sim: NetworkSim, id: String) -> bool:
	for s: ObjectiveState in sim.objective_states():
		if s.id == id:
			return s.passed
	fail("no objective %s" % id)
	return false


func _mission_done(sim: NetworkSim) -> bool:
	for s: ObjectiveState in sim.objective_states():
		if not s.passed:
			return false
	return true


func _cable_pc_b(sim: NetworkSim) -> void:
	assert_bool(sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()


## PC-B in VLAN 20 on Fa0/2, as the real solution does.
func _pc_b_in_vlan_20(sim: NetworkSim) -> void:
	_cable_pc_b(sim)
	_cli(sim, "S1", ["enable", "configure terminal", "vlan 20", "name SALES", "exit",
		"interface fa0/2", "switchport mode access", "switchport access vlan 20", "end"])


# --- shape ------------------------------------------------------------------


func test_the_mission_starts_incomplete() -> void:
	var sim := _sim()
	assert_bool(_passes(sim, "ping_ab")).is_false()
	assert_bool(_passes(sim, "trunk")).is_false()
	assert_bool(_mission_done(sim)).is_false()


func test_it_lists_the_expected_objectives_and_locks_both_pcs() -> void:
	var data: Dictionary = _data()
	var ids: Array = data["objectives"].map(func(o: Dictionary) -> String: return o["id"])
	assert_array(ids).is_equal(["ping_ab", "trunk", "sub10", "sub20", "parent_noip"])
	assert_array(data["reserved_ports"]).is_equal(["R1:Gi0/1"])
	for d: Dictionary in data["devices"]:
		if d["type"] == "host":
			assert_bool(d["config"]["locked"]).is_true()


# --- shortcuts --------------------------------------------------------------


func test_readdressing_a_locked_pc_is_refused() -> void:
	var sim := _sim()
	_cable_pc_b(sim)
	for pc: String in ["PC-A", "PC-B"]:
		var r: ConfigResult = sim.set_host_network(pc, "10.0.0.2", "255.255.255.0", "10.0.0.1")
		assert_bool(r.ok).is_false()
		assert_int(r.reason).is_equal(ConfigResult.Reason.LOCKED)
	var shell: CliResult = sim.open_session("PC-B").submit("ipconfig /set 192.168.10.20 255.255.255.0 192.168.10.1")
	assert_bool(shell.ok).is_false()
	assert_bool(_mission_done(sim)).is_false()


func test_cabling_pc_b_to_the_reserved_router_port_is_rejected() -> void:
	var sim := _sim()
	var r: LinkResult = sim.connect_link("R1:Gi0/1", "PC-B:Eth0")
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(LinkResult.Reason.PORT_RESERVED)
	assert_bool(_mission_done(sim)).is_false()


func test_a_decoy_ip_on_a_subinterface_fails_to_device() -> void:
	# Put PC-B's subnet on a router sub that really answers 192.168.20.10.
	var sim := _sim()
	_pc_b_in_vlan_20(sim)
	_cli(sim, "S1", ["enable", "configure terminal", "interface gi0/1", "switchport mode trunk", "end"])
	_cli(sim, "R1", ["enable", "configure terminal", "interface gi0/0", "no shutdown", "exit",
		"interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
		"interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.10 255.255.255.0", "end"])
	# 192.168.20.10 is now answered by R1 itself, not PC-B.
	assert_bool(_passes(sim, "ping_ab")).is_false()
	assert_bool(_passes(sim, "sub20")).is_false()
	assert_bool(_mission_done(sim)).is_false()


func test_asymmetric_masks_with_an_access_uplink_fail_the_config_objectives() -> void:
	var sim := _sim()
	_pc_b_in_vlan_20(sim)
	# S1 Gi0/1 stays an access port; R1 Gi0/0 gets a /16 straight on the physical port.
	_cli(sim, "R1", ["enable", "configure terminal", "interface gi0/0", "no shutdown",
		"ip address 192.168.10.1 255.255.0.0", "end"])
	assert_bool(_passes(sim, "trunk")).is_false()
	assert_bool(_passes(sim, "sub10")).is_false()
	assert_bool(_passes(sim, "parent_noip")).is_false()
	assert_bool(_mission_done(sim)).is_false()


func test_the_native_vlan_path_fails_sub10_and_parent_noip() -> void:
	var sim := _sim()
	_cable_pc_b(sim)
	# Both PC-A's port and the uplink in VLAN 1; the gateway sits on the physical port.
	_cli(sim, "S1", ["enable", "configure terminal",
		"interface fa0/1", "switchport access vlan 1", "exit",
		"interface gi0/1", "switchport mode access", "switchport access vlan 1", "end"])
	_cli(sim, "R1", ["enable", "configure terminal", "interface gi0/0", "no shutdown",
		"ip address 192.168.10.1 255.255.255.0", "exit",
		"interface gi0/0.10", "encapsulation dot1Q 10", "end"])
	assert_bool(_passes(sim, "sub10")).is_false()
	assert_bool(_passes(sim, "parent_noip")).is_false()
	assert_bool(_mission_done(sim)).is_false()


func test_overlapping_masks_on_a_subinterface_fail_sub10() -> void:
	var sim := _sim()
	_pc_b_in_vlan_20(sim)
	_cli(sim, "S1", ["enable", "configure terminal", "interface gi0/1", "switchport mode trunk", "end"])
	_cli(sim, "R1", ["enable", "configure terminal", "interface gi0/0", "no shutdown", "exit",
		"interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.0.0.0", "exit",
		"interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end"])
	assert_bool(_passes(sim, "sub10")).is_false()
	assert_bool(_mission_done(sim)).is_false()
