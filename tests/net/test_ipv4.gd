class_name TestIPv4
extends GdUnitTestSuite


func test_parse_valid() -> void:
	assert_int(IPv4.parse("0.0.0.0")).is_equal(0)
	assert_int(IPv4.parse("255.255.255.255")).is_equal(4294967295)
	assert_int(IPv4.parse("192.168.10.1")).is_equal(3232238081)


func test_parse_invalid(
	s: String,
	test_parameters := [
		[""], ["1.2.3"], ["1.2.3.4.5"], ["256.1.1.1"], ["1.2.3.-4"], ["a.b.c.d"],
		[" 1.2.3.4"], ["1.2.3.4 "], ["01.2.3.4"], ["1..3.4"], ["+1.2.3.4"],
	]
) -> void:
	assert_int(IPv4.parse(s)).is_equal(-1)
	assert_bool(IPv4.is_valid(s)).is_false()


func test_is_valid() -> void:
	assert_bool(IPv4.is_valid("10.0.0.1")).is_true()
	assert_bool(IPv4.is_valid("0.0.0.0")).is_true()


func test_format_round_trip() -> void:
	assert_str(IPv4.format(3232238081)).is_equal("192.168.10.1")
	for x: String in ["10.0.0.1", "172.16.254.3", "255.255.255.255"]:
		assert_str(IPv4.format(IPv4.parse(x))).is_equal(x)


func test_prefix_mask_round_trip() -> void:
	for p in range(0, 33):
		assert_int(IPv4.mask_to_prefix(IPv4.prefix_to_mask(p))).is_equal(p)
	assert_int(IPv4.prefix_to_mask(0)).is_equal(0)
	assert_int(IPv4.prefix_to_mask(24)).is_equal(4294967040)
	assert_int(IPv4.prefix_to_mask(32)).is_equal(4294967295)
	assert_int(IPv4.prefix_to_mask(33)).is_equal(-1)
	assert_int(IPv4.prefix_to_mask(-1)).is_equal(-1)


func test_parse_mask() -> void:
	assert_int(IPv4.parse_mask("255.255.255.0")).is_equal(4294967040)
	assert_int(IPv4.parse_mask("0.0.0.0")).is_equal(0)
	assert_int(IPv4.parse_mask("255.255.255.255")).is_equal(4294967295)
	for bad: String in ["255.0.255.0", "0.0.0.255", "255.255.255.253", "junk"]:
		assert_int(IPv4.parse_mask(bad)).is_equal(-1)


func test_mask_to_prefix_rejects_non_contiguous() -> void:
	assert_int(IPv4.mask_to_prefix(IPv4.parse("255.0.255.0"))).is_equal(-1)


func test_same_subnet() -> void:
	var m24: int = IPv4.prefix_to_mask(24)
	assert_bool(IPv4.same_subnet(IPv4.parse("192.168.10.5"), IPv4.parse("192.168.10.200"), m24)).is_true()
	assert_bool(IPv4.same_subnet(IPv4.parse("192.168.10.5"), IPv4.parse("192.168.11.5"), m24)).is_false()
	assert_bool(IPv4.same_subnet(IPv4.parse("1.2.3.4"), IPv4.parse("200.9.8.7"), 0)).is_true()
	var m32: int = IPv4.prefix_to_mask(32)
	assert_bool(IPv4.same_subnet(IPv4.parse("1.2.3.4"), IPv4.parse("1.2.3.4"), m32)).is_true()
	assert_bool(IPv4.same_subnet(IPv4.parse("1.2.3.4"), IPv4.parse("1.2.3.5"), m32)).is_false()
	assert_int(IPv4.network(IPv4.parse("192.168.10.77"), m24)).is_equal(IPv4.parse("192.168.10.0"))
