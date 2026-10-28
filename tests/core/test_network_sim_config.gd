class_name TestNetworkSimConfig
extends GdUnitTestSuite

var _configs: Array[String] = []
var _states: Array = []


func _topo() -> TopoBuilder:
	var t := TopoBuilder.new(1)
	t.add("router_2port", "R1")
	t.add("switch_24", "S1")
	t.add("pc", "PC-A")
	t.cable("S1:GigabitEthernet0/1", "R1:GigabitEthernet0/0")
	_configs = []
	_states = []
	t.sim.events.config_changed.connect(func(id: String) -> void: _configs.append(id))
	t.sim.events.interface_state_changed.connect(func(port: String, up: bool) -> void: _states.append([port, up]))
	return t


func _assert_fails(r: ConfigResult, reason: ConfigResult.Reason) -> void:
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(reason)
	assert_array(_configs).is_empty()


# --- hostname ---------------------------------------------------------------


func test_set_hostname() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.set_hostname("R1", "EDGE")
	assert_bool(r.ok and r.changed).is_true()
	assert_str(t.sim.get_device("R1").hostname).is_equal("EDGE")
	assert_array(_configs).is_equal(["R1"])


func test_set_hostname_same_value_is_silent() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.set_hostname("R1", "R1")
	assert_bool(r.ok).is_true()
	assert_bool(r.changed).is_false()
	assert_array(_configs).is_empty()


func test_set_hostname_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.set_hostname("nope", "X"), ConfigResult.Reason.UNKNOWN_DEVICE)
	_assert_fails(t.sim.set_hostname("R1", ""), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_hostname("R1", "A B"), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_hostname("PC-A", "X"), ConfigResult.Reason.WRONG_DEVICE_TYPE)


# --- shutdown ---------------------------------------------------------------


func test_no_shutdown_brings_a_cabled_port_up() -> void:
	var t := _topo()
	assert_bool(t.sim.is_oper_up("R1:Gi0/0")).is_false()
	var r: ConfigResult = t.sim.set_admin_up("R1:g0/0", true)
	assert_bool(r.ok and r.changed).is_true()
	assert_bool(t.sim.is_oper_up("R1:Gi0/0")).is_true()
	assert_array(_states).is_equal([["R1:GigabitEthernet0/0", true], ["S1:GigabitEthernet0/1", true]])
	assert_array(_configs).is_equal(["R1"])


func test_shutdown_takes_subinterfaces_down_too() -> void:
	var t := _topo()
	t.up("R1:Gi0/0")
	t.subif("R1", "Gi0/0.10", 10, "10.0.0.1", "255.255.255.0")
	_states.clear()
	t.sim.set_admin_up("R1:Gi0/0", false)
	assert_array(_states).is_equal([
		["R1:GigabitEthernet0/0", false],
		["R1:GigabitEthernet0/0.10", false],
		["S1:GigabitEthernet0/1", false],
	])


func test_shutdown_on_a_subinterface_flips_only_itself() -> void:
	var t := _topo()
	t.up("R1:Gi0/0")
	t.subif("R1", "Gi0/0.10", 10, "10.0.0.1", "255.255.255.0")
	_states.clear()
	t.sim.set_admin_up("R1:Gi0/0.10", false)
	assert_array(_states).is_equal([["R1:GigabitEthernet0/0.10", false]])
	assert_bool(t.sim.is_oper_up("R1:Gi0/0")).is_true()


func test_admin_state_unchanged_is_silent() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.set_admin_up("R1:Gi0/0", false)
	assert_bool(r.ok).is_true()
	assert_bool(r.changed).is_false()
	assert_array(_configs).is_empty()
	assert_array(_states).is_empty()


func test_admin_state_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.set_admin_up("R1:Gi0/9", true), ConfigResult.Reason.UNKNOWN_INTERFACE)
	_assert_fails(t.sim.set_admin_up("PC-A:Eth0", false), ConfigResult.Reason.WRONG_DEVICE_TYPE)


# --- ip address -------------------------------------------------------------


func test_set_and_clear_ip_address() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.set_ip_address("R1:g0/1", "10.0.0.1", "255.255.255.0")
	assert_bool(r.ok and r.changed).is_true()
	var i: Interface = t.sim.interface_at("R1:Gi0/1")
	assert_str(i.ip).is_equal("10.0.0.1")
	assert_str(i.mask).is_equal("255.255.255.0")
	assert_array(_configs).is_equal(["R1"])
	_configs.clear()
	r = t.sim.clear_ip_address("R1:Gi0/1")
	assert_bool(r.ok and r.changed).is_true()
	assert_bool(i.has_address()).is_false()
	assert_array(_configs).is_equal(["R1"])


