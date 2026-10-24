class_name TestInterface
extends GdUnitTestSuite


func test_interface_names_and_port() -> void:
	var i := Interface.new("R1", "g0/0", false)
	assert_str(i.full_name).is_equal("GigabitEthernet0/0")
	assert_str(i.short_name).is_equal("Gi0/0")
	assert_str(i.port()).is_equal("R1:GigabitEthernet0/0")
	assert_bool(i.is_sub()).is_false()
	assert_bool(i.admin_up).is_false()


func test_has_address(
	ip: String,
	mask: String,
	expected: bool,
	test_parameters := [
		["192.168.1.1", "255.255.255.0", true],
		["", "255.255.255.0", false],
		["192.168.1.1", "", false],
		["192.168.1.1", "255.0.255.0", false],
		["300.1.1.1", "255.0.0.0", false],
	]
) -> void:
	var i := Interface.new("PC", "eth0", true)
	i.ip = ip
	i.mask = mask
	assert_bool(i.has_address()).is_equal(expected)


func test_trunk_allows() -> void:
	var i := Interface.new("S1", "g0/1", true)
	assert_bool(i.trunk_allows(1)).is_true()
	assert_bool(i.trunk_allows(4094)).is_true()
	i.trunk_allowed_all = false
	i.trunk_allowed = [10, 20]
	assert_bool(i.trunk_allows(10)).is_true()
	assert_bool(i.trunk_allows(30)).is_false()


func test_interface_defaults() -> void:
	var i := Interface.new("S1", "fa0/1", true)
	assert_int(i.mode).is_equal(Interface.Mode.ACCESS)
	assert_int(i.access_vlan).is_equal(1)
	assert_str(i.peer_port).is_equal("")
	assert_int(i.dot1q_vlan).is_equal(0)
