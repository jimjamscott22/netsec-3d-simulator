class_name TestVuln
extends GdUnitTestSuite
## Vuln.from_entry (task 3.1).


func test_from_entry_reads_every_field() -> void:
	var v: Vuln = Vuln.from_entry({
		"id": "sqli_login", "kind": "sqli", "service": "http", "route": "/login.php",
		"region": {"file": "/var/www/login.php", "first_line": 4.0, "last_line": 5.0},
		"accept": ["a"], "accept_fixtures": ["b", "c"], "reject_fixtures": [""],
		"hint": "Use a prepared statement.",
		"exploit": {"param": "user", "payload": "' OR '1'='1"},
	})
	assert_str(v.id).is_equal("sqli_login")
	assert_str(v.kind).is_equal("sqli")
	assert_str(v.service).is_equal("http")
	assert_str(v.route).is_equal("/login.php")
	assert_str(v.file).is_equal("/var/www/login.php")
	assert_int(v.first_line).is_equal(4)
	assert_int(v.last_line).is_equal(5)
	assert_array(v.accept).is_equal(["a"])
	assert_array(v.accept_fixtures).is_equal(["b", "c"])
	assert_array(v.reject_fixtures).is_equal([""])
	assert_str(v.hint).is_equal("Use a prepared statement.")
	assert_dict(v.exploit).is_equal({"param": "user", "payload": "' OR '1'='1"})
	assert_int(v.patch_rev).is_equal(0)


func test_from_entry_copies_the_exploit() -> void:
	var exploit: Dictionary = {"param": "q"}
	var v: Vuln = Vuln.from_entry({"id": "x", "exploit": exploit})
	exploit["param"] = "changed"
	assert_str(v.exploit["param"]).is_equal("q")


func test_missing_optional_keys_stay_empty() -> void:
	var v: Vuln = Vuln.from_entry({"id": "x"})
	assert_str(v.file).is_empty()
	assert_array(v.accept).is_empty()
	assert_str(v.hint).is_empty()
	assert_dict(v.exploit).is_empty()
