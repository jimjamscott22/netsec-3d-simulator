class_name TestPingResult
extends GdUnitTestSuite


func test_enum_order() -> void:
	assert_array(PingResult.FailReason.keys()).is_equal([
		"NONE", "NO_IP", "NO_LINK", "ADMIN_DOWN", "VLAN_MISMATCH",
		"WRONG_SUBNET", "NO_GATEWAY", "NO_ROUTE", "HOST_UNREACHABLE", "ACL_DENIED",
	])


func test_ok() -> void:
	var hops: Array[String] = ["PC-A", "PC-B"]
	var r: PingResult = PingResult.ok(hops)
	assert_bool(r.success).is_true()
	assert_int(r.fail_reason).is_equal(PingResult.FailReason.NONE)
	assert_str(r.fail_at).is_equal("")
	assert_array(r.hops).is_equal(["PC-A", "PC-B"])


func test_fail() -> void:
	var hops: Array[String] = ["PC-A", "R1"]
	var r: PingResult = PingResult.fail(PingResult.FailReason.NO_ROUTE, "R1", hops)
	assert_bool(r.success).is_false()
	assert_int(r.fail_reason).is_equal(PingResult.FailReason.NO_ROUTE)
	assert_str(r.fail_at).is_equal("R1")
	assert_array(r.hops).is_equal(["PC-A", "R1"])


func test_fail_defaults_to_no_hops() -> void:
	assert_array(PingResult.fail(PingResult.FailReason.NO_IP, "").hops).is_empty()


func test_reason_name() -> void:
	assert_str(PingResult.reason_name(PingResult.FailReason.ACL_DENIED)).is_equal("ACL_DENIED")
	assert_str(PingResult.reason_name(PingResult.FailReason.NONE)).is_equal("NONE")
