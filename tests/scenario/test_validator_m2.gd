class_name TestValidatorM2
extends GdUnitTestSuite
## Validator rules for `logs`, `report` and `report` objectives (tasks 2.2 and
## 2.3, SPEC §7.4). Each test edits the known-good M2 fixture in one way and
## asserts the exact error list, so it also proves a mistake is reported once, at
## its JSON path.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const FILE_ID: String = "m2_fixture"

# Indices into the fixture's arrays.
const WEB_AUTH: int = 0  # 5 lines
const WEB_ACCESS: int = 1  # 3 lines
const DB_AUTH: int = 2  # 2 lines

# Objectives: 0 is a config objective, then one report objective per field.
const OBJ_IP: int = 1
const OBJ_TYPE: int = 2
const OBJ_USER: int = 3

const SNAKE: String = "must be snake_case (lowercase letters, digits and underscores, starting with a letter)"
const PATH_RULE: String = "must be an absolute file path such as /var/log/auth.log (no spaces)"


# --- helpers ----------------------------------------------------------------


func _load() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_bool(parsed is Dictionary).override_failure_message("fixture did not parse").is_true()
	return parsed


func _walk(root: Variant, path: Array) -> Variant:
	var node: Variant = root
	for key: Variant in path:
		node = node[key]
	return node


func _with(path: Array, value: Variant) -> Array[String]:
	var d: Dictionary = _load()
	_walk(d, path.slice(0, -1))[path[-1]] = value
	return ScenarioValidator.validate(d, FILE_ID)


func _without(path: Array) -> Array[String]:
	var d: Dictionary = _load()
	_walk(d, path.slice(0, -1)).erase(path[-1])
	return ScenarioValidator.validate(d, FILE_ID)


func _edit(edit: Callable) -> Array[String]:
	var d: Dictionary = _load()
	edit.call(d)
	return ScenarioValidator.validate(d, FILE_ID)


## Removes the report and every objective that answers it.
func _drop_report(d: Dictionary) -> void:
	d.erase("report")
	d["objectives"] = d["objectives"].filter(func(o: Dictionary) -> bool: return o["type"] != "report")


func _log(index: int) -> String:
	return "logs[%d]" % index


func _line(log_index: int, line_index: int) -> String:
	return "logs[%d].lines[%d]" % [log_index, line_index]


func _field(index: int) -> String:
	return "report.fields[%d]" % index


func _evidence_of(index: int, ref: Dictionary) -> Array[String]:
	return _with(["report", "fields", index, "evidence"], [ref])


func _ref(source: String, file: String, line: Variant) -> Dictionary:
	return {"source": source, "file": file, "line": line}


# --- the fixture itself -----------------------------------------------------


func test_fixture_is_valid() -> void:
	assert_array(ScenarioValidator.validate(_load(), FILE_ID)).is_empty()


func test_logs_and_report_are_both_optional() -> void:
	assert_array(_without(["logs"])).is_equal([
		_field(0) + ".evidence[0]: no log \"WEB1:/var/log/auth.log\" is declared",
		_field(0) + ".evidence[1]: no log \"WEB1:/var/log/auth.log\" is declared",
	])
	assert_array(_edit(func(d: Dictionary) -> void:
		d.erase("logs")
		_drop_report(d))).is_empty()
	assert_array(_edit(_drop_report)).is_empty()


# --- logs: shape ------------------------------------------------------------


func test_logs_must_be_an_array_of_objects() -> void:
	assert_array(_edit(func(d: Dictionary) -> void:
		d["logs"] = {}
		_drop_report(d))).is_equal(["logs: must be an array"])
	assert_array(_with(["logs", 1], 5)).is_equal(["logs[1]: must be an object"])


func test_an_empty_logs_array_is_fine_without_evidence() -> void:
	assert_array(_edit(func(d: Dictionary) -> void:
		d["logs"] = []
		_drop_report(d))).is_empty()


