class_name TestResolver
extends GdUnitTestSuite

const R := PingResult.FailReason


func _assert_fail(r: PingResult, reason: PingResult.FailReason, at: String) -> void:
	assert_bool(r.success).override_failure_message("expected a failure, got success").is_false()
	assert_str(PingResult.reason_name(r.fail_reason)).is_equal(PingResult.reason_name(reason))
	assert_str(r.fail_at).is_equal(at)


func _assert_ok(r: PingResult, hops: Array) -> void:
	assert_str(PingResult.reason_name(r.fail_reason)).is_equal("NONE")
	assert_bool(r.success).is_true()
	assert_array(r.hops).is_equal(hops)


func _host(t: TopoBuilder, id: String) -> Host:
	return t.sim.get_device(id)


func _r1(t: TopoBuilder) -> Router:
	return t.sim.get_device("R1")


## stick() plus R2: a 10.0.0.0/30 link R1:Gi0/1 <-> R2:Gi0/0, and PC-C
## (172.16.0.10/24, gw 172.16.0.1) cabled straight to R2:Gi0/1.
func _two_routers() -> TopoBuilder:
	var t := TopoBuilder.stick()
	t.add("router_2port", "R2")
	t.add("pc", "PC-C")
	t.cable("R1:GigabitEthernet0/1", "R2:GigabitEthernet0/0")
	t.up("R1:GigabitEthernet0/1")
	t.up("R2:GigabitEthernet0/0")
	t.set_ip("R1:GigabitEthernet0/1", "10.0.0.1", "255.255.255.252")
	t.set_ip("R2:GigabitEthernet0/0", "10.0.0.2", "255.255.255.252")
	t.cable("R2:GigabitEthernet0/1", "PC-C:Ethernet0")
	t.up("R2:GigabitEthernet0/1")
	t.set_ip("R2:GigabitEthernet0/1", "172.16.0.1", "255.255.255.0")
	t.set_host("PC-C", "172.16.0.10", "255.255.255.0", "172.16.0.1")
	return t


func _route(net: String, mask: String, next_hop: String) -> Dictionary:
	return {"network": net, "mask": mask, "next_hop": next_hop}


# --- success -----------------------------------------------------------------


func test_same_subnet_no_router() -> void:
	var t := TopoBuilder.flat()
	_assert_ok(t.sim.ping("PC-A", "192.168.10.20"), ["PC-A", "PC-B"])
	_assert_ok(t.sim.ping("PC-B", "192.168.10.10"), ["PC-B", "PC-A"])


func test_router_on_a_stick() -> void:
	var t := TopoBuilder.stick()
	_assert_ok(t.sim.ping("PC-A", "192.168.20.10"), ["PC-A", "R1", "PC-B"])
	_assert_ok(t.sim.ping("PC-B", "192.168.10.10"), ["PC-B", "R1", "PC-A"])


func test_ping_gateway_ip() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").gateway = ""
	_assert_ok(t.sim.ping("PC-A", "192.168.10.1"), ["PC-A", "R1"])


func test_router_pings_from_egress_ip() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-B").gateway = ""
	_assert_ok(t.sim.ping("R1", "192.168.20.10"), ["R1", "PC-B"])


func test_connected_beats_default() -> void:
	var t := _two_routers()
	_r1(t).static_routes.append(_route("0.0.0.0", "0.0.0.0", "10.0.0.2"))
	_assert_ok(t.sim.ping("PC-A", "192.168.20.10"), ["PC-A", "R1", "PC-B"])


func test_longest_prefix_wins_between_statics() -> void:
	var t := _two_routers()
	(t.sim.get_device("R2") as Router).static_routes.append(_route("192.168.10.0", "255.255.255.0", "10.0.0.1"))
	# The /8 sends traffic to a dead next hop; the more specific /24 must win.
	_r1(t).static_routes.append(_route("172.0.0.0", "255.0.0.0", "192.168.10.99"))
	_r1(t).static_routes.append(_route("172.16.0.0", "255.255.255.0", "10.0.0.2"))
	_assert_ok(t.sim.ping("PC-A", "172.16.0.10"), ["PC-A", "R1", "R2", "PC-C"])


func test_static_routes_two_routers() -> void:
	var t := _two_routers()
	_r1(t).static_routes.append(_route("172.16.0.0", "255.255.255.0", "10.0.0.2"))
	var r := t.sim.ping("PC-A", "172.16.0.10")
	_assert_fail(r, R.NO_ROUTE, "R2")
	assert_array(r.hops).is_equal(["PC-A", "R1", "R2", "PC-C"])
	(t.sim.get_device("R2") as Router).static_routes.append(_route("192.168.10.0", "255.255.255.0", "10.0.0.1"))
	_assert_ok(t.sim.ping("PC-A", "172.16.0.10"), ["PC-A", "R1", "R2", "PC-C"])


