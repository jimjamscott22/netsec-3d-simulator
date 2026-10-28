class_name TestIosCommands
extends GdUnitTestSuite

const INVALID: String = "% Invalid input detected at '^' marker."
const INCOMPLETE: String = "% Incomplete command."

const PRIV: CliMode.Id = CliMode.Id.PRIV_EXEC
const GLOBAL: CliMode.Id = CliMode.Id.GLOBAL_CONFIG
const IFACE: CliMode.Id = CliMode.Id.INTERFACE_CONFIG
const VLAN: CliMode.Id = CliMode.Id.VLAN_CONFIG

var _t: TopoBuilder
var _r: CliSession
var _s: CliSession
var _configs: int = 0


func before_test() -> void:
	_t = TopoBuilder.new()
	_t.add("router_2port", "R1")
	_t.add("switch_24", "S1")
	_t.add("pc", "PC-A")
	_t.add("pc", "PC-B")
	_t.cable("PC-A:Ethernet0", "S1:FastEthernet0/1")
	_t.cable("PC-B:Ethernet0", "S1:FastEthernet0/2")
	_t.cable("S1:GigabitEthernet0/1", "R1:GigabitEthernet0/0")
	_t.set_host("PC-A", "192.168.10.10", "255.255.255.0", "192.168.10.1")
	_t.set_host("PC-B", "192.168.20.10", "255.255.255.0", "192.168.20.1")
	_r = _open("R1")
	_s = _open("S1")
	_configs = 0
	_t.sim.events.config_changed.connect(func(_id: String) -> void: _configs += 1)


func _open(device_id: String) -> CliSession:
	return CliSession.new(_t.sim, device_id, IosCommands.registry_for(_t.sim.get_device(device_id)))


## Runs each line and fails the test on the first one that is rejected.
func _all(session: CliSession, lines: Array) -> void:
	for line: String in lines:
		var res: CliResult = session.submit(line)
		assert_bool(res.ok).override_failure_message("'%s' failed: %s" % [line, res.output]).is_true()


func _config(session: CliSession, lines: Array = []) -> void:
	_all(session, ["enable", "configure terminal"])
	_all(session, lines)


func _caret(session: CliSession, col: int) -> String:
	return " ".repeat(session.prompt().length() + col) + "^\n" + INVALID


func _router() -> Router:
	return _t.sim.get_device("R1")


func _switch() -> Switch:
	return _t.sim.get_device("S1")


# --- which devices get a CLI ------------------------------------------------


func test_registry_is_per_device_kind_and_shared() -> void:
	var router_reg: CommandRegistry = IosCommands.registry_for(_router())
	var switch_reg: CommandRegistry = IosCommands.registry_for(_switch())
	assert_object(router_reg).is_not_null()
	assert_object(switch_reg).is_not_null()
	assert_bool(router_reg == switch_reg).is_false()
	assert_bool(IosCommands.registry_for(_router()) == router_reg).is_true()


func test_hosts_have_no_ios_cli() -> void:
	assert_object(IosCommands.registry_for(_t.sim.get_device("PC-A"))).is_null()


# --- hostname ---------------------------------------------------------------


func test_hostname_changes_state_and_prompt() -> void:
	_config(_r, ["hostname EDGE"])
	assert_str(_router().hostname).is_equal("EDGE")
	assert_str(_r.prompt()).is_equal("EDGE(config)#")
	assert_int(_configs).is_equal(1)


func test_hostname_abbreviation_and_missing_argument() -> void:
	_config(_s, ["host SW1"])
	assert_str(_switch().hostname).is_equal("SW1")
	var res: CliResult = _s.submit("hostname")
	assert_bool(res.ok).is_false()
	assert_str(res.output).is_equal(INCOMPLETE)


# --- interface --------------------------------------------------------------


func test_interface_enters_interface_config_with_any_alias() -> void:
	_config(_r)
	for alias: String in ["interface g0/0", "int gi0/0", "interface GigabitEthernet0/0", "int gig0/0"]:
		_all(_r, [alias])
		assert_int(_r.mode()).is_equal(IFACE)
		assert_str(_r.context_interface()).is_equal("GigabitEthernet0/0")
		assert_str(_r.prompt()).is_equal("R1(config-if)#")
		_all(_r, ["exit"])