func test_log_entry_keys() -> void:
	assert_array(_with(["logs", WEB_AUTH, "extra"], 1)).is_equal([_log(WEB_AUTH) + ".extra: unknown key"])
	for key in ["source", "file", "lines"]:
		assert_array(_without(["logs", WEB_AUTH, key])).override_failure_message(key).is_equal(
			[_log(WEB_AUTH) + "." + key + ": required"]
		)


func test_log_source_must_be_a_device() -> void:
	assert_array(_with(["logs", WEB_AUTH, "source"], "NOPE")).is_equal(
		[_log(WEB_AUTH) + '.source: unknown device "NOPE"']
	)
	assert_array(_with(["logs", WEB_AUTH, "source"], 5)).is_equal([_log(WEB_AUTH) + ".source: must be a device id"])


func test_log_file_must_be_an_absolute_path_without_spaces() -> void:
	for bad: Variant in ["", "auth.log", "/var/log/", "/var//log", "/var/my log", "/", "/var/log/auth.log\n", 5]:
		assert_array(_with(["logs", WEB_AUTH, "file"], bad)).override_failure_message(str(bad)).is_equal(
			[_log(WEB_AUTH) + ".file: " + PATH_RULE]
		)
	assert_array(_with(["logs", WEB_AUTH, "file"], "/var/log/secure")).is_equal(
		[_field(0) + ".evidence[0]: no log \"WEB1:/var/log/auth.log\" is declared",
		_field(0) + ".evidence[1]: no log \"WEB1:/var/log/auth.log\" is declared"]
	)


func test_lines_must_be_an_array() -> void:
	assert_array(_with(["logs", WEB_AUTH, "lines"], "text")).is_equal([_log(WEB_AUTH) + ".lines: must be an array"])


# --- logs: duplicate (source, file) pairs -----------------------------------


func test_a_repeated_source_and_file_is_rejected() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["logs"].append(d["logs"][WEB_AUTH].duplicate(true)))
	assert_array(errors).is_equal(['logs[3].file: duplicate log "WEB1:/var/log/auth.log" (same as logs[0])'])


func test_a_repeated_pair_is_rejected_even_when_no_evidence_uses_it() -> void:
	# WEB_ACCESS is never cited by the report's evidence.
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["logs"].append(d["logs"][WEB_ACCESS].duplicate(true)))
	assert_array(errors).is_equal(['logs[3].file: duplicate log "WEB1:/var/log/nginx/access.log" (same as logs[1])'])


func test_the_same_path_on_two_devices_is_fine() -> void:
	# The fixture already has /var/log/auth.log on WEB1 and DB1.
	assert_array(ScenarioValidator.validate(_load(), FILE_ID)).is_empty()


func test_a_duplicate_with_a_bad_source_is_reported_once() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		var copy: Dictionary = d["logs"][WEB_AUTH].duplicate(true)
		copy["source"] = "NOPE"
		d["logs"].append(copy))
	assert_array(errors).is_equal(['logs[3].source: unknown device "NOPE"'])


# --- logs: the server's file tree --------------------------------------------


func _extra_log(file: String, source: String = "WEB1") -> Callable:
	return func(d: Dictionary) -> void:
		d["logs"].append({"source": source, "file": file, "lines": [{"text": "x"}]})


func test_a_log_path_cannot_be_a_directory_of_another_log() -> void:
	# /var/log is a directory because logs[0] is /var/log/auth.log.
	assert_array(_edit(_extra_log("/var/log"))).is_equal([
		'logs[3].file: clashes with "/var/log/auth.log" (logs[0]): a path cannot be both a file and a directory'
	])


func test_a_log_path_cannot_sit_inside_another_log() -> void:
	assert_array(_edit(_extra_log("/var/log/auth.log/old"))).is_equal([
		'logs[3].file: clashes with "/var/log/auth.log" (logs[0]): a path cannot be both a file and a directory'
	])


