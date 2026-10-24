class_name TestDeviceClasses
extends GdUnitTestSuite


func test_device_lookup_normalizes() -> void:
	var r := Router.new("R1")
	var i := Interface.new("R1", "g0/0", false)
	r.add_interface(i)
	assert_object(r.interface("gi0/0")).is_same(i)
	assert_object(r.interface("g0/9")).is_null()
	assert_str(r.hostname).is_equal("R1")


func test_router_add_subinterface() -> void:
	var r := Router.new("R1")
	r.add_interface(Interface.new("R1", "g0/0", false))
	var sub: Interface = r.add_subinterface("g0/0.10")
	assert_object(sub).is_not_null()
	assert_bool(sub.admin_up).is_true()
	assert_str(sub.parent).is_equal("GigabitEthernet0/0")
	assert_int(sub.dot1q_vlan).is_equal(0)
	assert_bool(sub.is_sub()).is_true()
	assert_object(r.interface("Gi0/0.10")).is_same(sub)
	assert_object(r.add_subinterface("g0/0.10")).is_null()
	assert_object(r.add_subinterface("g0/5.10")).is_null()
	assert_object(r.add_subinterface("g0/0")).is_null()


func test_switch_vlans() -> void:
	var s := Switch.new("S1")
	assert_dict(s.vlans).is_equal({1: "default"})
	assert_bool(s.remove_vlan(1)).is_false()
	assert_bool(s.vlans.has(1)).is_true()
	assert_bool(s.add_vlan(10, "SALES")).is_true()
	assert_bool(s.add_vlan(0, "x")).is_false()
	assert_bool(s.add_vlan(4095, "x")).is_false()
	assert_bool(s.remove_vlan(10)).is_true()
	assert_bool(s.remove_vlan(10)).is_false()


func test_kinds() -> void:
	assert_int(Router.new("R").kind()).is_equal(Device.Kind.ROUTER)
	assert_int(Switch.new("S").kind()).is_equal(Device.Kind.SWITCH)
	assert_int(Host.new("H").kind()).is_equal(Device.Kind.HOST)
	var srv := Server.new("SRV")
	assert_int(srv.kind()).is_equal(Device.Kind.SERVER)
	assert_bool(srv is Host).is_true()
	var h := Host.new("H")
	assert_bool(h.locked).is_false()
	assert_str(h.gateway).is_equal("")


func test_host_nic_is_first_interface() -> void:
	var h := Host.new("PC-A")
	assert_object(h.nic()).is_null()
	var nic := Interface.new("PC-A", "eth0", true)
	h.add_interface(nic)
	assert_object(h.nic()).is_same(nic)
