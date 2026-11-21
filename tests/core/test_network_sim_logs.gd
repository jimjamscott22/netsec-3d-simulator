class_name TestNetworkSimLogs
extends GdUnitTestSuite
## NetworkSim.add_log_file and query_logs (task 2.1).

const FILE: String = "/var/log/auth.log"


func _sim() -> NetworkSim:
	var sim := NetworkSim.new()
	sim.add_device(Server.new("WEB1"))
	return sim


func _auth() -> LogFile:
	return LogFile.from_entries("WEB1", FILE, [
		{"text": "sshd: Failed password for root from 203.0.113.45", "src_ip": "203.0.113.45"},
		{"text": "sshd: Accepted password for deploy from 198.51.100.7", "src_ip": "198.51.100.7"},
		{"text": "sshd: Failed password for admin from 203.0.113.45", "src_ip": "203.0.113.45"},
	])


func _numbers(lines: Array[LogLine]) -> Array:
	return lines.map(func(l: LogLine) -> int: return l.number())


func test_query_without_a_filter_returns_the_file_in_order() -> void:
	var sim: NetworkSim = _sim()
	assert_bool(sim.add_log_file(_auth())).is_true()
	assert_array(_numbers(sim.query_logs("WEB1", FILE, null))).is_equal([1, 2, 3])
	assert_array(_numbers(sim.query_logs("WEB1", FILE, LogFilter.all()))).is_equal([1, 2, 3])


func test_filtered_query_keeps_file_order_and_original_line_numbers() -> void:
	var sim: NetworkSim = _sim()
	sim.add_log_file(_auth())
	var hits: Array[LogLine] = sim.query_logs("WEB1", FILE, LogFilter.contains("Failed"))
	assert_array(_numbers(hits)).is_equal([1, 3])
	assert_array(_numbers(sim.query_logs("WEB1", FILE, LogFilter.src_ip("198.51.100.7")))).is_equal([2])


func test_invalid_filter_returns_nothing() -> void:
	var sim: NetworkSim = _sim()
	sim.add_log_file(_auth())
	assert_array(sim.query_logs("WEB1", FILE, LogFilter.regex("(oops"))).is_empty()


func test_unknown_source_or_file_returns_nothing() -> void:
	var sim: NetworkSim = _sim()
	sim.add_log_file(_auth())
	assert_array(sim.query_logs("NOPE", FILE, null)).is_empty()
	assert_array(sim.query_logs("WEB1", "/var/log/other.log", null)).is_empty()
	assert_array(NetworkSim.new().query_logs("WEB1", FILE, null)).is_empty()


func test_add_log_file_refuses_an_unknown_device() -> void:
	var sim: NetworkSim = NetworkSim.new()
	assert_bool(sim.add_log_file(_auth())).is_false()
	assert_array(sim.query_logs("WEB1", FILE, null)).is_empty()


func test_add_log_file_refuses_a_duplicate_source_and_file() -> void:
	var sim: NetworkSim = _sim()
	assert_bool(sim.add_log_file(_auth())).is_true()
	assert_bool(sim.add_log_file(LogFile.from_entries("WEB1", FILE, [{"text": "other"}]))).is_false()
	# The first file is untouched.
	assert_int(sim.query_logs("WEB1", FILE, null).size()).is_equal(3)


func test_same_path_on_different_devices_is_two_files() -> void:
	var sim: NetworkSim = _sim()
	sim.add_device(Server.new("DB1"))
	assert_bool(sim.add_log_file(_auth())).is_true()
	assert_bool(sim.add_log_file(LogFile.from_entries("DB1", FILE, [{"text": "db line"}]))).is_true()
	assert_int(sim.query_logs("WEB1", FILE, null).size()).is_equal(3)
	assert_str(sim.query_logs("DB1", FILE, null)[0].text()).is_equal("db line")


func test_each_query_returns_a_fresh_array() -> void:
	var sim: NetworkSim = _sim()
	sim.add_log_file(_auth())
	sim.query_logs("WEB1", FILE, null).clear()
	assert_int(sim.query_logs("WEB1", FILE, null).size()).is_equal(3)


func test_loading_a_scenario_drops_logs_from_before() -> void:
	var sim: NetworkSim = _sim()
	sim.add_log_file(_auth())
	var data: Dictionary = ScenarioRunner.read("res://scenarios/m1_vlan_ping.json")
	assert_array(sim.load_scenario(data).errors).is_empty()
	assert_array(sim.query_logs("WEB1", FILE, null)).is_empty()


func test_querying_changes_no_state_and_emits_nothing() -> void:
	var sim: NetworkSim = _sim()
	sim.add_log_file(_auth())
	var seen: Array[String] = []
	sim.events.config_changed.connect(func(id: String) -> void: seen.append(id))
	sim.query_logs("WEB1", FILE, LogFilter.contains("Failed"))
	assert_array(seen).is_empty()