func test_only_the_first_clash_is_reported_for_an_entry() -> void:
	assert_array(_edit(_extra_log("/var"))).is_equal([
		'logs[3].file: clashes with "/var/log/auth.log" (logs[0]): a path cannot be both a file and a directory'
	])


func test_siblings_and_lookalike_names_do_not_clash() -> void:
	assert_array(_edit(_extra_log("/var/log/auth.log.1"))).is_empty()
	assert_array(_edit(_extra_log("/var/log/nginx"))).is_equal([
		'logs[3].file: clashes with "/var/log/nginx/access.log" (logs[1]): a path cannot be both a file and a directory'
	])
	assert_array(_edit(_extra_log("/var/logs"))).is_empty()


func test_each_device_has_its_own_tree() -> void:
	# WEB1 has /var/log/nginx/access.log, so only WEB1 treats /var/log/nginx as a directory.
	assert_array(_edit(_extra_log("/var/log/nginx", "DB1"))).is_empty()


# --- logs: lines ------------------------------------------------------------


func test_a_log_may_have_no_lines() -> void:
	assert_array(_edit(func(d: Dictionary) -> void:
		d["logs"][DB_AUTH]["lines"] = [])).is_empty()


func test_a_line_must_be_an_object_with_known_keys() -> void:
	assert_array(_with(["logs", WEB_AUTH, "lines", 0], "text")).is_equal([_line(WEB_AUTH, 0) + ": must be an object"])
	assert_array(_with(["logs", WEB_AUTH, "lines", 0, "level"], "warn")).is_equal([_line(WEB_AUTH, 0) + ".level: unknown key"])


func test_a_line_needs_text() -> void:
	assert_array(_without(["logs", WEB_AUTH, "lines", 1, "text"])).is_equal([_line(WEB_AUTH, 1) + ".text: required"])
	for bad: Variant in ["", 5]:
		assert_array(_with(["logs", WEB_AUTH, "lines", 1, "text"], bad)).override_failure_message(str(bad)).is_equal(
			[_line(WEB_AUTH, 1) + ".text: must be a non-empty string"]
		)


func test_text_and_timestamp_are_one_line() -> void:
	assert_array(_with(["logs", WEB_AUTH, "lines", 1, "text"], "two\nlines")).is_equal(
		[_line(WEB_AUTH, 1) + ".text: must be one line (no line breaks)"]
	)
	assert_array(_with(["logs", WEB_AUTH, "lines", 1, "text"], "two\rlines")).is_equal(
		[_line(WEB_AUTH, 1) + ".text: must be one line (no line breaks)"]
	)
	assert_array(_with(["logs", WEB_AUTH, "lines", 1, "t"], "02:11\n05")).is_equal(
		[_line(WEB_AUTH, 1) + ".t: must be one line (no line breaks)"]
	)
	for bad: Variant in ["", 5]:
		assert_array(_with(["logs", WEB_AUTH, "lines", 1, "t"], bad)).override_failure_message(str(bad)).is_equal(
			[_line(WEB_AUTH, 1) + ".t: must be a non-empty string"]
		)


func test_timestamp_src_ip_and_geo_are_optional() -> void:
	assert_array(_without(["logs", WEB_AUTH, "lines", 0, "t"])).is_empty()
	assert_array(_without(["logs", WEB_AUTH, "lines", 0, "src_ip"])).is_empty()
	assert_array(_without(["logs", WEB_AUTH, "lines", 0, "geo"])).is_empty()


func test_src_ip_must_be_an_ipv4_address() -> void:
	for bad: Variant in ["", "999.1.1.1", "203.0.113", 5]:
		assert_array(_with(["logs", WEB_AUTH, "lines", 0, "src_ip"], bad)).override_failure_message(str(bad)).is_equal(
			[_line(WEB_AUTH, 0) + ".src_ip: must be an IPv4 address such as 192.168.10.1"]
		)