func test_ip_address_repeats_and_empty_clear_are_silent() -> void:
	var t := _topo()
	t.sim.set_ip_address("R1:Gi0/1", "10.0.0.1", "255.255.255.0")
	_configs.clear()
	assert_bool(t.sim.set_ip_address("R1:Gi0/1", "10.0.0.1", "255.255.255.0").changed).is_false()
	assert_bool(t.sim.clear_ip_address("R1:Gi0/0").changed).is_false()
	assert_array(_configs).is_empty()


func test_ip_address_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.set_ip_address("R1:Gi0/9", "10.0.0.1", "255.255.255.0"), ConfigResult.Reason.UNKNOWN_INTERFACE)
	_assert_fails(t.sim.set_ip_address("R1:Gi0/1", "300.0.0.1", "255.255.255.0"), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_ip_address("R1:Gi0/1", "10.0.0.1", "255.0.255.0"), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_ip_address("S1:Fa0/1", "10.0.0.1", "255.255.255.0"), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.set_ip_address("PC-A:Eth0", "10.0.0.1", "255.255.255.0"), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.clear_ip_address("S1:Fa0/1"), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	assert_bool(t.sim.interface_at("R1:Gi0/1").has_address()).is_false()


# --- subinterfaces and dot1Q ------------------------------------------------


func test_create_subinterface() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.create_subinterface("R1", "g0/0.10")
	assert_bool(r.ok and r.changed).is_true()
	var sub: Interface = t.sim.interface_at("R1:Gi0/0.10")
	assert_object(sub).is_not_null()
	assert_str(sub.parent).is_equal("GigabitEthernet0/0")
	assert_bool(sub.admin_up).is_true()
	assert_int(sub.dot1q_vlan).is_equal(0)
	assert_array(_configs).is_equal(["R1"])


func test_create_existing_subinterface_is_silent() -> void:
	var t := _topo()
	t.sim.create_subinterface("R1", "g0/0.10")
	_configs.clear()
	var r: ConfigResult = t.sim.create_subinterface("R1", "Gi0/0.10")
	assert_bool(r.ok).is_true()
	assert_bool(r.changed).is_false()
	assert_array(_configs).is_empty()


func test_create_subinterface_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.create_subinterface("nope", "g0/0.10"), ConfigResult.Reason.UNKNOWN_DEVICE)
	_assert_fails(t.sim.create_subinterface("S1", "g0/1.10"), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.create_subinterface("R1", "g0/0"), ConfigResult.Reason.NOT_SUBINTERFACE)
	_assert_fails(t.sim.create_subinterface("R1", "bogus"), ConfigResult.Reason.NOT_SUBINTERFACE)
	_assert_fails(t.sim.create_subinterface("R1", "g0/7.10"), ConfigResult.Reason.UNKNOWN_INTERFACE)


func test_set_dot1q_vlan() -> void:
	var t := _topo()
	t.sim.create_subinterface("R1", "g0/0.10")
	_configs.clear()
	var r: ConfigResult = t.sim.set_dot1q_vlan("R1:Gi0/0.10", 10)
	assert_bool(r.ok and r.changed).is_true()
	assert_int(t.sim.interface_at("R1:Gi0/0.10").dot1q_vlan).is_equal(10)
	assert_array(_configs).is_equal(["R1"])
	assert_bool(t.sim.set_dot1q_vlan("R1:Gi0/0.10", 10).changed).is_false()
	assert_array(_configs).has_size(1)


func test_dot1q_rejections() -> void:
	var t := _topo()
	t.sim.create_subinterface("R1", "g0/0.10")
	_configs.clear()
	_assert_fails(t.sim.set_dot1q_vlan("R1:Gi0/0", 10), ConfigResult.Reason.NOT_SUBINTERFACE)
	_assert_fails(t.sim.set_dot1q_vlan("R1:Gi0/0.10", 0), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_dot1q_vlan("R1:Gi0/0.10", 4095), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_dot1q_vlan("R1:Gi0/0.99", 10), ConfigResult.Reason.UNKNOWN_INTERFACE)
	_assert_fails(t.sim.set_dot1q_vlan("S1:Fa0/1", 10), ConfigResult.Reason.WRONG_DEVICE_TYPE)


# --- switch VLANs and ports -------------------------------------------------


