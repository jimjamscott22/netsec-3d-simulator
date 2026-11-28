class_name TestNetworkSimPatch
extends GdUnitTestSuite
## NetworkSim server source files and patch regions: add_source_file, add_vuln,
## read_file, patch_views, write_patch, patch_rev and `patch_applied` (task 3.1).

const LOGIN: String = "/var/www/login.php"
const SEARCH: String = "/var/www/search.php"
const LOGIN_TEXT: String = "<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\n  $q = \"SELECT * FROM users WHERE name = '\" . $user . \"'\";\n  $res = $db->query($q);\n  return $res->fetch();\n}\n"
const SEARCH_TEXT: String = "<?php\n$q = $_GET['q'];\necho \"Results for \" . $q;\n"
const FIX: String = "  $res = $db->prepare(\"SELECT * FROM users WHERE name = ?\");\n  $res->execute([$user]);"


func _vuln(id: String, file: String, first: int, last: int) -> Vuln:
	var v := Vuln.new(id, file, first, last)
	v.hint = "hint for " + id
	v.accept.assign(["secret-accept"])
	v.accept_fixtures.assign(["secret-fixture"])
	v.exploit = {"param": "user", "payload": "' OR '1'='1"}
	return v


func _sim() -> NetworkSim:
	var sim := NetworkSim.new()
	var web := Server.new("WEB1")
	web.services = [{"id": "http", "port": 80, "root": "/var/www"}]
	sim.add_device(web)
	sim.add_device(Host.new("PC-1"))
	assert_bool(sim.add_source_file("WEB1", LOGIN, LOGIN_TEXT)).is_true()
	assert_bool(sim.add_source_file("WEB1", SEARCH, SEARCH_TEXT)).is_true()
	assert_bool(sim.add_vuln("WEB1", _vuln("sqli_login", LOGIN, 4, 5))).is_true()
	assert_bool(sim.add_vuln("WEB1", _vuln("xss_search", SEARCH, 3, 3))).is_true()
	return sim


func test_read_file_returns_the_whole_text() -> void:
	var sim: NetworkSim = _sim()
	assert_str(sim.read_file("WEB1", LOGIN)).is_equal(LOGIN_TEXT)
	assert_str(sim.read_file("WEB1", SEARCH)).is_equal(SEARCH_TEXT)
	assert_array(sim.source_paths("WEB1")).is_equal([LOGIN, SEARCH])


func test_read_file_is_null_for_an_unknown_device_or_file() -> void:
	var sim: NetworkSim = _sim()
	assert_object(sim.read_file("WEB1", "/var/www/nope.php")).is_null()
	assert_object(sim.read_file("NOPE", LOGIN)).is_null()
	assert_object(sim.read_file("PC-1", LOGIN)).is_null()
	assert_object(NetworkSim.new().read_file("WEB1", LOGIN)).is_null()
	assert_array(sim.source_paths("PC-1")).is_empty()


func test_patch_views_give_the_vuln_range_and_hint_only() -> void:
	var views: Array[PatchView] = _sim().patch_views("WEB1", LOGIN)
	assert_int(views.size()).is_equal(1)
	assert_str(views[0].vuln_id()).is_equal("sqli_login")
	assert_int(views[0].first_line()).is_equal(4)
	assert_int(views[0].last_line()).is_equal(5)
	assert_str(views[0].hint()).is_equal("hint for sqli_login")
	# The view's class carries nothing else: no accept patterns, fixtures or exploit.
	var props: Array = views[0].get_property_list().map(func(p: Dictionary) -> String: return p["name"])
	for hidden: String in ["accept", "_accept", "accept_fixtures", "reject_fixtures", "exploit", "_exploit"]:
		assert_bool(props.has(hidden)).is_false()


func test_patch_views_are_empty_for_unknown_files_and_files_without_a_region() -> void:
	var sim: NetworkSim = _sim()
	sim.add_source_file("WEB1", "/var/www/index.php", "<?php echo 'hi';\n")
	assert_array(sim.patch_views("WEB1", "/var/www/index.php")).is_empty()
	assert_array(sim.patch_views("WEB1", "/var/www/nope.php")).is_empty()
	assert_array(sim.patch_views("NOPE", LOGIN)).is_empty()


func test_a_patch_replaces_only_the_region() -> void:
	var sim: NetworkSim = _sim()
	assert_bool(sim.write_patch("WEB1", "sqli_login", FIX)).is_true()
	assert_str(sim.read_file("WEB1", LOGIN)).is_equal(
		"<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\n" + FIX + "\n  return $res->fetch();\n}\n"
	)
	# The other file and its region are untouched.
	assert_str(sim.read_file("WEB1", SEARCH)).is_equal(SEARCH_TEXT)
	assert_int(sim.patch_rev("WEB1", "xss_search")).is_equal(0)


func test_a_patch_that_changes_the_line_count_keeps_prefix_and_suffix() -> void:
	var sim: NetworkSim = _sim()
	sim.write_patch("WEB1", "sqli_login", "  // safer\n" + FIX + "\n  // done")
	var lines: PackedStringArray = (sim.read_file("WEB1", LOGIN) as String).split("\n")
	assert_str(lines[2]).is_equal("  $user = $_POST['user'];")
	assert_str(lines[3]).is_equal("  // safer")
	assert_str(lines[6]).is_equal("  // done")
	assert_str(lines[7]).is_equal("  return $res->fetch();")
	assert_str(lines[8]).is_equal("}")
	var view: PatchView = sim.patch_views("WEB1", LOGIN)[0]
	assert_int(view.first_line()).is_equal(4)
	assert_int(view.last_line()).is_equal(7)
	# Shrinking it to one line moves the range back.
	sim.write_patch("WEB1", "sqli_login", "  x();")
	assert_int(sim.patch_views("WEB1", LOGIN)[0].last_line()).is_equal(4)
	assert_str((sim.read_file("WEB1", LOGIN) as String).split("\n")[4]).is_equal("  return $res->fetch();")


