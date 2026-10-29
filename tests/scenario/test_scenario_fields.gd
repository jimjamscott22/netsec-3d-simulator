class_name TestScenarioFields
extends GdUnitTestSuite

func test_is_int_accepts_whole_numbers_in_either_form() -> void:
	assert_bool(ScenarioFields.is_int(3)).is_true()
	assert_bool(ScenarioFields.is_int(3.0)).is_true()
	assert_bool(ScenarioFields.is_int(-2.0)).is_true()
	assert_bool(ScenarioFields.is_int(3.5)).is_false()
	assert_bool(ScenarioFields.is_int(INF)).is_false()
	assert_bool(ScenarioFields.is_int(NAN)).is_false()


func test_is_int_rejects_other_types() -> void:
	for v: Variant in ["3", true, null, [3], {"a": 3}]:
		assert_bool(ScenarioFields.is_int(v)).override_failure_message(str(v)).is_false()


func test_to_int_reads_a_json_style_float() -> void:
	assert_int(ScenarioFields.to_int(10.0)).is_equal(10)


func test_parse_vlan_key() -> void:
	assert_int(ScenarioFields.parse_vlan_key("10")).is_equal(10)
	assert_int(ScenarioFields.parse_vlan_key("1")).is_equal(1)
	assert_int(ScenarioFields.parse_vlan_key("4094")).is_equal(4094)
	for bad in ["", "0", "4095", "-5", "+5", "010", "1.5", "ten", " 10", "10 "]:
		assert_int(ScenarioFields.parse_vlan_key(bad)).override_failure_message('"%s"' % bad).is_equal(-1)


func test_check_value_accepts_good_values() -> void:
	var good: Array = [
		[ScenarioFields.Kind.BOOL, true],
		[ScenarioFields.Kind.BOOL, false],
		[ScenarioFields.Kind.STRING, "x"],
		[ScenarioFields.Kind.NAME, "SALES"],
		[ScenarioFields.Kind.IPV4, "192.168.10.1"],
		[ScenarioFields.Kind.MASK, "255.255.255.0"],
		[ScenarioFields.Kind.MASK, "255.255.255.252"],
		[ScenarioFields.Kind.VLAN_ID, 10],
		[ScenarioFields.Kind.VLAN_ID, 4094.0],
		[ScenarioFields.Kind.VLAN_LIST, [10, 20.0]],
		[ScenarioFields.Kind.SWITCHPORT_MODE, "access"],
		[ScenarioFields.Kind.SWITCHPORT_MODE, "trunk"],
	]
	for pair: Array in good:
		assert_str(ScenarioFields.check_value(pair[0], pair[1])).override_failure_message(str(pair)).is_empty()


func test_check_value_rejects_bad_values_with_a_reason() -> void:
	var bad: Array = [
		[ScenarioFields.Kind.BOOL, "yes", "be true or false"],
		[ScenarioFields.Kind.BOOL, 1, "be true or false"],
		[ScenarioFields.Kind.STRING, "", "be a non-empty string"],
		[ScenarioFields.Kind.STRING, 5, "be a non-empty string"],
		[ScenarioFields.Kind.NAME, "two words", "be a single word with no spaces"],
		[ScenarioFields.Kind.NAME, "", "be a single word with no spaces"],
		[ScenarioFields.Kind.IPV4, "300.1.1.1", "be an IPv4 address such as 192.168.10.1"],
		[ScenarioFields.Kind.IPV4, 5, "be an IPv4 address such as 192.168.10.1"],
		[ScenarioFields.Kind.MASK, "255.0.255.0", "be a subnet mask such as 255.255.255.0"],
		[ScenarioFields.Kind.VLAN_ID, 0, "be a VLAN id from 1 to 4094"],
		[ScenarioFields.Kind.VLAN_ID, 4095, "be a VLAN id from 1 to 4094"],
		[ScenarioFields.Kind.VLAN_ID, 1.5, "be a VLAN id from 1 to 4094"],
		[ScenarioFields.Kind.VLAN_ID, "10", "be a VLAN id from 1 to 4094"],
		[ScenarioFields.Kind.VLAN_LIST, 10, "be a list of VLAN ids"],
		[ScenarioFields.Kind.VLAN_LIST, [], "not be empty (leave it out to allow every VLAN)"],
		[ScenarioFields.Kind.VLAN_LIST, [10, 10], "list each VLAN once"],
		[ScenarioFields.Kind.VLAN_LIST, [10, 0], "be a list of VLAN ids from 1 to 4094"],
		[ScenarioFields.Kind.SWITCHPORT_MODE, "dynamic", 'be "access" or "trunk"'],
	]
	for row: Array in bad:
		assert_str(ScenarioFields.check_value(row[0], row[1])).override_failure_message(str(row)).is_equal(row[2])


func test_field_tables_match_the_device_model() -> void:
	# Every field a scenario can set is one the loader will have to apply.
	var iface := Interface.new("R1", "Gi0/0", true)
	for field: String in ScenarioFields.ROUTER_INTERFACE_FIELDS:
		assert_bool(field in iface).override_failure_message("Interface has no '%s'" % field).is_true()
	for field: String in ScenarioFields.SWITCH_INTERFACE_FIELDS:
		assert_bool(field in iface).override_failure_message("Interface has no '%s'" % field).is_true()
	var host := Host.new("PC")
	assert_bool("gateway" in host and "locked" in host).is_true()