func test_geo_must_be_a_two_letter_country_code() -> void:
	for bad: Variant in ["", "nl", "NLD", "N1", "NL\n", 5]:
		assert_array(_with(["logs", WEB_AUTH, "lines", 0, "geo"], bad)).override_failure_message(str(bad)).is_equal(
			[_line(WEB_AUTH, 0) + ".geo: must be a two-letter country code such as NL"]
		)


func test_every_bad_line_is_reported() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["logs"][WEB_AUTH]["lines"][0]["src_ip"] = "nope"
		d["logs"][WEB_AUTH]["lines"][2]["geo"] = "x"
		d["logs"][WEB_ACCESS]["lines"][1].erase("text"))
	assert_array(errors).is_equal([
		_line(WEB_AUTH, 0) + ".src_ip: must be an IPv4 address such as 192.168.10.1",
		_line(WEB_AUTH, 2) + ".geo: must be a two-letter country code such as NL",
		_line(WEB_ACCESS, 1) + ".text: required",
	])


# --- report: shape ----------------------------------------------------------


func test_report_must_be_an_object_with_known_keys() -> void:
	assert_array(_with(["report"], [])).is_equal(["report: must be an object"])
	assert_array(_with(["report", "attempts"], 3)).is_equal(["report.attempts: unknown key"])
	assert_array(_without(["report", "fields"])).is_equal(["report.fields: required"])


func test_report_needs_at_least_one_field() -> void:
	assert_array(_with(["report", "fields"], [])).is_equal(["report.fields: needs at least one field"])
	assert_array(_with(["report", "fields"], {})).is_equal(["report.fields: must be an array"])


func test_max_attempts_is_optional_and_at_least_one() -> void:
	assert_array(_without(["report", "max_attempts"])).is_empty()
	for bad: Variant in [0, -1, 1.5, "3"]:
		assert_array(_with(["report", "max_attempts"], bad)).override_failure_message(str(bad)).is_equal(
			["report.max_attempts: must be an integer of at least 1"]
		)
	assert_array(_with(["report", "max_attempts"], 1)).is_empty()
	assert_array(_with(["report", "max_attempts"], 3.0)).is_empty()


func test_field_must_be_an_object_with_known_keys() -> void:
	assert_array(_with(["report", "fields", 0], 5)).is_equal([_field(0) + ": must be an object"])
	assert_array(_with(["report", "fields", 2, "hint"], "x")).is_equal([_field(2) + ".hint: unknown key"])


func test_field_requires_id_label_and_kind() -> void:
	for key in ["id", "label", "kind"]:
		assert_array(_without(["report", "fields", 2, key])).override_failure_message(key).is_equal(
			[_field(2) + "." + key + ": required"]
		)


func test_field_id_is_snake_case_and_unique() -> void:
	assert_array(_with(["report", "fields", 2, "id"], "Compromised User")).is_equal([_field(2) + ".id: " + SNAKE])
	assert_array(_with(["report", "fields", 2, "id"], "attacker_ip")).is_equal(
		[_field(2) + '.id: duplicate report field id "attacker_ip"']
	)


func test_field_label_is_a_non_empty_string() -> void:
	for bad: Variant in ["", 5]:
		assert_array(_with(["report", "fields", 2, "label"], bad)).override_failure_message(str(bad)).is_equal(
			[_field(2) + ".label: must be a non-empty string"]
		)


func test_field_kind_is_one_of_three() -> void:
	for bad: Variant in ["number", "IPV4", 5]:
		assert_array(_with(["report", "fields", 2, "kind"], bad)).override_failure_message(str(bad)).is_equal(
			[_field(2) + ".kind: must be one of ipv4, choice, text"]
		)


# --- report: choice options -------------------------------------------------


func test_a_choice_field_needs_options() -> void:
	assert_array(_without(["report", "fields", 1, "options"])).is_equal([_field(1) + ".options: required for a choice field"])