func test_static_route_with_next_hop_off_connected_is_unusable() -> void:
	var t := _two_routers()
	_r1(t).static_routes.append(_route("172.16.0.0", "255.255.255.0", "10.9.9.9"))
	_assert_fail(t.sim.ping("PC-A", "172.16.0.10"), R.NO_ROUTE, "R1")


# --- one test per fail reason --------------------------------------------------


func test_no_ip() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").nic().ip = ""
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_IP, "PC-A")


func test_no_link() -> void:
	var t := TopoBuilder.stick()
	t.sim.disconnect_link("PC-A:Ethernet0")
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_LINK, "PC-A")
	var t2 := TopoBuilder.stick()
	t2.sim.disconnect_link("PC-B:Ethernet0")
	_assert_fail(t2.sim.ping("PC-A", "192.168.20.10"), R.NO_LINK, "R1")


func test_admin_down_router_port() -> void:
	var t := TopoBuilder.stick()
	_r1(t).interface("g0/0").admin_up = false
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.ADMIN_DOWN, "PC-A")


func test_admin_down_source_nic() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").nic().admin_up = false
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.ADMIN_DOWN, "PC-A")


func test_admin_down_subinterface() -> void:
	var t := TopoBuilder.stick()
	_r1(t).interface("g0/0.10").admin_up = false
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.ADMIN_DOWN, "PC-A")


func test_admin_down_egress_subinterface_of_router() -> void:
	var t := TopoBuilder.stick()
	_r1(t).interface("g0/0.20").admin_up = false
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.ADMIN_DOWN, "R1")


func test_vlan_mismatch_access_port() -> void:
	var t := TopoBuilder.stick()
	t.access("S1:FastEthernet0/1", 20)
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.VLAN_MISMATCH, "PC-A")


func test_vlan_mismatch_trunk_allowed() -> void:
	var t := TopoBuilder.stick()
	t.trunk("S1:GigabitEthernet0/1", [20])
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.VLAN_MISMATCH, "PC-A")


func test_vlan_mismatch_flat() -> void:
	var t := TopoBuilder.flat()
	(t.sim.get_device("S1") as Switch).add_vlan(20, "V20")
	t.access("S1:FastEthernet0/2", 20)
	_assert_fail(t.sim.ping("PC-A", "192.168.10.20"), R.VLAN_MISMATCH, "PC-A")


func test_vlan_mismatch_vlan_missing_from_database() -> void:
	var t := TopoBuilder.stick()
	(t.sim.get_device("S1") as Switch).remove_vlan(10)
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.VLAN_MISMATCH, "PC-A")


func test_wrong_subnet() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").gateway = "192.168.99.1"
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.WRONG_SUBNET, "PC-A")


func test_no_gateway() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").gateway = ""
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_GATEWAY, "PC-A")
	_assert_ok(t.sim.ping("PC-A", "192.168.10.1"), ["PC-A", "R1"])


func test_no_route() -> void:
	var t := TopoBuilder.stick()
	_r1(t).interface("g0/0.20").ip = ""
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_ROUTE, "R1")
	_assert_fail(t.sim.ping("PC-A", "8.8.8.8"), R.NO_ROUTE, "R1")


func test_host_unreachable_same_subnet() -> void:
	var t := TopoBuilder.stick()
	_assert_fail(t.sim.ping("PC-A", "192.168.10.99"), R.HOST_UNREACHABLE, "PC-A")


func test_host_unreachable_behind_router() -> void:
	var t := TopoBuilder.stick()
	_assert_fail(t.sim.ping("PC-A", "192.168.20.99"), R.HOST_UNREACHABLE, "R1")


func test_host_unreachable_gateway_is_a_host() -> void:
	var t := TopoBuilder.flat()
	_host(t, "PC-A").gateway = "192.168.10.20"
	_assert_fail(t.sim.ping("PC-A", "8.8.8.8"), R.HOST_UNREACHABLE, "PC-B")


func test_acl_denied_exists_but_is_never_produced() -> void:
	assert_bool(PingResult.FailReason.has("ACL_DENIED")).is_true()
	var t := TopoBuilder.stick()
	assert_int(t.sim.ping("PC-A", "192.168.20.10").fail_reason).is_not_equal(R.ACL_DENIED)


# --- first reason wins -----------------------------------------------------------