func test_interface_on_a_router_creates_the_subinterface() -> void:
	_config(_r, ["interface g0/0.10"])
	assert_int(_r.mode()).is_equal(IFACE)
	assert_str(_r.context_interface()).is_equal("GigabitEthernet0/0.10")
	assert_str(_r.prompt()).is_equal("R1(config-subif)#")
	var sub: Interface = _router().interface("Gi0/0.10")
	assert_object(sub).is_not_null()
	assert_str(sub.parent).is_equal("GigabitEthernet0/0")
	assert_bool(sub.admin_up).is_true()
	assert_int(_configs).is_equal(1)


func test_entering_an_existing_subinterface_changes_nothing() -> void:
	_config(_r, ["interface g0/0.10", "exit"])
	_configs = 0
	_all(_r, ["interface g0/0.10"])
	assert_int(_r.mode()).is_equal(IFACE)
	assert_int(_configs).is_equal(0)


func test_interface_that_does_not_exist_is_invalid_at_the_name() -> void:
	_config(_r)
	for bad: String in ["interface g0/5", "interface g0/5.10", "interface f0/0"]:
		var res: CliResult = _r.submit(bad)
		assert_bool(res.ok).is_false()
		assert_str(res.output).is_equal(_caret(_r, "interface ".length()))
		assert_int(_r.mode()).is_equal(GLOBAL)
	assert_int(_configs).is_equal(0)


func test_a_switch_has_no_subinterfaces() -> void:
	_config(_s)
	var res: CliResult = _s.submit("interface g0/1.10")
	assert_bool(res.ok).is_false()
	assert_str(res.output).is_equal(_caret(_s, "interface ".length()))
	assert_object(_switch().interface("Gi0/1.10")).is_null()
	assert_int(_s.mode()).is_equal(GLOBAL)


func test_interface_from_inside_interface_config_switches_context() -> void:
	_config(_r, ["interface g0/0.10", "interface g0/1"])
	assert_str(_r.context_interface()).is_equal("GigabitEthernet0/1")
	assert_str(_r.prompt()).is_equal("R1(config-if)#")
	_all(_r, ["exit"])
	assert_int(_r.mode()).is_equal(GLOBAL)


# --- shutdown ---------------------------------------------------------------


func test_no_shutdown_and_shutdown_change_admin_state() -> void:
	_config(_r, ["interface g0/1"])
	assert_bool(_router().interface("Gi0/1").admin_up).is_false()
	_all(_r, ["no shutdown"])
	assert_bool(_router().interface("Gi0/1").admin_up).is_true()
	_all(_r, ["shutdown"])
	assert_bool(_router().interface("Gi0/1").admin_up).is_false()


func test_shutdown_abbreviations() -> void:
	_config(_r, ["interface g0/1", "no shut"])
	assert_bool(_router().interface("Gi0/1").admin_up).is_true()
	_all(_r, ["shut"])
	assert_bool(_router().interface("Gi0/1").admin_up).is_false()


func test_no_shutdown_brings_the_cabled_link_up() -> void:
	assert_bool(_t.sim.is_oper_up("R1:Gi0/0")).is_false()
	_config(_r, ["interface g0/0", "no shutdown"])
	assert_bool(_t.sim.is_oper_up("R1:Gi0/0")).is_true()
	assert_bool(_t.sim.is_oper_up("S1:Gi0/1")).is_true()


func test_shutdown_on_a_switch_port() -> void:
	_config(_s, ["interface fa0/1", "shutdown"])
	assert_bool(_switch().interface("Fa0/1").admin_up).is_false()
	assert_bool(_t.sim.is_oper_up("PC-A:Eth0")).is_false()
	_all(_s, ["no shutdown"])
	assert_bool(_t.sim.is_oper_up("PC-A:Eth0")).is_true()


func test_repeating_shutdown_emits_no_config_change() -> void:
	_config(_r, ["interface g0/1", "shutdown"])
	assert_int(_configs).is_equal(0)


func test_shutdown_is_only_valid_in_interface_config() -> void:
	_config(_r)
	assert_str(_r.submit("shutdown").output).is_equal(_caret(_r, 0))


# --- ip address -------------------------------------------------------------


