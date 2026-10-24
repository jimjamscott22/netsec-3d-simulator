class_name TestModels
extends GdUnitTestSuite


func test_router_2port() -> void:
	var d: Device = DeviceModels.build("router_2port", "R1")
	assert_int(d.kind()).is_equal(Device.Kind.ROUTER)
	assert_array(d.interfaces.keys()).is_equal(["GigabitEthernet0/0", "GigabitEthernet0/1"])
	for i: Interface in d.interfaces.values():
		assert_bool(i.admin_up).is_false()


func test_switch_24() -> void:
	var d: Device = DeviceModels.build("switch_24", "S1")
	assert_int(d.kind()).is_equal(Device.Kind.SWITCH)
	var names: Array = d.interfaces.keys()
	assert_int(names.size()).is_equal(26)
	assert_str(names[0]).is_equal("FastEthernet0/1")
	assert_str(names[23]).is_equal("FastEthernet0/24")
	assert_str(names[24]).is_equal("GigabitEthernet0/1")
	assert_str(names[25]).is_equal("GigabitEthernet0/2")
	for i: Interface in d.interfaces.values():
		assert_bool(i.admin_up).is_true()
		assert_int(i.mode).is_equal(Interface.Mode.ACCESS)
		assert_int(i.access_vlan).is_equal(1)


func test_pc_and_server() -> void:
	var pc: Device = DeviceModels.build("pc", "PC-A")
	var srv: Device = DeviceModels.build("server", "SRV")
	assert_array(pc.interfaces.keys()).is_equal(["Ethernet0"])
	assert_bool(pc.interfaces["Ethernet0"].admin_up).is_true()
	assert_array(srv.interfaces.keys()).is_equal(["Ethernet0"])
	assert_bool(srv.interfaces["Ethernet0"].admin_up).is_true()
	assert_bool(srv is Server).is_true()
	assert_bool(pc is Server).is_false()
	assert_bool(pc is Host).is_true()


func test_hostname_defaults_to_id() -> void:
	assert_str(DeviceModels.build("pc", "PC-A").hostname).is_equal("PC-A")


func test_unknown_model() -> void:
	assert_bool(DeviceModels.has_model("nope")).is_false()
	assert_object(DeviceModels.build("nope", "X")).is_null()
	assert_array(DeviceModels.interface_names("nope")).is_empty()


func test_interface_names_match_build(
	model: String,
	test_parameters := [["router_2port"], ["switch_24"], ["pc"], ["server"]]
) -> void:
	assert_bool(DeviceModels.has_model(model)).is_true()
	var d: Device = DeviceModels.build(model, "X")
	assert_array(DeviceModels.interface_names(model)).is_equal(d.interfaces.keys())
