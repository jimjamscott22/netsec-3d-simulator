class_name TestHostShell
extends GdUnitTestSuite

const NOT_RECOGNIZED: String = "'%s' is not recognized as an internal or external command,\noperable program or batch file."
const LOCKED: String = "Access is denied. Network settings are managed by IT."
const USAGE_IPCONFIG: String = "Usage: ipconfig\n       ipconfig /set <ip> <mask> <gateway>"
const USAGE_PING: String = "Usage: ping <ip address>"

var _t: TopoBuilder
var _a: CliSession
var _b: CliSession
var _configs: int = 0
var _states: int = 0


func before_test() -> void:
	_t = TopoBuilder.stick()
	_a = _t.sim.open_session("PC-A")
	_b = _t.sim.open_session("PC-B")
	_configs = 0
	_states = 0
	_t.sim.events.config_changed.connect(func(_id: String) -> void: _configs += 1)
	_t.sim.events.interface_state_changed.connect(func(_p: String, _u: bool) -> void: _states += 1)


func _pc(id: String) -> Host:
	return _t.sim.get_device(id)


func _reply(ip: String, ttl: int, time: String) -> String:
	return "Reply from %s: bytes=32 time%s TTL=%d" % [ip, time, ttl]


# --- the session ----------------------------------------------------------


func test_prompt_and_mode() -> void:
	assert_str(_a.prompt()).is_equal("C:\\>")
	assert_int(_a.mode()).is_equal(CliMode.Id.USER_EXEC)
	assert_bool(_a.is_password_prompt()).is_false()


func test_only_a_pc_has_this_registry() -> void:
	assert_object(HostCommands.registry_for(_pc("PC-A"))).is_not_null()
	assert_object(HostCommands.registry_for(_t.sim.get_device("R1"))).is_null()
	assert_object(HostCommands.registry_for(_t.sim.get_device("S1"))).is_null()
	assert_object(HostCommands.registry_for(null)).is_null()
	var t := TopoBuilder.new()
	t.add("server", "SRV")
	assert_object(HostCommands.registry_for(t.sim.get_device("SRV"))).is_null()


func test_blank_input_prints_nothing() -> void:
	for line in ["", "   ", "\t"]:
		var r: CliResult = _a.submit(line)
		assert_bool(r.ok).is_true()
		assert_str(r.output).is_empty()


# --- ipconfig ---------------------------------------------------------------


func test_ipconfig_prints_the_adapter() -> void:
	var r: CliResult = _a.submit("ipconfig")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_equal("\n".join([
		"Windows IP Configuration",
		"",
		"Ethernet adapter Ethernet0:",
		"",
		"   Connection-specific DNS Suffix  . :",
		"   IPv4 Address. . . . . . . . . . . : 192.168.10.10",
		"   Subnet Mask . . . . . . . . . . . : 255.255.255.0",
		"   Default Gateway . . . . . . . . . : 192.168.10.1",
	]))


func test_ipconfig_is_not_case_sensitive() -> void:
	var want: String = _a.submit("ipconfig").output
	for line in ["IPCONFIG", "IpConfig", "  ipconfig  "]:
		assert_str(_a.submit(line).output).override_failure_message(line).is_equal(want)


func test_ipconfig_reports_a_pulled_cable_and_its_return() -> void:
	_t.sim.disconnect_link("PC-A:Ethernet0")
	assert_str(_a.submit("ipconfig").output).contains("Media disconnected").not_contains("192.168.10.10")
	_t.sim.connect_link("PC-A:Ethernet0", "S1:FastEthernet0/1")
	assert_str(_a.submit("ipconfig").output).contains("192.168.10.10").not_contains("Media disconnected")


func test_ipconfig_is_read_only() -> void:
	_a.submit("ipconfig")
	assert_int(_configs).is_equal(0)
	assert_int(_states).is_equal(0)


# --- ipconfig /set --------------------------------------------------------------