func test_options_are_two_or_more_different_non_empty_strings() -> void:
	var rule: String = ".options: must be an array of at least 2 different non-empty strings"
	for bad: Variant in [[], ["Only one"], ["A", "A"], ["A", ""], ["A", 5], "A,B"]:
		assert_array(_with(["report", "fields", 1, "options"], bad)).override_failure_message(str(bad)).is_equal(
			[_field(1) + rule]
		)


func test_only_choice_fields_have_options() -> void:
	assert_array(_with(["report", "fields", 0, "options"], ["A", "B"])).is_equal([_field(0) + ".options: only choice fields have options"])
	assert_array(_with(["report", "fields", 2, "options"], ["A", "B"])).is_equal([_field(2) + ".options: only choice fields have options"])


func test_a_bad_kind_does_not_also_flag_options() -> void:
	assert_array(_edit(func(d: Dictionary) -> void:
		d["report"]["fields"][1]["kind"] = "number"
		d["report"]["fields"][1].erase("options"))).is_equal([_field(1) + ".kind: must be one of ipv4, choice, text"])


# --- report: evidence -------------------------------------------------------


func test_evidence_may_be_omitted_or_empty() -> void:
	assert_array(_without(["report", "fields", 0, "evidence"])).is_empty()
	assert_array(_with(["report", "fields", 0, "evidence"], [])).is_empty()


func test_evidence_must_be_an_array_of_objects() -> void:
	assert_array(_with(["report", "fields", 0, "evidence"], {})).is_equal([_field(0) + ".evidence: must be an array"])
	assert_array(_with(["report", "fields", 0, "evidence", 0], 5)).is_equal([_field(0) + ".evidence[0]: must be an object"])


func test_evidence_reference_keys() -> void:
	assert_array(_with(["report", "fields", 0, "evidence", 0, "why"], "x")).is_equal([_field(0) + ".evidence[0].why: unknown key"])
	for key in ["source", "file", "line"]:
		assert_array(_without(["report", "fields", 0, "evidence", 0, key])).override_failure_message(key).is_equal(
			[_field(0) + ".evidence[0]." + key + ": required"]
		)


func test_evidence_must_name_a_declared_log() -> void:
	assert_array(_evidence_of(0, _ref("WEB1", "/var/log/other.log", 1))).is_equal(
		[_field(0) + '.evidence[0]: no log "WEB1:/var/log/other.log" is declared']
	)
	# A real device and a real path, but that path is on another device.
	assert_array(_evidence_of(0, _ref("DB1", "/var/log/nginx/access.log", 1))).is_equal(
		[_field(0) + '.evidence[0]: no log "DB1:/var/log/nginx/access.log" is declared']
	)
	assert_array(_evidence_of(0, _ref("NOPE", "/var/log/auth.log", 1))).is_equal(
		[_field(0) + '.evidence[0]: no log "NOPE:/var/log/auth.log" is declared']
	)


func test_evidence_accepts_the_first_and_last_line_of_each_log() -> void:
	var firsts_and_lasts: Array = [
		_ref("WEB1", "/var/log/auth.log", 1), _ref("WEB1", "/var/log/auth.log", 5),
		_ref("WEB1", "/var/log/nginx/access.log", 1), _ref("WEB1", "/var/log/nginx/access.log", 3),
		_ref("DB1", "/var/log/auth.log", 1), _ref("DB1", "/var/log/auth.log", 2),
	]
	assert_array(_with(["report", "fields", 0, "evidence"], firsts_and_lasts)).is_empty()
	# A whole-number float is an integer in JSON.
	assert_array(_evidence_of(0, _ref("WEB1", "/var/log/auth.log", 5.0))).is_empty()


func test_evidence_line_zero_and_negative_are_rejected() -> void:
	for bad: Variant in [0, -1]:
		assert_array(_evidence_of(0, _ref("WEB1", "/var/log/auth.log", bad))).override_failure_message(str(bad)).is_equal(
			[_field(0) + ".evidence[0].line: must be an integer of at least 1"]
		)