func test_create_vlan_uses_the_ios_default_name() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.create_vlan("S1", 10)
	assert_bool(r.ok and r.changed).is_true()
	assert_str((t.sim.get_device("S1") as Switch).vlans[10]).is_equal("VLAN0010")
	assert_array(_configs).is_equal(["S1"])
	assert_bool(t.sim.create_vlan("S1", 10).changed).is_false()
	assert_bool(t.sim.create_vlan("S1", 1).changed).is_false()
	assert_array(_configs).has_size(1)


func test_create_vlan_keeps_an_existing_name() -> void:
	var t := _topo()
	t.sim.create_vlan("S1", 10)
	t.sim.set_vlan_name("S1", 10, "Sales")
	t.sim.create_vlan("S1", 10)
	assert_str((t.sim.get_device("S1") as Switch).vlans[10]).is_equal("Sales")


func test_create_vlan_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.create_vlan("nope", 10), ConfigResult.Reason.UNKNOWN_DEVICE)
	_assert_fails(t.sim.create_vlan("R1", 10), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.create_vlan("S1", 0), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.create_vlan("S1", 4095), ConfigResult.Reason.INVALID_VALUE)


func test_set_vlan_name() -> void:
	var t := _topo()
	t.sim.create_vlan("S1", 10)
	_configs.clear()
	var r: ConfigResult = t.sim.set_vlan_name("S1", 10, "Sales")
	assert_bool(r.ok and r.changed).is_true()
	assert_str((t.sim.get_device("S1") as Switch).vlans[10]).is_equal("Sales")
	assert_array(_configs).is_equal(["S1"])
	assert_bool(t.sim.set_vlan_name("S1", 10, "Sales").changed).is_false()
	assert_array(_configs).has_size(1)


func test_set_vlan_name_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.set_vlan_name("S1", 10, "Sales"), ConfigResult.Reason.INVALID_VALUE)
	t.sim.create_vlan("S1", 10)
	_configs.clear()
	_assert_fails(t.sim.set_vlan_name("S1", 10, ""), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_vlan_name("S1", 10, "A B"), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_vlan_name("R1", 10, "Sales"), ConfigResult.Reason.WRONG_DEVICE_TYPE)


func test_switchport_mode() -> void:
	var t := _topo()
	var i: Interface = t.sim.interface_at("S1:Gi0/1")
	assert_int(i.mode).is_equal(Interface.Mode.ACCESS)
	var r: ConfigResult = t.sim.set_switchport_mode("S1:g0/1", Interface.Mode.TRUNK)
	assert_bool(r.ok and r.changed).is_true()
	assert_int(i.mode).is_equal(Interface.Mode.TRUNK)
	assert_array(_configs).is_equal(["S1"])
	assert_bool(t.sim.set_switchport_mode("S1:g0/1", Interface.Mode.TRUNK).changed).is_false()
	assert_array(_configs).has_size(1)


func test_access_vlan_need_not_exist() -> void:
	var t := _topo()
	var r: ConfigResult = t.sim.set_access_vlan("S1:fa0/1", 10)
	assert_bool(r.ok and r.changed).is_true()
	assert_int(t.sim.interface_at("S1:Fa0/1").access_vlan).is_equal(10)
	assert_bool((t.sim.get_device("S1") as Switch).vlans.has(10)).is_false()
	assert_array(_configs).is_equal(["S1"])
	assert_bool(t.sim.set_access_vlan("S1:fa0/1", 10).changed).is_false()
	assert_array(_configs).has_size(1)


func test_switchport_rejections() -> void:
	var t := _topo()
	_assert_fails(t.sim.set_switchport_mode("S1:Fa0/99", Interface.Mode.TRUNK), ConfigResult.Reason.UNKNOWN_INTERFACE)
	_assert_fails(t.sim.set_switchport_mode("R1:Gi0/0", Interface.Mode.TRUNK), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.set_switchport_mode("PC-A:Eth0", Interface.Mode.TRUNK), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.set_access_vlan("R1:Gi0/0", 10), ConfigResult.Reason.WRONG_DEVICE_TYPE)
	_assert_fails(t.sim.set_access_vlan("S1:Fa0/1", 0), ConfigResult.Reason.INVALID_VALUE)
	_assert_fails(t.sim.set_access_vlan("S1:Fa0/1", 4095), ConfigResult.Reason.INVALID_VALUE)
	assert_int(t.sim.interface_at("S1:Fa0/1").access_vlan).is_equal(1)
