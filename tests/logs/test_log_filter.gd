class_name TestLogFilter
extends GdUnitTestSuite
## LogFilter (task 2.1): substring, case-insensitive, regex and src_ip filters.
## A filter tests a line's `full_text()`, the text the player sees.


func _lines() -> Array[LogLine]:
	return LogFile.from_entries("WEB1", "/f", [
		{"t": "2026-03-14T02:11:05Z", "text": "sshd[811]: Failed password for root from 203.0.113.45", "src_ip": "203.0.113.45"},
		{"t": "2026-03-14T02:11:06Z", "text": "sshd[811]: failed password for admin from 203.0.113.45", "src_ip": "203.0.113.45"},
		{"t": "2026-03-14T02:12:00Z", "text": "sshd[900]: Accepted password for deploy from 198.51.100.7", "src_ip": "198.51.100.7"},
		{"text": "cron[12]: session opened for root"},
	]).lines()


func _numbers(filter: LogFilter) -> Array:
	var out: Array = []
	for l in _lines():
		if filter.matches(l):
			out.append(l.number())
	return out


func test_all_matches_every_line() -> void:
	assert_array(_numbers(LogFilter.all())).is_equal([1, 2, 3, 4])


func test_substring_is_case_sensitive() -> void:
	assert_array(_numbers(LogFilter.contains("Failed"))).is_equal([1])
	assert_array(_numbers(LogFilter.contains("failed"))).is_equal([2])


func test_substring_ignoring_case() -> void:
	assert_array(_numbers(LogFilter.contains_ignore_case("FAILED"))).is_equal([1, 2])


func test_substring_has_no_regex_meaning() -> void:
	assert_array(_numbers(LogFilter.contains("sshd[811]"))).is_equal([1, 2])
	assert_array(_numbers(LogFilter.contains("."))).is_equal([1, 2, 3])


func test_substring_can_match_the_timestamp() -> void:
	assert_array(_numbers(LogFilter.contains("02:12:00"))).is_equal([3])


func test_empty_substring_matches_every_line() -> void:
	assert_array(_numbers(LogFilter.contains(""))).is_equal([1, 2, 3, 4])
	assert_array(_numbers(LogFilter.contains_ignore_case(""))).is_equal([1, 2, 3, 4])


func test_regex_matches_anywhere_in_the_line() -> void:
	assert_array(_numbers(LogFilter.regex("for (root|admin) from"))).is_equal([1, 2])
	assert_array(_numbers(LogFilter.regex("^sshd"))).is_equal([])
	assert_array(_numbers(LogFilter.regex("^2026-03-14T02:12"))).is_equal([3])


func test_regex_is_case_sensitive_unless_it_says_otherwise() -> void:
	assert_array(_numbers(LogFilter.regex("failed"))).is_equal([2])
	assert_array(_numbers(LogFilter.regex("(?i)failed"))).is_equal([1, 2])


func test_invalid_regex_is_flagged_and_matches_nothing() -> void:
	var f: LogFilter = LogFilter.regex("(unclosed")
	assert_bool(f.is_valid()).is_false()
	assert_array(_numbers(f)).is_empty()


func test_valid_filters_report_valid() -> void:
	assert_bool(LogFilter.all().is_valid()).is_true()
	assert_bool(LogFilter.contains("x").is_valid()).is_true()
	assert_bool(LogFilter.regex("x+").is_valid()).is_true()
	assert_bool(LogFilter.src_ip("203.0.113.45").is_valid()).is_true()


func test_src_ip_is_an_exact_match_on_the_field() -> void:
	assert_array(_numbers(LogFilter.src_ip("203.0.113.45"))).is_equal([1, 2])
	assert_array(_numbers(LogFilter.src_ip("198.51.100.7"))).is_equal([3])
	# A prefix of an address is a different address, not a partial hit.
	assert_array(_numbers(LogFilter.src_ip("203.0.113.4"))).is_empty()
	# The address in the text but not in the field does not count.
	assert_array(_numbers(LogFilter.src_ip("203.0.113.45"))).not_contains([4])


func test_empty_src_ip_is_invalid_and_matches_nothing() -> void:
	var f: LogFilter = LogFilter.src_ip("")
	assert_bool(f.is_valid()).is_false()
	assert_array(_numbers(f)).is_empty()
