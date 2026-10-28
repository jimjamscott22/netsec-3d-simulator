class_name TestPingCommand
extends GdUnitTestSuite

const INVALID: String = "% Invalid input detected at '^' marker."
const INCOMPLETE: String = "% Incomplete command."

const PRIV: CliMode.Id = CliMode.Id.PRIV_EXEC
const GLOBAL: CliMode.Id = CliMode.Id.GLOBAL_CONFIG
const IFACE: CliMode.Id = CliMode.Id.INTERFACE_CONFIG

var _t: TopoBuilder
var _r: CliSession
var _s: CliSession
var _configs: int = 0
var _states: int = 0


func before_test() -> void:
	_t = TopoBuilder.stick()
	_r = _open("R1")
	_s = _open("S1")
	_all(_r, ["enable"])
	_all(_s, ["enable"])
	_configs = 0
	_states = 0
	_t.sim.events.config_changed.connect(func(_id: String) -> void: _configs += 1)
	_t.sim.events.interface_state_changed.connect(func(_p: String, _u: bool) -> void: _states += 1)


func _open(device_id: String) -> CliSession:
	return CliSession.new(_t.sim, device_id, IosCommands.registry_for(_t.sim.get_device(device_id)))


func _all(session: CliSession, lines: Array) -> void:
	for line: String in lines:
		var res: CliResult = session.submit(line)
		assert_bool(res.ok).override_failure_message("'%s' failed: %s" % [line, res.output]).is_true()


func _caret(session: CliSession, col: int) -> String:
	return " ".repeat(session.prompt().length() + col) + "^\n" + INVALID


func _hit(ip: String, hops: String) -> String:
	return "\n".join([
		"Type escape sequence to abort.",
		"Sending 5, 100-byte ICMP Echos to %s, timeout is 2 seconds:" % ip,
		"!!!!!",
		"Success rate is 100 percent (5/5), round-trip min/avg/max = %s ms" % hops,
	])


func _miss(ip: String) -> String:
	return "\n".join([
		"Type escape sequence to abort.",
		"Sending 5, 100-byte ICMP Echos to %s, timeout is 2 seconds:" % ip,
		".....",
		"Success rate is 0 percent (0/5)",
	])


# --- success and failure goldens ------------------------------------------


func test_ping_a_host_through_a_subinterface() -> void:
	var res: CliResult = _r.submit("ping 192.168.10.10")
	assert_bool(res.ok).is_true()
	assert_str(res.output).is_equal(_hit("192.168.10.10", "1/2/4"))
	assert_str(_r.submit("ping 192.168.20.10").output).is_equal(_hit("192.168.20.10", "1/2/4"))


func test_ping_the_routers_own_address() -> void:
	assert_str(_r.submit("ping 192.168.10.1").output).is_equal(_hit("192.168.10.1", "1/2/4"))


func test_ping_with_no_route_is_all_dots() -> void:
	var res: CliResult = _r.submit("ping 10.9.9.9")
	assert_bool(res.ok).is_true()
	assert_str(res.output).is_equal(_miss("10.9.9.9"))


func test_ping_an_address_nobody_owns_is_all_dots() -> void:
	assert_str(_r.submit("ping 192.168.10.99").output).is_equal(_miss("192.168.10.99"))


func test_a_switch_has_no_address_to_ping_from() -> void:
	assert_str(_s.submit("ping 192.168.10.10").output).is_equal(_miss("192.168.10.10"))


func test_ping_output_is_the_same_every_time() -> void:
	var first: String = _r.submit("ping 192.168.20.10").output
	assert_str(_r.submit("ping 192.168.20.10").output).is_equal(first)


# --- parse and abbreviations --------------------------------------------------


func test_ping_abbreviations_and_case() -> void:
	for line: String in ["ping 192.168.10.10", "pin 192.168.10.10", "p 192.168.10.10", "PING 192.168.10.10"]:
		var res: CliResult = _r.submit(line)
		assert_bool(res.ok).override_failure_message(line).is_true()
		assert_str(res.output).override_failure_message(line).is_equal(_hit("192.168.10.10", "1/2/4"))