func test_ipconfig_set_changes_the_address_mask_and_gateway() -> void:
	var r: CliResult = _a.submit("ipconfig /set 10.1.2.3 255.255.0.0 10.1.0.1")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_equal("Ok.")
	assert_str(_pc("PC-A").nic().ip).is_equal("10.1.2.3")
	assert_str(_pc("PC-A").nic().mask).is_equal("255.255.0.0")
	assert_str(_pc("PC-A").gateway).is_equal("10.1.0.1")
	assert_int(_configs).is_equal(1)
	assert_str(_a.submit("ipconfig").output).contains("10.1.2.3").contains("255.255.0.0").contains("10.1.0.1")


func test_ipconfig_set_is_not_case_sensitive() -> void:
	assert_bool(_a.submit("IPCONFIG /SET 10.1.2.3 255.255.0.0 10.1.0.1").ok).is_true()
	assert_str(_pc("PC-A").nic().ip).is_equal("10.1.2.3")


func test_ipconfig_set_with_the_same_values_emits_nothing() -> void:
	var r: CliResult = _a.submit("ipconfig /set 192.168.10.10 255.255.255.0 192.168.10.1")
	assert_bool(r.ok).is_true()
	assert_int(_configs).is_equal(0)


func test_ipconfig_set_fixes_a_broken_pc_and_the_ping_follows() -> void:
	_t.set_host("PC-A", "192.168.10.10", "255.255.255.0", "192.168.99.1")
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Request timed out.")
	assert_bool(_a.submit("ipconfig /set 192.168.10.10 255.255.255.0 192.168.10.1").ok).is_true()
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Received = 4")


func test_ipconfig_set_can_also_break_a_pc() -> void:
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Received = 4")
	_a.submit("ipconfig /set 192.168.10.10 255.255.255.0 192.168.10.77")
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Request timed out.")


func test_a_locked_pc_refuses_ipconfig_set() -> void:
	_pc("PC-A").locked = true
	var r: CliResult = _a.submit("ipconfig /set 10.1.2.3 255.255.0.0 10.1.0.1")
	assert_bool(r.ok).is_false()
	assert_str(r.output).is_equal(LOCKED)
	assert_str(_pc("PC-A").nic().ip).is_equal("192.168.10.10")
	assert_str(_pc("PC-A").nic().mask).is_equal("255.255.255.0")
	assert_str(_pc("PC-A").gateway).is_equal("192.168.10.1")
	assert_int(_configs).is_equal(0)


func test_a_locked_pc_still_runs_ipconfig_and_ping() -> void:
	_pc("PC-A").locked = true
	assert_str(_a.submit("ipconfig").output).contains("192.168.10.10")
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Received = 4")


func test_locking_is_per_host() -> void:
	_pc("PC-A").locked = true
	assert_str(_b.submit("ipconfig /set 192.168.20.10 255.255.255.0 192.168.20.1").output).is_equal("Ok.")
	assert_str(_a.submit("ipconfig /set 192.168.10.10 255.255.255.0 192.168.10.1").output).is_equal(LOCKED)


func test_a_locked_pc_cannot_dodge_the_router_by_readdressing() -> void:
	# The shortcut: put PC-A in PC-B's subnet so the ping needs no routing.
	_pc("PC-A").locked = true
	var before: PingResult = _t.sim.ping("PC-A", "192.168.20.10")
	assert_str(_a.submit("ipconfig /set 192.168.20.99 255.255.255.0 192.168.20.1").output).is_equal(LOCKED)
	var after: PingResult = _t.sim.ping("PC-A", "192.168.20.10")
	assert_array(after.hops).is_equal(before.hops)
	assert_array(after.hops).is_equal(["PC-A", "R1", "PC-B"])


func test_ipconfig_set_bad_arguments_print_the_usage() -> void:
	for line in [
		"ipconfig /set",
		"ipconfig /set 10.1.2.3",
		"ipconfig /set 10.1.2.3 255.255.0.0",
		"ipconfig /set 999.1.2.3 255.255.0.0 10.1.0.1",
		"ipconfig /set 10.1.2.3 255.0.255.0 10.1.0.1",
		"ipconfig /set 10.1.2.3 255.255.0.0 gateway",
		"ipconfig /set 10.1.2.3 255.255.0.0 10.1.0.1 extra",
		"ipconfig /renew",
		"ipconfig extra",
	]:
		var r: CliResult = _a.submit(line)
		assert_bool(r.ok).override_failure_message(line).is_false()
		assert_str(r.output).override_failure_message(line).is_equal(USAGE_IPCONFIG)
	assert_str(_pc("PC-A").nic().ip).is_equal("192.168.10.10")
	assert_int(_configs).is_equal(0)


