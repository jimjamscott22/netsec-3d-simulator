class_name TestShowCommands
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


func before_test() -> void:
	_t = TopoBuilder.stick()
	_r = _open("R1")
	_s = _open("S1")
	_all(_r, ["enable"])
	_all(_s, ["enable"])
	_configs = 0
	_t.sim.events.config_changed.connect(func(_id: String) -> void: _configs += 1)


func _open(device_id: String) -> CliSession:
	return CliSession.new(_t.sim, device_id, IosCommands.registry_for(_t.sim.get_device(device_id)))


func _all(session: CliSession, lines: Array) -> void:
	for line: String in lines:
		var res: CliResult = session.submit(line)
		assert_bool(res.ok).override_failure_message("'%s' failed: %s" % [line, res.output]).is_true()


func _caret(session: CliSession, col: int) -> String:
	return " ".repeat(session.prompt().length() + col) + "^\n" + INVALID


# --- parse and abbreviations -------------------------------------------------


func test_show_running_config_and_its_abbreviations() -> void:
	var want: String = CliFormatters.running_config(_t.sim.get_device("R1"))
	for line: String in ["show running-config", "sh run", "show run", "sho running-config", "SHOW RUNNING-CONFIG"]:
		var res: CliResult = _r.submit(line)
		assert_bool(res.ok).override_failure_message(line).is_true()
		assert_str(res.output).override_failure_message(line).is_equal(want)


func test_show_ip_interface_brief_and_its_abbreviations() -> void:
	var want: String = CliFormatters.ip_interface_brief(_t.sim, "R1")
	for line: String in ["show ip interface brief", "sh ip int br", "show ip int brief", "sh ip interface b"]:
		var res: CliResult = _r.submit(line)
		assert_bool(res.ok).override_failure_message(line).is_true()
		assert_str(res.output).override_failure_message(line).is_equal(want)


func test_show_vlan_brief_and_its_abbreviations() -> void:
	var want: String = CliFormatters.vlan_brief(_t.sim.get_device("S1"))
	for line: String in ["show vlan brief", "sh vlan br", "sh vl b"]:
		var res: CliResult = _s.submit(line)
		assert_bool(res.ok).override_failure_message(line).is_true()
		assert_str(res.output).override_failure_message(line).is_equal(want)


func test_show_ip_interface_brief_also_works_on_a_switch() -> void:
	assert_str(_s.submit("sh ip int br").output).is_equal(CliFormatters.ip_interface_brief(_t.sim, "S1"))


func test_show_running_config_also_works_on_a_switch() -> void:
	assert_str(_s.submit("sh run").output).is_equal(CliFormatters.running_config(_t.sim.get_device("S1")))


func test_incomplete_and_invalid_show_commands() -> void:
	assert_str(_r.submit("show").output).is_equal(INCOMPLETE)
	assert_str(_r.submit("show ip").output).is_equal(INCOMPLETE)
	assert_str(_r.submit("show ip interface").output).is_equal(INCOMPLETE)
	assert_str(_r.submit("show foo").output).is_equal(_caret(_r, "show ".length()))
	assert_str(_r.submit("show ip interface brief extra").output).is_equal(_caret(_r, "show ip interface brief ".length()))
	assert_str(_s.submit("show vlan").output).is_equal(INCOMPLETE)


# --- where each show command exists ----------------------------------------


func test_show_vlan_brief_is_not_a_router_command() -> void:
	var res: CliResult = _r.submit("show vlan brief")
	assert_bool(res.ok).is_false()
	assert_str(res.output).is_equal(_caret(_r, "show ".length()))


func test_show_commands_need_privileged_exec() -> void:
	var user := _open("R1")
	for line: String in ["show running-config", "show ip interface brief"]:
		var res: CliResult = user.submit(line)
		assert_bool(res.ok).is_false()
		assert_str(res.output).is_equal(_caret(user, 0))


# --- from config modes -----------------------------------------------------


func test_do_show_runs_from_every_config_mode_without_leaving_it() -> void:
	_all(_r, ["configure terminal"])
	var brief: String = CliFormatters.ip_interface_brief(_t.sim, "R1")
	assert_str(_r.submit("do show ip interface brief").output).is_equal(brief)
	assert_int(_r.mode()).is_equal(GLOBAL)
	_all(_r, ["interface g0/1"])
	assert_str(_r.submit("do sh ip int br").output).is_equal(brief)
	assert_int(_r.mode()).is_equal(IFACE)
	assert_str(_r.context_interface()).is_equal("GigabitEthernet0/1")
	assert_str(_r.submit("do sh run").output).is_equal(CliFormatters.running_config(_t.sim.get_device("R1")))