func test_patch_rev_counts_every_save() -> void:
	var sim: NetworkSim = _sim()
	assert_int(sim.patch_rev("WEB1", "sqli_login")).is_equal(0)
	sim.write_patch("WEB1", "sqli_login", FIX)
	assert_int(sim.patch_rev("WEB1", "sqli_login")).is_equal(1)
	# Saving the same text again still counts as a save.
	sim.write_patch("WEB1", "sqli_login", FIX)
	assert_int(sim.patch_rev("WEB1", "sqli_login")).is_equal(2)
	assert_int(sim.patch_rev("WEB1", "nope")).is_equal(-1)
	assert_int(sim.patch_rev("NOPE", "sqli_login")).is_equal(-1)


func test_an_unknown_vuln_or_device_is_refused_and_changes_nothing() -> void:
	var sim: NetworkSim = _sim()
	var monitor: Array[String] = []
	sim.events.patch_applied.connect(func(d: String, v: String) -> void: monitor.append(d + ":" + v))
	assert_bool(sim.write_patch("WEB1", "nope", FIX)).is_false()
	assert_bool(sim.write_patch("NOPE", "sqli_login", FIX)).is_false()
	assert_bool(sim.write_patch("PC-1", "sqli_login", FIX)).is_false()
	assert_str(sim.read_file("WEB1", LOGIN)).is_equal(LOGIN_TEXT)
	assert_int(sim.patch_rev("WEB1", "sqli_login")).is_equal(0)
	assert_array(monitor).is_empty()


func test_a_save_emits_patch_applied_once() -> void:
	var sim: NetworkSim = _sim()
	var monitor: Array[String] = []
	sim.events.patch_applied.connect(func(d: String, v: String) -> void: monitor.append(d + ":" + v))
	sim.write_patch("WEB1", "xss_search", "echo htmlspecialchars($q);")
	sim.write_patch("WEB1", "sqli_login", FIX)
	assert_array(monitor).is_equal(["WEB1:xss_search", "WEB1:sqli_login"])


func test_add_source_file_refuses_non_servers_and_taken_paths() -> void:
	var sim: NetworkSim = _sim()
	assert_bool(sim.add_source_file("PC-1", "/a.php", "x")).is_false()
	assert_bool(sim.add_source_file("NOPE", "/a.php", "x")).is_false()
	assert_bool(sim.add_source_file("WEB1", LOGIN, "x")).is_false()
	assert_str(sim.read_file("WEB1", LOGIN)).is_equal(LOGIN_TEXT)
	# Log files and source files share one set of paths.
	assert_bool(sim.add_log_file(LogFile.from_entries("WEB1", LOGIN, []))).is_false()
	assert_bool(sim.add_log_file(LogFile.from_entries("WEB1", "/var/log/auth.log", []))).is_true()
	assert_bool(sim.add_source_file("WEB1", "/var/log/auth.log", "x")).is_false()


func test_add_vuln_refusals() -> void:
	var sim: NetworkSim = _sim()
	sim.add_source_file("WEB1", "/var/www/index.php", "a\nb\n")
	# Duplicate id, a file that already has a region, a missing file, a range
	# outside the file, a non-server.
	assert_bool(sim.add_vuln("WEB1", _vuln("sqli_login", "/var/www/index.php", 1, 1))).is_false()
	assert_bool(sim.add_vuln("WEB1", _vuln("other", LOGIN, 1, 1))).is_false()
	assert_bool(sim.add_vuln("WEB1", _vuln("other", "/var/www/nope.php", 1, 1))).is_false()
	assert_bool(sim.add_vuln("WEB1", _vuln("other", "/var/www/index.php", 2, 3))).is_false()
	assert_bool(sim.add_vuln("PC-1", _vuln("other", "/var/www/index.php", 1, 1))).is_false()
	assert_array(sim.patch_views("WEB1", "/var/www/index.php")).is_empty()
	assert_bool(sim.add_vuln("WEB1", _vuln("other", "/var/www/index.php", 1, 2))).is_true()


func test_a_save_re_checks_the_objectives() -> void:
	# No objective type reads patches yet (3.5 adds them), so a save must at
	# least run the evaluator without disturbing a loaded scenario.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenarios/m2_log_triage.json"))
	var sim := NetworkSim.new()
	assert_bool(sim.load_scenario(data).ok).is_true()
	var server_id: String = ""
	for id: String in sim.device_ids():
		if sim.get_device(id) is Server:
			server_id = id
	sim.add_source_file(server_id, "/var/www/a.php", "a\n")
	sim.add_vuln(server_id, _vuln("v", "/var/www/a.php", 1, 1))
	var updates: Array[String] = []
	sim.events.objective_updated.connect(func(id: String, _p: bool) -> void: updates.append(id))
	assert_bool(sim.write_patch(server_id, "v", "b")).is_true()
	assert_array(updates).is_empty()
	assert_int(sim.objective_states().size()).is_greater(0)
