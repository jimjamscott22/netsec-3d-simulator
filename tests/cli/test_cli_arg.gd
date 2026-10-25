class_name TestCliArg
extends GdUnitTestSuite


func _w(text: String) -> PackedStringArray:
	return text.split(" ", false)


func test_arity() -> void:
	assert_int(CliArg.arity(CliArg.Type.INTERFACE)).is_equal(1)
	assert_int(CliArg.arity(CliArg.Type.IPV4)).is_equal(1)
	assert_int(CliArg.arity(CliArg.Type.MASK)).is_equal(1)
	assert_int(CliArg.arity(CliArg.Type.VLAN_ID)).is_equal(1)
	assert_int(CliArg.arity(CliArg.Type.WORD)).is_equal(1)
	assert_int(CliArg.arity(CliArg.Type.LINE_RANGE)).is_equal(2)


func test_interface_normalizes_aliases() -> void:
	var r: CliArgResult = CliArg.parse(CliArg.Type.INTERFACE, _w("g0/1"))
	assert_bool(r.ok).is_true()
	assert_str(r.value).is_equal("GigabitEthernet0/1")
	r = CliArg.parse(CliArg.Type.INTERFACE, _w("Fa0/24"))
	assert_str(r.value).is_equal("FastEthernet0/24")
	r = CliArg.parse(CliArg.Type.INTERFACE, _w("g0/0.10"))
	assert_str(r.value).is_equal("GigabitEthernet0/0.10")


func test_interface_rejects_garbage() -> void:
	for bad: String in ["bogus", "g", "0/1", "g0/1.0", "lo0"]:
		assert_bool(CliArg.parse(CliArg.Type.INTERFACE, _w(bad)).ok).is_false()


func test_ipv4() -> void:
	var r: CliArgResult = CliArg.parse(CliArg.Type.IPV4, _w("10.0.10.5"))
	assert_bool(r.ok).is_true()
	assert_int(r.value).is_equal(IPv4.parse("10.0.10.5"))
	for bad: String in ["10.0.10", "10.0.10.256", "a.b.c.d", "10.0.10.5.1", "01.0.0.1"]:
		assert_bool(CliArg.parse(CliArg.Type.IPV4, _w(bad)).ok).is_false()


func test_mask_accepts_contiguous_only() -> void:
	var r: CliArgResult = CliArg.parse(CliArg.Type.MASK, _w("255.255.255.0"))
	assert_bool(r.ok).is_true()
	assert_int(r.value).is_equal(IPv4.parse("255.255.255.0"))
	assert_bool(CliArg.parse(CliArg.Type.MASK, _w("0.0.0.0")).ok).is_true()
	assert_bool(CliArg.parse(CliArg.Type.MASK, _w("255.0.255.0")).ok).is_false()
	assert_bool(CliArg.parse(CliArg.Type.MASK, _w("/24")).ok).is_false()


func test_vlan_id_range() -> void:
	var r: CliArgResult = CliArg.parse(CliArg.Type.VLAN_ID, _w("10"))
	assert_bool(r.ok).is_true()
	assert_int(r.value).is_equal(10)
	assert_int(CliArg.parse(CliArg.Type.VLAN_ID, _w("1")).value).is_equal(1)
	assert_int(CliArg.parse(CliArg.Type.VLAN_ID, _w("4094")).value).is_equal(4094)
	for bad: String in ["0", "4095", "-5", "+5", "ten", "1.5", "007"]:
		assert_bool(CliArg.parse(CliArg.Type.VLAN_ID, _w(bad)).ok).is_false()


func test_word_keeps_case() -> void:
	var r: CliArgResult = CliArg.parse(CliArg.Type.WORD, _w("Core-SW1"))
	assert_bool(r.ok).is_true()
	assert_str(r.value).is_equal("Core-SW1")
	assert_bool(CliArg.parse(CliArg.Type.WORD, PackedStringArray([""])).ok).is_false()


func test_line_range_takes_first_and_last() -> void:
	var r: CliArgResult = CliArg.parse(CliArg.Type.LINE_RANGE, _w("0 4"))
	assert_bool(r.ok).is_true()
	assert_object(r.value).is_equal(Vector2i(0, 4))
	r = CliArg.parse(CliArg.Type.LINE_RANGE, _w("3 3"))
	assert_object(r.value).is_equal(Vector2i(3, 3))


func test_line_range_rejects_bad_input() -> void:
	for bad: String in ["4 0", "0 16", "-1 4", "a 4", "0 b"]:
		assert_bool(CliArg.parse(CliArg.Type.LINE_RANGE, _w(bad)).ok).is_false()


func test_wrong_word_count_is_not_ok() -> void:
	assert_bool(CliArg.parse(CliArg.Type.LINE_RANGE, _w("0")).ok).is_false()
	assert_bool(CliArg.parse(CliArg.Type.IPV4, _w("1.1.1.1 2.2.2.2")).ok).is_false()
	assert_bool(CliArg.parse(CliArg.Type.IPV4, PackedStringArray()).ok).is_false()


func test_placeholders_for_help() -> void:
	assert_str(CliArg.placeholder(CliArg.Type.INTERFACE)).is_equal("<interface>")
	assert_str(CliArg.placeholder(CliArg.Type.IPV4)).is_equal("A.B.C.D")
	assert_str(CliArg.placeholder(CliArg.Type.MASK)).is_equal("A.B.C.D")
	assert_str(CliArg.placeholder(CliArg.Type.VLAN_ID)).is_equal("<1-4094>")
	assert_str(CliArg.placeholder(CliArg.Type.WORD)).is_equal("WORD")
	assert_str(CliArg.placeholder(CliArg.Type.LINE_RANGE)).is_equal("<0-15> <0-15>")