func test_ip_address_sets_address_and_mask() -> void:
	_config(_r, ["interface g0/1", "ip address 10.0.0.1 255.255.255.252"])
	var i: Interface = _router().interface("Gi0/1")
	assert_str(i.ip).is_equal("10.0.0.1")
	assert_str(i.mask).is_equal("255.255.255.252")
	assert_int(_configs).is_equal(1)


func test_ip_address_abbreviations_and_overwrite() -> void:
	_config(_r, ["int g0/1", "ip add 10.0.0.1 255.255.255.0", "ip addr 10.0.0.2 255.255.0.0"])
	var i: Interface = _router().interface("Gi0/1")
	assert_str(i.ip).is_equal("10.0.0.2")
	assert_str(i.mask).is_equal("255.255.0.0")


func test_no_ip_address_clears_it() -> void:
	_config(_r, ["interface g0/1", "ip address 10.0.0.1 255.255.255.0", "no ip address"])
	assert_bool(_router().interface("Gi0/1").has_address()).is_false()
	_all(_r, ["ip address 10.0.0.1 255.255.255.0", "no ip address 10.0.0.1 255.255.255.0"])
	assert_bool(_router().interface("Gi0/1").has_address()).is_false()


func test_ip_address_on_a_subinterface() -> void:
	_config(_r, ["interface g0/0.10", "ip address 192.168.10.1 255.255.255.0"])
	assert_str(_router().interface("Gi0/0.10").ip).is_equal("192.168.10.1")


func test_ip_address_bad_arguments() -> void:
	_config(_r, ["interface g0/1"])
	var res: CliResult = _r.submit("ip address 10.0.0.300 255.255.255.0")
	assert_str(res.output).is_equal(_caret(_r, "ip address ".length()))
	res = _r.submit("ip address 10.0.0.1 255.0.255.0")
	assert_str(res.output).is_equal(_caret(_r, "ip address 10.0.0.1 ".length()))
	assert_str(_r.submit("ip address 10.0.0.1").output).is_equal(INCOMPLETE)
	assert_bool(_router().interface("Gi0/1").has_address()).is_false()


func test_ip_address_is_not_a_switch_command() -> void:
	_config(_s, ["interface fa0/1"])
	var res: CliResult = _s.submit("ip address 10.0.0.1 255.255.255.0")
	assert_bool(res.ok).is_false()
	assert_str(res.output).is_equal(_caret(_s, 0))
	assert_bool(_switch().interface("Fa0/1").has_address()).is_false()
	assert_int(_configs).is_equal(0)


# --- encapsulation ----------------------------------------------------------


func test_encapsulation_dot1q_tags_the_subinterface() -> void:
	_config(_r, ["interface g0/0.10", "encapsulation dot1Q 10"])
	assert_int(_router().interface("Gi0/0.10").dot1q_vlan).is_equal(10)
	assert_int(_configs).is_equal(2)


func test_encapsulation_abbreviations_and_case() -> void:
	_config(_r, ["interface g0/0.20", "enc dot1q 20"])
	assert_int(_router().interface("Gi0/0.20").dot1q_vlan).is_equal(20)
	_all(_r, ["encapsulation DOT1Q 30"])
	assert_int(_router().interface("Gi0/0.20").dot1q_vlan).is_equal(30)


func test_encapsulation_is_rejected_on_a_physical_interface() -> void:
	_config(_r, ["interface g0/0"])
	var res: CliResult = _r.submit("encapsulation dot1Q 10")
	assert_bool(res.ok).is_false()
	assert_str(res.output).is_equal(_caret(_r, 0))
	assert_int(_configs).is_equal(0)


func test_encapsulation_bad_vlan_ids() -> void:
	_config(_r, ["interface g0/0.10"])
	assert_str(_r.submit("encapsulation dot1Q 0").output).is_equal(_caret(_r, "encapsulation dot1Q ".length()))
	assert_str(_r.submit("encapsulation dot1Q 4095").output).is_equal(_caret(_r, "encapsulation dot1Q ".length()))
	assert_str(_r.submit("encapsulation dot1Q").output).is_equal(INCOMPLETE)
	assert_int(_router().interface("Gi0/0.10").dot1q_vlan).is_equal(0)