func test_ping_incomplete_and_bad_arguments() -> void:
	assert_str(_r.submit("ping").output).is_equal(INCOMPLETE)
	assert_str(_r.submit("ping 10.0.0.300").output).is_equal(_caret(_r, "ping ".length()))
	assert_str(_r.submit("ping 10.0.0").output).is_equal(_caret(_r, "ping ".length()))
	assert_str(_r.submit("ping r2").output).is_equal(_caret(_r, "ping ".length()))
	assert_str(_r.submit("ping 10.0.0.1 extra").output).is_equal(_caret(_r, "ping 10.0.0.1 ".length()))


func test_ping_needs_privileged_exec() -> void:
	var user := _open("R1")
	var res: CliResult = user.submit("ping 192.168.10.10")
	assert_bool(res.ok).is_false()
	assert_str(res.output).is_equal(_caret(user, 0))


func test_do_ping_from_config_modes() -> void:
	_all(_r, ["configure terminal"])
	assert_str(_r.submit("do ping 192.168.10.10").output).is_equal(_hit("192.168.10.10", "1/2/4"))
	assert_int(_r.mode()).is_equal(GLOBAL)
	_all(_r, ["interface g0/1"])
	assert_str(_r.submit("do p 10.9.9.9").output).is_equal(_miss("10.9.9.9"))
	assert_int(_r.mode()).is_equal(IFACE)
	assert_str(_r.context_interface()).is_equal("GigabitEthernet0/1")


func test_ping_without_do_is_invalid_in_config_mode() -> void:
	_all(_r, ["configure terminal"])
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_caret(_r, 0))


# --- ping follows configuration changes -----------------------------------------


func test_shutting_the_trunk_side_breaks_the_ping_and_no_shutdown_fixes_it() -> void:
	_all(_r, ["configure terminal", "interface g0/0", "shutdown", "end"])
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_miss("192.168.10.10"))
	_all(_r, ["configure terminal", "interface g0/0", "no shutdown", "end"])
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_hit("192.168.10.10", "1/2/4"))


func test_removing_the_subinterface_address_breaks_only_that_vlan() -> void:
	_all(_r, ["configure terminal", "interface g0/0.20", "no ip address", "end"])
	assert_str(_r.submit("ping 192.168.20.10").output).is_equal(_miss("192.168.20.10"))
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_hit("192.168.10.10", "1/2/4"))


func test_moving_a_port_to_another_vlan_breaks_the_ping() -> void:
	_all(_s, ["configure terminal", "interface fa0/1", "switchport access vlan 20", "end"])
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_miss("192.168.10.10"))


func test_wrong_dot1q_tag_breaks_the_ping() -> void:
	_all(_r, ["configure terminal", "interface g0/0.10", "encapsulation dot1Q 11", "end"])
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_miss("192.168.10.10"))
	_all(_r, ["configure terminal", "interface g0/0.10", "encapsulation dot1Q 10", "end"])
	assert_str(_r.submit("ping 192.168.10.10").output).is_equal(_hit("192.168.10.10", "1/2/4"))


func test_ping_matches_the_simulators_own_answer() -> void:
	for ip in ["192.168.10.10", "192.168.20.10", "10.9.9.9", "192.168.10.1"]:
		var want: String = CliFormatters.ping_output(ip, _t.sim.ping("R1", ip))
		assert_str(_r.submit("ping " + ip).output).override_failure_message(ip).is_equal(want)


# --- ping is read-only --------------------------------------------------------


func test_ping_changes_nothing_and_emits_no_events() -> void:
	var before: String = CliFormatters.running_config(_t.sim.get_device("R1"))
	_r.submit("ping 192.168.10.10")
	_r.submit("ping 10.9.9.9")
	_s.submit("ping 192.168.10.10")
	assert_int(_configs).is_equal(0)
	assert_int(_states).is_equal(0)
	assert_str(CliFormatters.running_config(_t.sim.get_device("R1"))).is_equal(before)
	assert_int(_r.mode()).is_equal(PRIV)


# --- help and completion ----------------------------------------------------


func test_ping_help_and_completion() -> void:
	assert_str(_r.help("ping ")).contains("A.B.C.D")
	assert_str(_r.help("")).contains("ping").contains("Send echo messages")
	assert_str(_r.complete("pi")).is_equal("ping ")
	assert_str(_r.complete("p")).is_equal("ping ")
	assert_str(_s.help("ping ")).contains("A.B.C.D")