func test_evidence_line_must_be_an_integer() -> void:
	for bad: Variant in [1.5, "3", null, true]:
		assert_array(_evidence_of(0, _ref("WEB1", "/var/log/auth.log", bad))).override_failure_message(str(bad)).is_equal(
			[_field(0) + ".evidence[0].line: must be an integer of at least 1"]
		)


func test_evidence_line_past_the_end_is_rejected() -> void:
	assert_array(_evidence_of(0, _ref("WEB1", "/var/log/auth.log", 6))).is_equal(
		[_field(0) + ".evidence[0].line: must be at most 5 (WEB1:/var/log/auth.log has 5 lines)"]
	)
	assert_array(_evidence_of(0, _ref("DB1", "/var/log/auth.log", 3))).is_equal(
		[_field(0) + ".evidence[0].line: must be at most 2 (DB1:/var/log/auth.log has 2 lines)"]
	)


func test_evidence_counts_lines_even_if_one_of_them_is_malformed() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["logs"][WEB_AUTH]["lines"][4].erase("text")
		d["report"]["fields"][0]["evidence"] = [_ref("WEB1", "/var/log/auth.log", 5)])
	assert_array(errors).is_equal([_line(WEB_AUTH, 4) + ".text: required"])


func test_an_unresolved_pair_and_a_bad_line_are_both_reported() -> void:
	assert_array(_evidence_of(0, _ref("WEB1", "/var/log/other.log", 0))).is_equal([
		_field(0) + ".evidence[0].line: must be an integer of at least 1",
		_field(0) + '.evidence[0]: no log "WEB1:/var/log/other.log" is declared',
	])


func test_every_bad_evidence_reference_is_reported() -> void:
	var errors: Array[String] = _with(["report", "fields", 0, "evidence"], [
		_ref("WEB1", "/var/log/auth.log", 1),
		_ref("WEB1", "/var/log/auth.log", 9),
		_ref("DB1", "/nope", 1),
	])
	assert_array(errors).is_equal([
		_field(0) + ".evidence[1].line: must be at most 5 (WEB1:/var/log/auth.log has 5 lines)",
		_field(0) + '.evidence[2]: no log "DB1:/nope" is declared',
	])


func test_evidence_is_checked_against_the_first_of_a_duplicated_pair() -> void:
	# The second copy is rejected as a duplicate, but the first still defines the log.
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		var copy: Dictionary = d["logs"][DB_AUTH].duplicate(true)
		copy["lines"] = copy["lines"].slice(0, 1)
		d["logs"].append(copy)
		d["report"]["fields"][0]["evidence"] = [_ref("DB1", "/var/log/auth.log", 2)])
	assert_array(errors).is_equal(['logs[3].file: duplicate log "DB1:/var/log/auth.log" (same as logs[2])'])


func test_a_broken_log_identity_does_not_also_flag_evidence_that_cites_it() -> void:
	# Losing WEB1's auth.log source leaves its evidence with no log to resolve to.
	assert_array(_without(["logs", WEB_AUTH, "source"])).is_equal([_log(WEB_AUTH) + ".source: required"])
	assert_array(_with(["logs", WEB_AUTH, "file"], "auth.log")).is_equal([_log(WEB_AUTH) + ".file: " + PATH_RULE])


func test_a_broken_log_identity_still_lets_other_evidence_be_checked() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["logs"][WEB_ACCESS]["file"] = "access.log"
		d["report"]["fields"][0]["evidence"] = [_ref("DB1", "/var/log/auth.log", 9)])
	assert_array(errors).is_equal([
		_log(WEB_ACCESS) + ".file: " + PATH_RULE,
		_field(0) + ".evidence[0].line: must be at most 2 (DB1:/var/log/auth.log has 2 lines)",
	])


# --- report objectives ------------------------------------------------------


func _objective(index: int) -> String:
	return "objectives[%d]" % index


func test_a_report_objective_takes_field_and_equals_only() -> void:
	assert_array(_with(["objectives", OBJ_IP, "extra"], 1)).is_equal([_objective(OBJ_IP) + ".extra: unknown key"])
	assert_array(_with(["objectives", OBJ_IP, "order"], 2)).is_empty()


