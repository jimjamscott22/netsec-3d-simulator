class_name TestServerFiles
extends GdUnitTestSuite
## ServerFiles (task 2.5): one path tree per device, built from its log paths.

var _sim: NetworkSim


func before_test() -> void:
	_sim = NetworkSim.new()
	_sim.add_device(Server.new("WEB1"))
	_sim.add_device(Server.new("EMPTY"))
	for path in ["/var/log/nginx/access.log", "/var/log/auth.log", "/etc/motd"]:
		_sim.add_log_file(LogFile.from_entries("WEB1", path, [{"text": "a"}, {"text": "b"}]))


func test_normalize() -> void:
	assert_str(ServerFiles.normalize("")).is_equal("/")
	assert_str(ServerFiles.normalize("/")).is_equal("/")
	assert_str(ServerFiles.normalize("var/log")).is_equal("/var/log")
	assert_str(ServerFiles.normalize("//var//log//")).is_equal("/var/log")


func test_paths_come_in_declaration_order() -> void:
	assert_array(ServerFiles.paths(_sim, "WEB1")).is_equal(["/var/log/nginx/access.log", "/var/log/auth.log", "/etc/motd"])
	assert_array(ServerFiles.paths(_sim, "EMPTY")).is_empty()
	assert_array(ServerFiles.paths(_sim, "NOPE")).is_empty()


func test_files_and_directories_are_told_apart() -> void:
	assert_bool(ServerFiles.is_file(_sim, "WEB1", "/etc/motd")).is_true()
	assert_bool(ServerFiles.is_file(_sim, "WEB1", "etc//motd")).is_true()
	assert_bool(ServerFiles.is_file(_sim, "WEB1", "/etc")).is_false()
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/etc")).is_true()
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/var/log/nginx/")).is_true()
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/etc/motd")).is_false()
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/nope")).is_false()


func test_a_name_that_only_starts_like_a_directory_is_not_one() -> void:
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/var/lo")).is_false()
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/va")).is_false()


func test_the_root_always_exists() -> void:
	assert_bool(ServerFiles.is_dir(_sim, "WEB1", "/")).is_true()
	assert_bool(ServerFiles.is_dir(_sim, "EMPTY", "/")).is_true()
	assert_bool(ServerFiles.is_file(_sim, "WEB1", "/")).is_false()


func test_children_are_sorted_with_directories_marked() -> void:
	assert_array(ServerFiles.children(_sim, "WEB1", "/")).is_equal(["etc/", "var/"])
	assert_array(ServerFiles.children(_sim, "WEB1", "/var/log")).is_equal(["auth.log", "nginx/"])
	assert_array(ServerFiles.children(_sim, "WEB1", "var/log/nginx")).is_equal(["access.log"])
	assert_array(ServerFiles.children(_sim, "WEB1", "/etc")).is_equal(["motd"])


func test_children_of_a_file_a_missing_path_or_an_empty_device_are_empty() -> void:
	assert_array(ServerFiles.children(_sim, "WEB1", "/etc/motd")).is_empty()
	assert_array(ServerFiles.children(_sim, "WEB1", "/nope")).is_empty()
	assert_array(ServerFiles.children(_sim, "EMPTY", "/")).is_empty()


func test_lines_of_a_file_in_order_and_nothing_for_other_paths() -> void:
	var lines: Array[LogLine] = ServerFiles.lines(_sim, "WEB1", "etc/motd")
	assert_array(lines.map(func(l: LogLine) -> String: return l.text())).is_equal(["a", "b"])
	assert_array(ServerFiles.lines(_sim, "WEB1", "/etc")).is_empty()
	assert_array(ServerFiles.lines(_sim, "WEB1", "/nope")).is_empty()