func test_a_locked_pc_given_bad_arguments_still_gets_the_usage() -> void:
	_pc("PC-A").locked = true
	assert_str(_a.submit("ipconfig /set 10.1.2.3").output).is_equal(USAGE_IPCONFIG)


# --- ping -------------------------------------------------------------------


func test_ping_a_pc_through_the_router() -> void:
	var r: CliResult = _a.submit("ping 192.168.20.10")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_equal("\n".join([
		"Pinging 192.168.20.10 with 32 bytes of data:",
		_reply("192.168.20.10", 127, "=1ms"),
		_reply("192.168.20.10", 127, "=1ms"),
		_reply("192.168.20.10", 127, "=1ms"),
		_reply("192.168.20.10", 127, "=1ms"),
		"",
		"Ping statistics for 192.168.20.10:",
		"    Packets: Sent = 4, Received = 4, Lost = 0 (0% loss),",
		"Approximate round trip times in milli-seconds:",
		"    Minimum = 1ms, Maximum = 1ms, Average = 1ms",
	]))


func test_ping_the_gateway_and_itself() -> void:
	assert_str(_a.submit("ping 192.168.10.1").output).contains("time<1ms TTL=128")
	assert_str(_a.submit("ping 192.168.10.10").output).contains("Received = 4")


func test_ping_with_no_route_times_out() -> void:
	var r: CliResult = _a.submit("ping 10.9.9.9")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_equal("\n".join([
		"Pinging 10.9.9.9 with 32 bytes of data:",
		"Request timed out.",
		"Request timed out.",
		"Request timed out.",
		"Request timed out.",
		"",
		"Ping statistics for 10.9.9.9:",
		"    Packets: Sent = 4, Received = 0, Lost = 4 (100% loss),",
	]))


func test_ping_matches_the_simulators_own_answer() -> void:
	for ip in ["192.168.20.10", "192.168.10.1", "10.9.9.9", "192.168.10.10"]:
		var want: String = CliFormatters.windows_ping(ip, _t.sim.ping("PC-A", ip))
		assert_str(_a.submit("ping " + ip).output).override_failure_message(ip).is_equal(want)


func test_ping_follows_cabling_and_router_state() -> void:
	_t.sim.disconnect_link("PC-B:Ethernet0")
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Request timed out.")
	_t.sim.connect_link("PC-B:Ethernet0", "S1:FastEthernet0/2")
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Received = 4")
	_t.sim.set_admin_up("R1:Gi0/0", false)
	assert_str(_a.submit("ping 192.168.20.10").output).contains("Request timed out.")


func test_ping_a_name_cannot_be_resolved() -> void:
	for target in ["server1", "10.0.0.300", "10.0.0", "localhost"]:
		var r: CliResult = _a.submit("ping " + target)
		assert_bool(r.ok).override_failure_message(target).is_false()
		assert_str(r.output).override_failure_message(target).is_equal(
			"Ping request could not find host %s. Please check the name and try again." % target
		)


func test_ping_with_missing_or_extra_arguments_prints_the_usage() -> void:
	for line in ["ping", "ping 10.0.0.1 extra", "ping 10.0.0.1 10.0.0.2"]:
		var r: CliResult = _a.submit(line)
		assert_bool(r.ok).override_failure_message(line).is_false()
		assert_str(r.output).override_failure_message(line).is_equal(USAGE_PING)


func test_ping_accepts_a_quoted_address() -> void:
	assert_str(_a.submit('ping "192.168.20.10"').output).contains("Received = 4")