func test_ordering_no_link_before_no_gateway() -> void:
	var t := TopoBuilder.stick()
	t.sim.disconnect_link("PC-A:Ethernet0")
	_host(t, "PC-A").gateway = ""
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_LINK, "PC-A")


func test_ordering_no_gateway_before_target_no_link() -> void:
	var t := TopoBuilder.stick()
	t.sim.disconnect_link("PC-B:Ethernet0")
	_host(t, "PC-A").gateway = ""
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_GATEWAY, "PC-A")


func test_ordering_wrong_subnet_before_admin_down() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").gateway = "192.168.99.1"
	_r1(t).interface("g0/0").admin_up = false
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.WRONG_SUBNET, "PC-A")


func test_ordering_no_ip_before_no_link() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").nic().ip = ""
	t.sim.disconnect_link("PC-A:Ethernet0")
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.NO_IP, "PC-A")


func test_asymmetric_reply_failure() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-B").gateway = ""
	var r := t.sim.ping("PC-A", "192.168.20.10")
	_assert_fail(r, R.NO_GATEWAY, "PC-B")
	assert_array(r.hops).is_equal(["PC-A", "R1", "PC-B"])


# --- review focus --------------------------------------------------------------


func test_route_loop_terminates_no_route() -> void:
	var t := _two_routers()
	_r1(t).static_routes.append(_route("0.0.0.0", "0.0.0.0", "10.0.0.2"))
	(t.sim.get_device("R2") as Router).static_routes.append(_route("0.0.0.0", "0.0.0.0", "10.0.0.1"))
	var r := t.sim.ping("PC-A", "8.8.8.8")
	assert_bool(r.success).is_false()
	assert_str(PingResult.reason_name(r.fail_reason)).is_equal("NO_ROUTE")
	assert_bool(r.fail_at == "R1" or r.fail_at == "R2").is_true()


func test_bad_destination_strings(
	dst: String,
	test_parameters := [[""], ["256.1.1.1"], ["0.0.0.0"], ["192.168.010.1"], ["junk"]]
) -> void:
	var t := TopoBuilder.stick()
	_assert_fail(t.sim.ping("PC-A", dst), R.HOST_UNREACHABLE, "PC-A")


func test_ping_own_ip() -> void:
	var t := TopoBuilder.stick()
	_assert_ok(t.sim.ping("PC-A", "192.168.10.10"), ["PC-A"])
	_assert_ok(t.sim.ping("R1", "192.168.10.1"), ["R1"])


func test_gateway_is_self() -> void:
	var t := TopoBuilder.stick()
	_host(t, "PC-A").gateway = "192.168.10.10"
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.HOST_UNREACHABLE, "PC-A")


func _with_duplicate_ip() -> TopoBuilder:
	var t := TopoBuilder.stick()
	t.add("pc", "PC-C")
	t.cable("PC-C:Ethernet0", "S1:FastEthernet0/3")
	t.access("S1:FastEthernet0/3", 20)
	t.set_host("PC-C", "192.168.20.10", "255.255.255.0", "192.168.20.1")
	return t


func test_duplicate_ip_only_second_reachable() -> void:
	var t := _with_duplicate_ip()
	t.sim.disconnect_link("PC-B:Ethernet0")
	_assert_ok(t.sim.ping("PC-A", "192.168.20.10"), ["PC-A", "R1", "PC-C"])


func test_duplicate_ip_both_reachable_picks_first_by_id() -> void:
	var t := _with_duplicate_ip()
	_assert_ok(t.sim.ping("PC-A", "192.168.20.10"), ["PC-A", "R1", "PC-B"])


func test_duplicate_ip_neither_reachable_classifies_against_first() -> void:
	var t := _with_duplicate_ip()
	_host(t, "PC-B").nic().admin_up = false
	t.sim.disconnect_link("PC-C:Ethernet0")
	_assert_fail(t.sim.ping("PC-A", "192.168.20.10"), R.ADMIN_DOWN, "R1")


func test_sub_without_dot1q() -> void:
	var t := TopoBuilder.stick()
	_r1(t).interface("g0/0.10").dot1q_vlan = 0
	_assert_fail(t.sim.ping("PC-A", "192.168.10.1"), R.VLAN_MISMATCH, "PC-A")
	_assert_fail(t.sim.ping("R1", "192.168.10.10"), R.VLAN_MISMATCH, "R1")


func test_unknown_source_and_switch_source() -> void:
	var t := TopoBuilder.stick()
	_assert_fail(t.sim.ping("nope", "192.168.10.10"), R.NO_IP, "")
	_assert_fail(t.sim.ping("S1", "192.168.10.10"), R.NO_IP, "")