func test_do_show_vlan_brief_on_a_switch() -> void:
	_all(_s, ["configure terminal", "interface fa0/1"])
	assert_str(_s.submit("do show vlan brief").output).is_equal(CliFormatters.vlan_brief(_t.sim.get_device("S1")))


func test_show_without_do_is_invalid_in_config_mode() -> void:
	_all(_r, ["configure terminal"])
	assert_str(_r.submit("show running-config").output).is_equal(_caret(_r, 0))


func test_do_show_vlan_on_a_router_is_invalid() -> void:
	_all(_r, ["configure terminal"])
	assert_str(_r.submit("do show vlan brief").output).is_equal(_caret(_r, "do show ".length()))


# --- show output follows CLI changes ----------------------------------------


func test_show_ip_interface_brief_after_cli_changes() -> void:
	_all(_r, ["configure terminal", "interface g0/1", "ip address 10.0.0.1 255.255.255.252", "no shutdown", "exit",
			"interface g0/0", "shutdown", "end"])
	assert_str(_r.submit("show ip interface brief").output).is_equal("\n".join([
		"Interface                  IP-Address      OK? Method Status                Protocol",
		"GigabitEthernet0/0         unassigned      YES unset  administratively down down",
		"GigabitEthernet0/0.10      192.168.10.1    YES manual administratively down down",
		"GigabitEthernet0/0.20      192.168.20.1    YES manual administratively down down",
		"GigabitEthernet0/1         10.0.0.1        YES manual down                  down",
	]))


func test_show_vlan_brief_after_cli_changes() -> void:
	_all(_s, ["configure terminal", "vlan 30", "name Guests", "exit", "interface fa0/3", "switchport mode access",
			"switchport access vlan 30", "end"])
	var rows: PackedStringArray = _s.submit("show vlan brief").output.split("\n")
	assert_str(rows[2]).is_equal("1    default                          active    Fa0/4, Fa0/5, Fa0/6, Fa0/7")
	assert_str(rows[10]).is_equal("30   Guests                           active    Fa0/3")


func test_show_running_config_after_cli_changes() -> void:
	_all(_r, ["configure terminal", "hostname EDGE", "interface g0/1", "ip address 10.0.0.1 255.255.255.252", "no shutdown", "end"])
	var rows: PackedStringArray = _r.submit("show running-config").output.split("\n")
	assert_str(rows[4]).is_equal("hostname EDGE")
	assert_array(rows.slice(-4)).is_equal(["interface GigabitEthernet0/1", " ip address 10.0.0.1 255.255.255.252", "!", "end"])
	assert_str(_r.prompt()).is_equal("EDGE#")


func test_show_running_config_reflects_a_vlan_built_from_the_cli() -> void:
	_all(_s, ["configure terminal", "vlan 50", "name Printers", "exit", "interface fa0/9", "switchport access vlan 50", "end"])
	var text: String = _s.submit("show running-config").output
	assert_str(text).contains("\n".join(["vlan 50", " name Printers", "!"]))
	assert_str(text).contains("\n".join(["interface FastEthernet0/9", " switchport access vlan 50", " switchport mode access", "!"]))


# --- show is read-only -----------------------------------------------------


func test_show_commands_change_nothing() -> void:
	var before: String = CliFormatters.running_config(_t.sim.get_device("S1"))
	for line: String in ["show running-config", "show ip interface brief", "show vlan brief"]:
		_s.submit(line)
	assert_int(_configs).is_equal(0)
	assert_str(CliFormatters.running_config(_t.sim.get_device("S1"))).is_equal(before)
	assert_int(_s.mode()).is_equal(PRIV)


# --- help and completion ----------------------------------------------------


func test_router_help_for_show() -> void:
	var top: String = _r.help("show ")
	assert_str(top).contains("running-config").contains("ip").not_contains("vlan")
	assert_str(_r.help("show ip ")).contains("interface")
	assert_str(_r.help("show ip interface ")).contains("brief")
	assert_str(_r.help("show ip interface brief ")).is_equal("  <cr>")


func test_switch_help_for_show_lists_vlan() -> void:
	assert_str(_s.help("show ")).contains("running-config").contains("ip").contains("vlan")
	assert_str(_s.help("show vlan ")).contains("brief")


func test_tab_completes_show_keywords() -> void:
	assert_str(_r.complete("show run")).is_equal("show running-config ")
	assert_str(_r.complete("sh")).is_equal("show ")
	assert_str(_r.complete("show ip int")).is_equal("show ip interface ")
	assert_str(_s.complete("show vl")).is_equal("show vlan ")
	assert_str(_r.complete("show vl")).is_equal("show vl")