func test_ping_is_read_only() -> void:
	_a.submit("ping 192.168.20.10")
	_a.submit("ping 10.9.9.9")
	assert_int(_configs).is_equal(0)
	assert_int(_states).is_equal(0)


# --- unknown commands and no abbreviations ---------------------------------------


func test_unknown_commands_are_not_recognized() -> void:
	for word in ["foo", "dir", "enable", "show", "configure", "?"]:
		var r: CliResult = _a.submit(word)
		assert_bool(r.ok).override_failure_message(word).is_false()
		assert_str(r.output).override_failure_message(word).is_equal(NOT_RECOGNIZED % word)


func test_the_unknown_word_is_named_even_with_arguments_and_leading_space() -> void:
	assert_str(_a.submit("show running-config").output).is_equal(NOT_RECOGNIZED % "show")
	assert_str(_a.submit("   foo bar").output).is_equal(NOT_RECOGNIZED % "foo")


func test_commands_cannot_be_abbreviated() -> void:
	for line in ["ipc", "ipconfi", "pin 192.168.10.1", "p 192.168.10.1", "hel", "ex"]:
		var r: CliResult = _a.submit(line)
		assert_bool(r.ok).override_failure_message(line).is_false()
		assert_str(r.output).override_failure_message(line).is_equal(NOT_RECOGNIZED % line.split(" ")[0])
	assert_str(_a.submit("ipconfig /s 1.1.1.1 255.0.0.0 1.1.1.2").output).is_equal(USAGE_IPCONFIG)


# --- help and exit ----------------------------------------------------------------


func test_help_lists_the_commands() -> void:
	assert_str(_a.submit("help").output).is_equal("\n".join([
		"For more information on a specific command, type HELP command-name",
		"IPCONFIG       Displays the IP configuration of this computer.",
		"PING           Tests the connection to another computer.",
		"HELP           Provides help information for commands.",
		"EXIT           Quits the command prompt.",
	]))


func test_help_for_one_command() -> void:
	assert_str(_a.submit("help ping").output).is_equal("Tests the connection to another computer.\n\nping <ip address>")
	assert_str(_a.submit("HELP IPCONFIG").output).contains("ipconfig /set <ip> <mask> <gateway>")
	assert_str(_a.submit("help dir").output).is_equal('This command is not supported by the help utility.  Try "dir /?".')


func test_exit_asks_the_terminal_to_close() -> void:
	var r: CliResult = _a.submit("exit")
	assert_int(r.action).is_equal(CliResult.ShellAction.CLOSE_SESSION)
	assert_bool(r.ok).is_true()


# --- question-mark help, Tab and history --------------------------------------------


func test_question_mark_help_lists_the_commands() -> void:
	assert_str(_a.help("")).contains("ipconfig").contains("ping").contains("help").contains("exit")
	assert_str(_a.help("ipconfig ")).contains("/set").contains("<cr>")
	assert_str(_a.help("ping ")).contains("WORD")
	assert_str(_a.help("ipconfig /set ")).contains("A.B.C.D")


func test_tab_completes_prefixes_even_though_enter_needs_the_full_name() -> void:
	assert_str(_a.complete("ipc")).is_equal("ipconfig ")
	assert_str(_a.complete("ipconfig /s")).is_equal("ipconfig /set ")
	assert_str(_a.complete("pi")).is_equal("ping ")
	assert_str(_a.complete("zz")).is_equal("zz")


func test_history_keeps_every_line_including_failures() -> void:
	_a.submit("ipconfig")
	_a.submit("foo")
	_a.submit("ping 192.168.20.10")
	assert_array(_a.history()).is_equal(["ipconfig", "foo", "ping 192.168.20.10"])
	assert_str(_a.history_prev()).is_equal("ping 192.168.20.10")
	assert_str(_a.history_prev()).is_equal("foo")
	assert_str(_a.history_next()).is_equal("ping 192.168.20.10")
	assert_str(_a.history_next()).is_empty()


func test_ctrl_z_does_nothing_in_a_pc_shell() -> void:
	var r: CliResult = _a.ctrl_z()
	assert_bool(r.ok).is_true()
	assert_str(_a.prompt()).is_equal("C:\\>")