func test_a_report_objective_needs_field_and_equals() -> void:
	assert_array(_without(["objectives", OBJ_IP, "field"])).is_equal([_objective(OBJ_IP) + ".field: required"])
	assert_array(_without(["objectives", OBJ_IP, "equals"])).is_equal([_objective(OBJ_IP) + ".equals: required"])


func test_the_field_must_exist_in_the_report() -> void:
	# The field the objective meant is not also reported as unchecked.
	assert_array(_with(["objectives", OBJ_IP, "field"], "nope")).is_equal(
		[_objective(OBJ_IP) + '.field: unknown report field "nope"']
	)
	assert_array(_with(["objectives", OBJ_IP, "field"], 5)).is_equal(
		[_objective(OBJ_IP) + ".field: must be a report field id"]
	)


func test_a_report_objective_without_any_report_is_unknown() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void: d.erase("report"))
	assert_array(errors).is_equal([
		_objective(OBJ_IP) + '.field: unknown report field "attacker_ip"',
		_objective(OBJ_TYPE) + '.field: unknown report field "attack_type"',
		_objective(OBJ_USER) + '.field: unknown report field "compromised_user"',
	])


func test_an_ipv4_answer_must_be_an_address() -> void:
	for bad: Variant in ["", "banana", "203.0.113", 5, null]:
		assert_array(_with(["objectives", OBJ_IP, "equals"], bad)).override_failure_message(str(bad)).is_equal(
			[_objective(OBJ_IP) + ".equals: must be an IPv4 address such as 192.168.10.1"]
		)


func test_a_choice_answer_must_be_one_of_the_options_exactly() -> void:
	var rule: String = ".equals: must be one of the field's options (Brute force, SQL injection, Port scan, Phishing)"
	for bad: Variant in ["Smishing", "brute force", "", 5]:
		assert_array(_with(["objectives", OBJ_TYPE, "equals"], bad)).override_failure_message(str(bad)).is_equal(
			[_objective(OBJ_TYPE) + rule]
		)
	assert_array(_with(["objectives", OBJ_TYPE, "equals"], "Phishing")).is_empty()


func test_a_text_answer_must_be_non_empty() -> void:
	for bad: Variant in ["", "   ", 5]:
		assert_array(_with(["objectives", OBJ_USER, "equals"], bad)).override_failure_message(str(bad)).is_equal(
			[_objective(OBJ_USER) + ".equals: must be a non-empty string"]
		)


func test_two_objectives_may_not_check_the_same_field() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		var copy: Dictionary = d["objectives"][OBJ_IP].duplicate(true)
		copy["id"] = "found_ip_again"
		d["objectives"].append(copy))
	assert_array(errors).is_equal([
		_objective(4) + '.field: a second objective for report field "attacker_ip" (same as objectives[1])',
	])


func test_every_report_field_needs_an_objective() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void: d["objectives"].remove_at(OBJ_USER))
	assert_array(errors).is_equal([_field(2) + ': no "report" objective checks field "compromised_user"'])


func test_a_malformed_field_does_not_also_flag_its_objective() -> void:
	# The field list can't be trusted, so the objective's field isn't called unknown.
	assert_array(_with(["report", "fields", 2, "id"], "Bad Id")).is_equal([_field(2) + ".id: " + SNAKE])
	assert_array(_without(["report", "fields", 1, "options"])).is_equal([_field(1) + ".options: required for a choice field"])
	assert_array(_with(["report", "fields"], [])).is_equal(["report.fields: needs at least one field"])


func test_an_answer_is_not_checked_against_a_field_that_is_not_there() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["objectives"][OBJ_IP]["field"] = "nope"
		d["objectives"][OBJ_IP]["equals"] = "banana")
	assert_array(errors).is_equal([_objective(OBJ_IP) + '.field: unknown report field "nope"'])
