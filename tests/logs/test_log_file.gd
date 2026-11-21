class_name TestLogFile
extends GdUnitTestSuite
## LogLine and LogFile (task 2.1): immutable lines numbered from 1 in file order.


func _entries() -> Array:
	return [
		{"t": "2026-03-14T02:11:05Z", "text": "sshd[811]: Failed password for root from 203.0.113.45 port 51122 ssh2", "src_ip": "203.0.113.45", "geo": "NL"},
		{"text": "cron[12]: session opened"},
		{"t": "2026-03-14T02:11:09Z", "text": "sshd[811]: Accepted password for deploy from 203.0.113.45 port 51130 ssh2", "src_ip": "203.0.113.45"},
	]


func test_lines_are_numbered_from_one_in_file_order() -> void:
	var f: LogFile = LogFile.from_entries("WEB1", "/var/log/auth.log", _entries())
	assert_str(f.source()).is_equal("WEB1")
	assert_str(f.file()).is_equal("/var/log/auth.log")
	assert_int(f.line_count()).is_equal(3)
	var lines: Array[LogLine] = f.lines()
	assert_array(lines.map(func(l: LogLine) -> int: return l.number())).is_equal([1, 2, 3])
	assert_str(lines[1].text()).is_equal("cron[12]: session opened")


func test_optional_fields_default_to_empty() -> void:
	var line: LogLine = LogFile.from_entries("WEB1", "/f", _entries()).lines()[1]
	assert_str(line.t()).is_empty()
	assert_str(line.src_ip()).is_empty()
	assert_str(line.geo()).is_empty()


func test_present_fields_are_kept() -> void:
	var line: LogLine = LogFile.from_entries("WEB1", "/f", _entries()).lines()[0]
	assert_str(line.t()).is_equal("2026-03-14T02:11:05Z")
	assert_str(line.src_ip()).is_equal("203.0.113.45")
	assert_str(line.geo()).is_equal("NL")


func test_full_text_is_what_the_player_sees() -> void:
	var lines: Array[LogLine] = LogFile.from_entries("WEB1", "/f", _entries()).lines()
	assert_str(lines[0].full_text()).starts_with("2026-03-14T02:11:05Z sshd[811]: Failed")
	# No timestamp: no stray leading space.
	assert_str(lines[1].full_text()).is_equal("cron[12]: session opened")


func test_line_lookup_is_one_based_and_bounded() -> void:
	var f: LogFile = LogFile.from_entries("WEB1", "/f", _entries())
	assert_int(f.line(1).number()).is_equal(1)
	assert_int(f.line(3).number()).is_equal(3)
	assert_object(f.line(0)).is_null()
	assert_object(f.line(4)).is_null()
	assert_object(f.line(-1)).is_null()


func test_lines_returns_a_fresh_array() -> void:
	var f: LogFile = LogFile.from_entries("WEB1", "/f", _entries())
	var first: Array[LogLine] = f.lines()
	first.clear()
	assert_int(f.lines().size()).is_equal(3)
	assert_int(f.line_count()).is_equal(3)


func test_empty_file_is_allowed() -> void:
	var f: LogFile = LogFile.from_entries("WEB1", "/f", [])
	assert_int(f.line_count()).is_equal(0)
	assert_array(f.lines()).is_empty()