func test_encapsulation_is_not_a_switch_command() -> void:
	_config(_s, ["interface g0/1"])
	assert_str(_s.submit("encapsulation dot1Q 10").output).is_equal(_caret(_s, 0))


# --- vlan and name ----------------------------------------------------------


func test_vlan_creates_and_enters_vlan_config() -> void:
	_config(_s, ["vlan 10"])
	assert_int(_s.mode()).is_equal(VLAN)
	assert_int(_s.context_vlan()).is_equal(10)
	assert_str(_s.prompt()).is_equal("S1(config-vlan)#")
	assert_str(_switch().vlans[10]).is_equal("VLAN0010")
	assert_int(_configs).is_equal(1)


func test_name_names_the_vlan() -> void:
	_config(_s, ["vlan 10", "name Sales"])
	assert_str(_switch().vlans[10]).is_equal("Sales")
	_all(_s, ["exit", "vlan 20", "na Engineering"])
	assert_str(_switch().vlans[20]).is_equal("Engineering")
	assert_str(_switch().vlans[10]).is_equal("Sales")


func test_reentering_a_vlan_keeps_its_name() -> void:
	_config(_s, ["vlan 10", "name Sales", "exit", "vlan 10"])
	assert_str(_switch().vlans[10]).is_equal("Sales")
	assert_int(_s.context_vlan()).is_equal(10)


func test_vlan_one_exists_and_can_be_entered() -> void:
	_config(_s, ["vlan 1"])
	assert_int(_s.mode()).is_equal(VLAN)
	assert_int(_configs).is_equal(0)


func test_vlan_from_another_vlan_replaces_it() -> void:
	_config(_s, ["vlan 10", "vlan 20"])
	assert_int(_s.context_vlan()).is_equal(20)
	_all(_s, ["exit"])
	assert_int(_s.mode()).is_equal(GLOBAL)


func test_vlan_bad_ids() -> void:
	_config(_s)
	assert_str(_s.submit("vlan 0").output).is_equal(_caret(_s, "vlan ".length()))
	assert_str(_s.submit("vlan 4095").output).is_equal(_caret(_s, "vlan ".length()))
	assert_str(_s.submit("vlan abc").output).is_equal(_caret(_s, "vlan ".length()))
	assert_str(_s.submit("vlan").output).is_equal(INCOMPLETE)
	assert_int(_switch().vlans.size()).is_equal(1)


func test_vlan_and_name_are_not_router_commands() -> void:
	_config(_r)
	assert_str(_r.submit("vlan 10").output).is_equal(_caret(_r, 0))
	assert_int(_r.mode()).is_equal(GLOBAL)


func test_name_is_only_valid_in_vlan_config() -> void:
	_config(_s)
	assert_str(_s.submit("name Sales").output).is_equal(_caret(_s, 0))
	_all(_s, ["interface fa0/1"])
	assert_str(_s.submit("name Sales").output).is_equal(_caret(_s, 0))


# --- switchport -------------------------------------------------------------


func test_switchport_mode_trunk_and_access() -> void:
	_config(_s, ["interface g0/1", "switchport mode trunk"])
	assert_int(_switch().interface("Gi0/1").mode).is_equal(Interface.Mode.TRUNK)
	_all(_s, ["switchport mode access"])
	assert_int(_switch().interface("Gi0/1").mode).is_equal(Interface.Mode.ACCESS)


func test_switchport_abbreviations() -> void:
	_config(_s, ["int g0/1", "sw mo tr"])
	assert_int(_switch().interface("Gi0/1").mode).is_equal(Interface.Mode.TRUNK)
	_all(_s, ["switchport mode acc"])
	assert_int(_switch().interface("Gi0/1").mode).is_equal(Interface.Mode.ACCESS)


func test_switchport_access_vlan() -> void:
	_config(_s, ["interface fa0/1", "switchport access vlan 10"])
	assert_int(_switch().interface("Fa0/1").access_vlan).is_equal(10)
	_all(_s, ["sw acc vl 20"])
	assert_int(_switch().interface("Fa0/1").access_vlan).is_equal(20)


func test_switchport_access_vlan_does_not_create_the_vlan() -> void:
	_config(_s, ["interface fa0/1", "switchport access vlan 10"])
	assert_bool(_switch().vlans.has(10)).is_false()


