class_name TestNetworkSim
extends GdUnitTestSuite

var _links: Array = []
var _states: Array = []


func _watch(sim: NetworkSim) -> void:
	_links = []
	_states = []
	sim.events.link_changed.connect(
		func(a: String, b: String, connected: bool) -> void: _links.append([a, b, connected])
	)
	sim.events.interface_state_changed.connect(
		func(port: String, up: bool) -> void: _states.append([port, up])
	)


func _pcs(spare: int) -> NetworkSim:
	var sim := NetworkSim.new(spare)
	sim.add_device(DeviceModels.build("pc", "PC-A"))
	sim.add_device(DeviceModels.build("pc", "PC-B"))
	return sim


func _world(spare: int) -> NetworkSim:
	var sim := NetworkSim.new(spare)
	sim.add_device(DeviceModels.build("router_2port", "R1"))
	sim.add_device(DeviceModels.build("switch_24", "S1"))
	sim.add_device(DeviceModels.build("pc", "PC-A"))
	sim.add_device(DeviceModels.build("pc", "PC-B"))
	return sim


func _expect_reject(sim: NetworkSim, a: String, b: String, reason: LinkResult.Reason) -> void:
	var spare: int = sim.spare_cables()
	var links: int = _links.size()
	var states: int = _states.size()
	var r: LinkResult = sim.connect_link(a, b)
	assert_bool(r.ok).override_failure_message("%s <-> %s should be rejected" % [a, b]).is_false()
	assert_int(r.reason).override_failure_message("%s <-> %s" % [a, b]).is_equal(reason)
	assert_int(sim.spare_cables()).is_equal(spare)
	assert_int(_links.size()).is_equal(links)
	assert_int(_states.size()).is_equal(states)


func test_add_device() -> void:
	var sim := NetworkSim.new()
	assert_bool(sim.add_device(DeviceModels.build("pc", "PC-B"))).is_true()
	assert_bool(sim.add_device(DeviceModels.build("pc", "PC-A"))).is_true()
	assert_bool(sim.add_device(DeviceModels.build("pc", "PC-A"))).is_false()
	assert_object(sim.get_device("nope")).is_null()
	assert_object(sim.get_device("PC-A")).is_not_null()
	assert_array(sim.device_ids()).is_equal(["PC-A", "PC-B"])


func test_interface_at_accepts_unnormalized_names() -> void:
	var sim := _pcs(0)
	assert_object(sim.interface_at("PC-A:eth0")).is_same(sim.get_device("PC-A").interface("Ethernet0"))
	assert_object(sim.interface_at("PC-A:g9/9")).is_null()
	assert_object(sim.interface_at("nope:eth0")).is_null()
	assert_object(sim.interface_at("PC-A")).is_null()


func test_connect_two_pcs() -> void:
	var sim := _pcs(1)
	_watch(sim)
	var r: LinkResult = sim.connect_link("PC-A:eth0", "PC-B:Ethernet0")
	assert_bool(r.ok).is_true()
	assert_str(sim.interface_at("PC-A:Ethernet0").peer_port).is_equal("PC-B:Ethernet0")
	assert_str(sim.interface_at("PC-B:Ethernet0").peer_port).is_equal("PC-A:Ethernet0")
	assert_int(sim.spare_cables()).is_equal(0)
	assert_bool(sim.is_oper_up("PC-A:Ethernet0")).is_true()
	assert_bool(sim.is_oper_up("PC-B:Ethernet0")).is_true()
	assert_array(_links).is_equal([["PC-A:Ethernet0", "PC-B:Ethernet0", true]])
	assert_array(_states).is_equal([["PC-A:Ethernet0", true], ["PC-B:Ethernet0", true]])


func test_connect_shut_router_port_no_state_signal() -> void:
	var sim := _world(1)
	_watch(sim)
	assert_bool(sim.connect_link("R1:g0/0", "S1:fa0/1").ok).is_true()
	assert_int(_links.size()).is_equal(1)
	assert_int(_states.size()).is_equal(0)
	assert_bool(sim.is_oper_up("R1:GigabitEthernet0/0")).is_false()
	assert_bool(sim.is_oper_up("S1:FastEthernet0/1")).is_false()


func test_connect_rejections() -> void:
	var sim := _world(5)
	(sim.get_device("R1") as Router).add_subinterface("g0/0.10")
	sim.reserve_port("S1:fa0/24")
	_watch(sim)
	_expect_reject(sim, "nope:eth0", "PC-B:eth0", LinkResult.Reason.UNKNOWN_PORT)
	_expect_reject(sim, "PC-A:g9/9", "PC-B:eth0", LinkResult.Reason.UNKNOWN_PORT)
	_expect_reject(sim, "PC-A:eth0", "nope:eth0", LinkResult.Reason.UNKNOWN_PORT)
	_expect_reject(sim, "R1:g0/0.10", "S1:fa0/1", LinkResult.Reason.NOT_PHYSICAL)
	_expect_reject(sim, "S1:fa0/1", "S1:fa0/2", LinkResult.Reason.SAME_DEVICE)
	_expect_reject(sim, "S1:fa0/1", "S1:fa0/1", LinkResult.Reason.SAME_DEVICE)
	_expect_reject(sim, "PC-A:eth0", "S1:fa0/24", LinkResult.Reason.PORT_RESERVED)
	# Check order: SAME_DEVICE wins over PORT_RESERVED.
	_expect_reject(sim, "S1:fa0/24", "S1:fa0/1", LinkResult.Reason.SAME_DEVICE)
	assert_bool(sim.connect_link("PC-A:eth0", "S1:fa0/1").ok).is_true()
	_expect_reject(sim, "PC-B:eth0", "S1:fa0/1", LinkResult.Reason.PORT_IN_USE)
	var broke := _world(0)
	_watch(broke)
	_expect_reject(broke, "PC-A:eth0", "S1:fa0/1", LinkResult.Reason.NO_SPARE_CABLE)


