class_name TestL2
extends GdUnitTestSuite


## Reachable endpoints as sorted "port|tag" strings.
func _eps(net: NetworkSim, start: String, tag: int, mode: L2.Mode) -> Array[String]:
	var out: Array[String] = []
	for e: L2Endpoint in L2.reach(net, start, tag, mode):
		out.append("%s|%d" % [e.port, e.tag])
	out.sort()
	return out


func test_same_vlan_reach() -> void:
	var t := TopoBuilder.flat()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_equal(["PC-B:Ethernet0|0"])
	assert_array(_eps(t.sim, "PC-B:Ethernet0", 0, L2.Mode.VLAN)).is_equal(["PC-A:Ethernet0|0"])


func test_different_vlan_blocked_by_vlan_not_by_oper() -> void:
	var t := TopoBuilder.flat()
	(t.sim.get_device("S1") as Switch).add_vlan(20, "V20")
	t.access("S1:FastEthernet0/2", 20)
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_empty()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.OPER)).contains(["PC-B:Ethernet0|0"])
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.CABLES)).contains(["PC-B:Ethernet0|0"])


func test_trunk_carries_tagged_vlan() -> void:
	var t := TopoBuilder.stick()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_equal(["R1:GigabitEthernet0/0|10"])
	var r1: Router = t.sim.get_device("R1")
	assert_bool(L2.reaches(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN, r1.interface("g0/0.10"))).is_true()
	assert_bool(L2.reaches(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN, r1.interface("g0/0.20"))).is_false()
	assert_bool(L2.reaches(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN, r1.interface("g0/0"))).is_false()
	# From the router side: sub .10 sends tag 10 and reaches PC-A only.
	var from_router: Array[String] = _eps(t.sim, "R1:GigabitEthernet0/0", 10, L2.Mode.VLAN)
	assert_array(from_router).is_equal(["PC-A:Ethernet0|0"])


func test_trunk_allowed_list_excludes() -> void:
	var t := TopoBuilder.stick()
	t.trunk("S1:GigabitEthernet0/1", [20])
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_empty()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.OPER)).contains(["R1:GigabitEthernet0/0|0"])


func test_untagged_on_trunk_is_native_vlan_1() -> void:
	var t := TopoBuilder.new()
	t.add("switch_24", "S1")
	t.add("router_2port", "R1")
	t.add("pc", "PC-A")
	t.cable("PC-A:Ethernet0", "S1:FastEthernet0/1")
	t.cable("S1:GigabitEthernet0/1", "R1:GigabitEthernet0/0")
	t.up("R1:GigabitEthernet0/0")
	t.trunk("S1:GigabitEthernet0/1")
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_equal(["R1:GigabitEthernet0/0|0"])
	t.trunk("S1:GigabitEthernet0/1", [1, 10])
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_equal(["R1:GigabitEthernet0/0|0"])
	t.trunk("S1:GigabitEthernet0/1", [10])
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_empty()


func test_tagged_frame_into_access_port_dropped() -> void:
	var t := TopoBuilder.stick()
	t.access("S1:GigabitEthernet0/1", 10)
	assert_array(_eps(t.sim, "R1:GigabitEthernet0/0", 10, L2.Mode.VLAN)).is_empty()
	# The same frame, untagged, is accepted into the access VLAN.
	assert_array(_eps(t.sim, "R1:GigabitEthernet0/0", 0, L2.Mode.VLAN)).is_equal(["PC-A:Ethernet0|0"])


func test_vlan_missing_from_db_blocks() -> void:
	var t := TopoBuilder.stick()
	(t.sim.get_device("S1") as Switch).remove_vlan(10)
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_empty()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.OPER)).contains(["R1:GigabitEthernet0/0|0"])


func _chain() -> TopoBuilder:
	var t := TopoBuilder.stick()
	t.add("switch_24", "S2")
	t.add("pc", "PC-C")
	(t.sim.get_device("S2") as Switch).add_vlan(10, "V10")
	t.cable("S1:GigabitEthernet0/2", "S2:GigabitEthernet0/1")
	t.trunk("S1:GigabitEthernet0/2")
	t.trunk("S2:GigabitEthernet0/1")
	t.cable("PC-C:Ethernet0", "S2:FastEthernet0/1")
	t.access("S2:FastEthernet0/1", 10)
	return t


func test_multi_switch_chain() -> void:
	var t := _chain()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).contains(["PC-C:Ethernet0|0"])
	t.trunk("S1:GigabitEthernet0/2", [20])
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).not_contains(["PC-C:Ethernet0|0"])


func test_multi_switch_chain_vlan_missing_on_second_switch() -> void:
	var t := _chain()
	(t.sim.get_device("S2") as Switch).remove_vlan(10)
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).not_contains(["PC-C:Ethernet0|0"])
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.OPER)).contains(["PC-C:Ethernet0|0"])


func test_admin_down_link_excluded_in_oper() -> void:
	var t := TopoBuilder.flat()
	t.sim.interface_at("S1:FastEthernet0/2").admin_up = false
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.OPER)).is_empty()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN)).is_empty()
	assert_array(_eps(t.sim, "PC-A:Ethernet0", 0, L2.Mode.CABLES)).is_equal(["PC-B:Ethernet0|0"])


func test_ring_terminates() -> void:
	var t := TopoBuilder.new()
	for n in [1, 2, 3]:
		t.add("switch_24", "S%d" % n)
		t.add("pc", "P%d" % n)
		t.cable("P%d:Ethernet0" % n, "S%d:FastEthernet0/1" % n)
	t.cable("S1:GigabitEthernet0/1", "S2:GigabitEthernet0/2")
	t.cable("S2:GigabitEthernet0/1", "S3:GigabitEthernet0/2")
	t.cable("S3:GigabitEthernet0/1", "S1:GigabitEthernet0/2")
	for n in [1, 2, 3]:
		t.trunk("S%d:GigabitEthernet0/1" % n)
		t.trunk("S%d:GigabitEthernet0/2" % n)
	for mode: L2.Mode in [L2.Mode.CABLES, L2.Mode.OPER, L2.Mode.VLAN]:
		assert_array(_eps(t.sim, "P1:Ethernet0", 0, mode)).is_equal(["P2:Ethernet0|0", "P3:Ethernet0|0"])


func test_unknown_or_uncabled_start() -> void:
	var t := TopoBuilder.flat()
	assert_array(_eps(t.sim, "nope:eth0", 0, L2.Mode.VLAN)).is_empty()
	assert_array(_eps(t.sim, "S1:FastEthernet0/9", 0, L2.Mode.VLAN)).is_empty()
	assert_array(_eps(t.sim, "garbage", 0, L2.Mode.CABLES)).is_empty()


func test_attachment_port() -> void:
	var t := TopoBuilder.stick()
	var r1: Router = t.sim.get_device("R1")
	assert_str(L2.attachment_port(t.sim, r1.interface("g0/0"))).is_equal("R1:GigabitEthernet0/0")
	assert_str(L2.attachment_port(t.sim, r1.interface("g0/0.10"))).is_equal("R1:GigabitEthernet0/0")


func test_sub_without_dot1q_is_never_reached_in_vlan_mode() -> void:
	var t := TopoBuilder.stick()
	var sub: Interface = (t.sim.get_device("R1") as Router).interface("g0/0.10")
	sub.dot1q_vlan = 0
	assert_bool(L2.reaches(t.sim, "PC-A:Ethernet0", 0, L2.Mode.VLAN, sub)).is_false()
	assert_bool(L2.reaches(t.sim, "PC-A:Ethernet0", 0, L2.Mode.OPER, sub)).is_true()
