class_name TestReportState
extends GdUnitTestSuite
## ReportState on its own (task 2.3): matching, attempts, and what a refusal costs.


func _state(max_attempts: Variant = null) -> ReportState:
	var report: Dictionary = {
		"fields": [
			{"id": "attacker_ip", "label": "Attacker IP", "kind": "ipv4"},
			{"id": "attack_type", "label": "Attack type", "kind": "choice", "options": ["Brute force", "SQL injection"]},
			{"id": "user", "label": "Account", "kind": "text"},
		],
	}
	if max_attempts != null:
		report["max_attempts"] = max_attempts
	var answers: Dictionary = {"attacker_ip": "203.0.113.45", "attack_type": "Brute force", "user": "deploy"}
	return ReportState.from_scenario(report, answers)


func test_fields_keep_file_order_and_start_unsolved_with_default_attempts() -> void:
	var s: ReportState = _state()
	assert_array(s.field_ids()).is_equal(["attacker_ip", "attack_type", "user"])
	for f in s.view().fields():
		assert_int(f["attempts_left"]).is_equal(3)
		assert_bool(f["solved"]).is_false()
		assert_str(f["last_value"]).is_empty()


func test_max_attempts_comes_from_the_report_and_accepts_a_whole_float() -> void:
	assert_int(_state(5).view().attempts_left("user")).is_equal(5)
	assert_int(_state(2.0).view().attempts_left("user")).is_equal(2)


func test_a_right_answer_solves_the_field_and_keeps_its_attempts() -> void:
	var s: ReportState = _state()
	var r: ReportResult = s.submit("attacker_ip", "203.0.113.45")
	assert_bool(r.ok).is_true()
	assert_bool(r.correct).is_true()
	assert_int(r.attempts_left).is_equal(3)
	assert_bool(s.view().solved("attacker_ip")).is_true()
	assert_str(s.view().field("attacker_ip")["last_value"]).is_equal("203.0.113.45")


func test_a_wrong_answer_costs_one_attempt() -> void:
	var s: ReportState = _state()
	var r: ReportResult = s.submit("attacker_ip", "198.51.100.7")
	assert_bool(r.ok).is_true()
	assert_bool(r.correct).is_false()
	assert_int(r.attempts_left).is_equal(2)
	var f: Dictionary = s.view().field("attacker_ip")
	assert_int(f["attempts_left"]).is_equal(2)
	assert_bool(f["solved"]).is_false()
	assert_str(f["last_value"]).is_equal("198.51.100.7")


func test_attempts_are_counted_per_field() -> void:
	var s: ReportState = _state()
	s.submit("attacker_ip", "198.51.100.7")
	assert_int(s.view().attempts_left("attacker_ip")).is_equal(2)
	assert_int(s.view().attempts_left("user")).is_equal(3)


func test_matching_ignores_case_and_surrounding_whitespace() -> void:
	for typed in ["DEPLOY", "  deploy  ", "\tDeploy\n"]:
		var s: ReportState = _state()
		assert_bool(s.submit("user", typed).correct).override_failure_message(typed).is_true()


func test_matching_collapses_inner_whitespace() -> void:
	var s: ReportState = _state()
	assert_bool(s.submit("attack_type", "  brute    FORCE ").correct).is_true()


func test_a_choice_is_filed_in_the_options_own_spelling() -> void:
	var s: ReportState = _state()
	s.submit("attack_type", "sql INJECTION")
	assert_str(s.view().field("attack_type")["last_value"]).is_equal("SQL injection")


func test_text_is_filed_trimmed() -> void:
	var s: ReportState = _state()
	s.submit("user", "  Admin   User ")
	assert_str(s.view().field("user")["last_value"]).is_equal("Admin User")


func test_a_choice_outside_the_options_is_refused_and_free() -> void:
	var s: ReportState = _state()
	var r: ReportResult = s.submit("attack_type", "Phishing")
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(ReportResult.Reason.INVALID_VALUE)
	assert_int(r.attempts_left).is_equal(3)
	assert_int(s.view().attempts_left("attack_type")).is_equal(3)
	assert_str(s.view().field("attack_type")["last_value"]).is_empty()


func test_a_malformed_ip_is_refused_and_free() -> void:
	var s: ReportState = _state()
	for bad in ["", "203.0.113", "banana", "999.1.1.1", "203.0.113.45 extra"]:
		var r: ReportResult = s.submit("attacker_ip", bad)
		assert_int(r.reason).override_failure_message(bad).is_equal(ReportResult.Reason.INVALID_VALUE)
	assert_int(s.view().attempts_left("attacker_ip")).is_equal(3)


func test_empty_text_is_refused_and_free() -> void:
	var s: ReportState = _state()
	for bad in ["", "   ", "\n"]:
		assert_int(s.submit("user", bad).reason).override_failure_message(bad).is_equal(ReportResult.Reason.INVALID_VALUE)
	assert_int(s.view().attempts_left("user")).is_equal(3)


func test_unknown_field_is_refused() -> void:
	var r: ReportResult = _state().submit("nope", "x")
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(ReportResult.Reason.UNKNOWN_FIELD)


func test_a_solved_field_refuses_more_answers_and_stays_solved() -> void:
	var s: ReportState = _state()
	s.submit("user", "deploy")
	var r: ReportResult = s.submit("user", "somebody else")
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(ReportResult.Reason.ALREADY_SOLVED)
	assert_bool(s.view().solved("user")).is_true()
	assert_str(s.view().field("user")["last_value"]).is_equal("deploy")


func test_running_out_of_attempts_refuses_even_the_right_answer() -> void:
	var s: ReportState = _state(2)
	assert_int(s.submit("user", "a").attempts_left).is_equal(1)
	assert_int(s.submit("user", "b").attempts_left).is_equal(0)
	var r: ReportResult = s.submit("user", "deploy")
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(ReportResult.Reason.OUT_OF_ATTEMPTS)
	assert_bool(s.view().solved("user")).is_false()
	assert_str(s.view().field("user")["last_value"]).is_equal("b")


func test_the_last_attempt_can_still_be_right() -> void:
	var s: ReportState = _state(1)
	assert_bool(s.submit("user", "deploy").correct).is_true()
	assert_bool(s.view().solved("user")).is_true()


func test_the_view_is_a_snapshot_and_has_no_answers() -> void:
	var s: ReportState = _state()
	var before: ReportView = s.view()
	s.submit("user", "wrong")
	assert_int(before.attempts_left("user")).is_equal(3)
	before.fields()[0]["solved"] = true
	assert_bool(s.view().solved("attacker_ip")).is_false()
	for f in s.view().fields():
		assert_array(f.keys()).contains_exactly_in_any_order(["id", "attempts_left", "last_value", "solved"])
	assert_str(str(s.view().fields())).not_contains("203.0.113.45")


func test_view_lookups_for_an_unknown_field() -> void:
	var v: ReportView = _state().view()
	assert_bool(v.has_field("nope")).is_false()
	assert_bool(v.has_field("user")).is_true()
	assert_dict(v.field("nope")).is_empty()
	assert_bool(v.solved("nope")).is_false()
	assert_int(v.attempts_left("nope")).is_equal(0)


func test_validator_and_state_agree_on_the_report_kinds() -> void:
	var names: Array[String] = []
	for key: String in ReportState.Kind.keys():
		names.append(key.to_lower())
	assert_array(names).contains_exactly(ScenarioValidator.REPORT_KINDS)