func test_disconnect() -> void:
	var sim := _pcs(1)
	sim.connect_link("PC-A:eth0", "PC-B:eth0")
	_watch(sim)
	var r: LinkResult = sim.disconnect_link("PC-B:eth0")
	assert_bool(r.ok).is_true()
	assert_str(sim.interface_at("PC-A:Ethernet0").peer_port).is_equal("")
	assert_str(sim.interface_at("PC-B:Ethernet0").peer_port).is_equal("")
	assert_int(sim.spare_cables()).is_equal(1)
	assert_array(_links).is_equal([["PC-B:Ethernet0", "PC-A:Ethernet0", false]])
	assert_array(_states).is_equal([["PC-B:Ethernet0", false], ["PC-A:Ethernet0", false]])
	assert_int(sim.disconnect_link("PC-B:eth0").reason).is_equal(LinkResult.Reason.NOT_CONNECTED)
	assert_int(sim.disconnect_link("nope:eth0").reason).is_equal(LinkResult.Reason.UNKNOWN_PORT)
	assert_int(_links.size()).is_equal(1)


func test_disconnect_from_either_end() -> void:
	var sim := _pcs(1)
	sim.connect_link("PC-A:eth0", "PC-B:eth0")
	assert_bool(sim.disconnect_link("PC-A:eth0").ok).is_true()
	assert_int(sim.spare_cables()).is_equal(1)


func test_locked_fixed_link() -> void:
	var sim := _pcs(0)
	_watch(sim)
	assert_bool(sim.add_fixed_link("PC-A:eth0", "PC-B:eth0").ok).is_true()
	assert_int(sim.spare_cables()).is_equal(0)
	assert_int(_links.size()).is_equal(0)
	assert_int(_states.size()).is_equal(0)
	assert_bool(sim.is_oper_up("PC-A:Ethernet0")).is_true()
	assert_int(sim.disconnect_link("PC-A:eth0").reason).is_equal(LinkResult.Reason.LOCKED)
	assert_str(sim.interface_at("PC-A:Ethernet0").peer_port).is_equal("PC-B:Ethernet0")
	assert_int(_links.size()).is_equal(0)
	assert_int(_states.size()).is_equal(0)
	assert_int(sim.spare_cables()).is_equal(0)


func test_unlocked_fixed_link_returns_cable() -> void:
	var sim := _pcs(0)
	assert_bool(sim.add_fixed_link("PC-A:eth0", "PC-B:eth0", false).ok).is_true()
	assert_bool(sim.disconnect_link("PC-A:eth0").ok).is_true()
	assert_int(sim.spare_cables()).is_equal(1)


func test_fixed_link_ignores_reservation_but_checks_the_rest() -> void:
	var sim := _world(0)
	sim.reserve_port("S1:fa0/1")
	assert_bool(sim.add_fixed_link("PC-A:eth0", "S1:fa0/1").ok).is_true()
	assert_int(sim.add_fixed_link("PC-B:eth0", "S1:fa0/1").reason).is_equal(LinkResult.Reason.PORT_IN_USE)
	assert_int(sim.add_fixed_link("S1:fa0/2", "S1:fa0/3").reason).is_equal(LinkResult.Reason.SAME_DEVICE)
	assert_int(sim.add_fixed_link("nope:eth0", "S1:fa0/3").reason).is_equal(LinkResult.Reason.UNKNOWN_PORT)


func test_oper_up_rules() -> void:
	var sim := _world(1)
	var r1: Router = sim.get_device("R1")
	r1.interface("g0/0").admin_up = true
	var sub: Interface = r1.add_subinterface("g0/0.10")
	assert_bool(sim.is_oper_up("R1:Gi0/0")).is_false()  # no cable
	assert_bool(sim.is_oper_up("R1:Gi0/0.10")).is_false()  # parent has no cable
	sim.connect_link("R1:g0/0", "S1:fa0/1")
	assert_bool(sim.is_oper_up("R1:Gi0/0")).is_true()
	assert_bool(sim.is_oper_up("R1:Gi0/0.10")).is_true()
	sub.admin_up = false
	assert_bool(sim.is_oper_up("R1:Gi0/0.10")).is_false()
	sub.admin_up = true
	r1.interface("g0/0").admin_up = false
	assert_bool(sim.is_oper_up("R1:Gi0/0.10")).is_false()
	assert_bool(sim.is_oper_up("S1:Fa0/1")).is_false()
	assert_bool(sim.is_oper_up("nope:eth0")).is_false()


func test_subinterface_state_signals() -> void:
	var sim := _world(1)
	var r1: Router = sim.get_device("R1")
	r1.interface("g0/0").admin_up = true
	r1.add_subinterface("g0/0.10")
	_watch(sim)
	sim.connect_link("R1:g0/0", "S1:fa0/1")
	assert_array(_states).is_equal([
		["R1:GigabitEthernet0/0", true],
		["R1:GigabitEthernet0/0.10", true],
		["S1:FastEthernet0/1", true],
	])
	_states.clear()
	sim.disconnect_link("R1:g0/0")
	assert_array(_states).is_equal([
		["R1:GigabitEthernet0/0", false],
		["R1:GigabitEthernet0/0.10", false],
		["S1:FastEthernet0/1", false],
	])
