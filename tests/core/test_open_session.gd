class_name TestOpenSession
extends GdUnitTestSuite


func _topo() -> TopoBuilder:
	var t := TopoBuilder.new()
	t.add("router_2port", "R1")
	t.add("switch_24", "S1")
	t.add("pc", "PC-A")
	t.add("server", "SRV")
	return t


func test_router_and_switch_get_the_ios_cli() -> void:
	var t := _topo()
	var r: CliSession = t.sim.open_session("R1")
	assert_object(r).is_not_null()
	assert_bool(r is HostSession).is_false()
	assert_str(r.prompt()).is_equal("R1>")
	assert_int(r.mode()).is_equal(CliMode.Id.USER_EXEC)
	assert_str(t.sim.open_session("S1").prompt()).is_equal("S1>")


func test_a_pc_gets_the_windows_shell() -> void:
	var t := _topo()
	var pc: CliSession = t.sim.open_session("PC-A")
	assert_bool(pc is HostSession).is_true()
	assert_str(pc.prompt()).is_equal("C:\\>")


func test_a_server_has_no_shell_yet() -> void:
	assert_object(_topo().sim.open_session("SRV")).is_null()


func test_an_unknown_device_has_no_session() -> void:
	assert_object(_topo().sim.open_session("nope")).is_null()
	assert_object(_topo().sim.open_session("")).is_null()


func test_sessions_are_independent_but_share_the_simulation() -> void:
	var t := _topo()
	var a: CliSession = t.sim.open_session("R1")
	var b: CliSession = t.sim.open_session("R1")
	assert_bool(a == b).is_false()
	a.submit("enable")
	assert_str(a.prompt()).is_equal("R1#")
	assert_str(b.prompt()).is_equal("R1>")
	a.submit("configure terminal")
	a.submit("hostname EDGE")
	assert_str(b.prompt()).is_equal("EDGE>")


func test_a_session_from_open_session_can_configure_the_device() -> void:
	var t := _topo()
	var s: CliSession = t.sim.open_session("S1")
	for line in ["enable", "configure terminal", "vlan 10", "name Sales"]:
		assert_bool(s.submit(line).ok).override_failure_message(line).is_true()
	assert_str((t.sim.get_device("S1") as Switch).vlans[10]).is_equal("Sales")
