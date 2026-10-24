class_name TestIfName
extends GdUnitTestSuite


func test_normalize_aliases(
	raw: String,
	expected: String,
	test_parameters := [
		["g0/1", "GigabitEthernet0/1"], ["G0/1", "GigabitEthernet0/1"],
		["gi0/1", "GigabitEthernet0/1"], ["Gi0/1", "GigabitEthernet0/1"],
		["gig0/1", "GigabitEthernet0/1"], ["gigabitethernet0/1", "GigabitEthernet0/1"],
		["GigabitEthernet0/1", "GigabitEthernet0/1"], ["gi 0/1", "GigabitEthernet0/1"],
		["fa0/1", "FastEthernet0/1"], ["f0/1", "FastEthernet0/1"],
		["fas0/1", "FastEthernet0/1"], ["FastEthernet0/1", "FastEthernet0/1"],
		["eth0", "Ethernet0"], ["e0", "Ethernet0"], ["Ethernet0", "Ethernet0"],
		["g0/0.10", "GigabitEthernet0/0.10"],
	]
) -> void:
	assert_str(IfName.normalize(raw)).is_equal(expected)


func test_normalize_invalid(
	raw: String,
	test_parameters := [
		[""], ["g"], ["g0/"], ["0/1"], ["gx0/1"], ["fe0/1"], ["g0/1."], ["g0/1.0"],
		["g0/1.a"], ["g0//1"], ["lo0"], ["gigabitethernets0/1"],
	]
) -> void:
	assert_str(IfName.normalize(raw)).is_equal("")


func test_short_name() -> void:
	assert_str(IfName.short_name("GigabitEthernet0/1")).is_equal("Gi0/1")
	assert_str(IfName.short_name("FastEthernet0/24")).is_equal("Fa0/24")
	assert_str(IfName.short_name("Ethernet0")).is_equal("Eth0")
	assert_str(IfName.short_name("GigabitEthernet0/0.10")).is_equal("Gi0/0.10")
	assert_str(IfName.short_name("junk")).is_equal("")


func test_subinterface_helpers() -> void:
	assert_str(IfName.parent_of("GigabitEthernet0/0.10")).is_equal("GigabitEthernet0/0")
	assert_int(IfName.sub_id("GigabitEthernet0/0.10")).is_equal(10)
	assert_bool(IfName.is_subinterface("GigabitEthernet0/0.10")).is_true()
	assert_str(IfName.parent_of("GigabitEthernet0/0")).is_equal("")
	assert_int(IfName.sub_id("GigabitEthernet0/0")).is_equal(-1)
	assert_bool(IfName.is_subinterface("GigabitEthernet0/0")).is_false()


func test_ports() -> void:
	assert_str(IfName.canonical_port("S1:fa0/1")).is_equal("S1:FastEthernet0/1")
	assert_str(IfName.canonical_port("S1:g0/1")).is_equal("S1:GigabitEthernet0/1")
	assert_str(IfName.canonical_port("S1")).is_equal("")
	assert_str(IfName.canonical_port(":g0/1")).is_equal("")
	assert_str(IfName.canonical_port("S1:bogus")).is_equal("")
	assert_str(IfName.port_device("S1:FastEthernet0/1")).is_equal("S1")
	assert_str(IfName.port_iface("S1:FastEthernet0/1")).is_equal("FastEthernet0/1")