func test_switchport_incomplete_and_invalid() -> void:
	_config(_s, ["interface fa0/1"])
	assert_str(_s.submit("switchport mode").output).is_equal(INCOMPLETE)
	assert_str(_s.submit("switchport access vlan").output).is_equal(INCOMPLETE)
	assert_str(_s.submit("switchport mode dynamic").output).is_equal(_caret(_s, "switchport mode ".length()))
	assert_str(_s.submit("switchport access vlan 5000").output).is_equal(_caret(_s, "switchport access vlan ".length()))
	assert_int(_switch().interface("Fa0/1").access_vlan).is_equal(1)
	assert_int(_switch().interface("Fa0/1").mode).is_equal(Interface.Mode.ACCESS)


func test_switchport_is_not_a_router_command() -> void:
	_config(_r, ["interface g0/0"])
	for line: String in ["switchport mode trunk", "switchport access vlan 10"]:
		var res: CliResult = _r.submit(line)
		assert_bool(res.ok).is_false()
		assert_str(res.output).is_equal(_caret(_r, 0))
	assert_int(_configs).is_equal(0)


# --- wrong mode -------------------------------------------------------------


func test_config_commands_are_invalid_outside_config_mode() -> void:
	_all(_r, ["enable"])
	for line: String in ["hostname X", "interface g0/0", "ip address 10.0.0.1 255.255.255.0"]:
		var res: CliResult = _r.submit(line)
		assert_bool(res.ok).is_false()
		assert_str(res.output).is_equal(_caret(_r, 0))
	assert_str(_router().hostname).is_equal("R1")


func test_interface_commands_are_invalid_in_global_config() -> void:
	_config(_s)
	for line: String in ["shutdown", "switchport mode trunk", "switchport access vlan 10"]:
		assert_str(_s.submit(line).output).is_equal(_caret(_s, 0))


# --- help and completion ----------------------------------------------------


func test_switch_help_lists_switchport_options() -> void:
	_config(_s, ["interface fa0/1"])
	assert_str(_s.help("switchport ")).contains("access").contains("mode")
	assert_str(_s.help("switchport mode ")).contains("access").contains("trunk").not_contains("dynamic")
	assert_str(_s.help("switchport access vlan ")).contains("<1-4094>")


func test_router_help_lists_router_only_commands() -> void:
	_config(_r, ["interface g0/0.10"])
	var top: String = _r.help("")
	assert_str(top).contains("encapsulation").contains("ip").contains("shutdown").not_contains("switchport")
	assert_str(_r.help("encapsulation ")).contains("dot1q")
	assert_str(_r.help("ip address ")).contains("A.B.C.D")


func test_tab_completes_the_new_keywords() -> void:
	_config(_s, ["interface fa0/1"])
	assert_str(_s.complete("switchp")).is_equal("switchport ")
	assert_str(_s.complete("switchport m")).is_equal("switchport mode ")
	assert_str(_s.complete("switchport mode t")).is_equal("switchport mode trunk ")
	assert_str(_s.complete("s")).is_equal("s")  # shutdown and switchport


# --- the M1 mission, built entirely through the CLI --------------------------


func test_router_on_a_stick_configured_by_cli_lets_the_pcs_ping() -> void:
	var before: PingResult = _t.sim.ping("PC-A", "192.168.20.10")
	assert_bool(before.success).is_false()

	_config(_s, [
		"vlan 10", "name Sales", "exit",
		"vlan 20", "name Engineering", "exit",
		"interface fa0/1", "switchport mode access", "switchport access vlan 10", "exit",
		"interface fa0/2", "switchport mode access", "switchport access vlan 20", "exit",
		"interface g0/1", "switchport mode trunk", "end",
	])
	_config(_r, [
		"interface g0/0", "no shutdown", "exit",
		"interface g0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
		"interface g0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end",
	])

	var after: PingResult = _t.sim.ping("PC-A", "192.168.20.10")
	assert_bool(after.success).override_failure_message(
		"ping failed: %s" % PingResult.FailReason.keys()[after.fail_reason]
	).is_true()
	assert_array(after.hops).is_equal(["PC-A", "R1", "PC-B"])
