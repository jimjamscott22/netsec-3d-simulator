class_name TestNetworkSimReport
extends GdUnitTestSuite
## submit_report, report_view and the report fields in scenario_view (task 2.3),
## end to end through load_scenario on the M2 fixture.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const ATTACKER: String = "203.0.113.45"


func _data() -> Dictionary:
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	assert_bool(data.is_empty()).is_false()
	return data


func _loaded(data: Dictionary = _data()) -> NetworkSim:
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(data).errors).is_empty()
	return sim


## Appends "<tag>:<args>" to `seen` each time `sig` fires.
func _record(sig: Signal, tag: String, seen: Array[String]) -> void:
	sig.connect(func(a: Variant = null, b: Variant = null) -> void:
		var parts: Array[String] = [tag]
		for v: Variant in [a, b]:
			if v != null:
				parts.append(str(v))
		seen.append(":".join(parts)))


func _state(sim: NetworkSim, id: String) -> ObjectiveState:
	for s in sim.objective_states():
		if s.id == id:
			return s
	return null


# --- the views --------------------------------------------------------------


func test_scenario_view_lists_every_log_file_in_order() -> void:
	var logs: Array = _loaded().scenario_view().logs()
	assert_array(logs).is_equal([
		{"source": "WEB1", "file": "/var/log/auth.log", "lines": 5},
		{"source": "WEB1", "file": "/var/log/nginx/access.log", "lines": 3},
		{"source": "DB1", "file": "/var/log/auth.log", "lines": 2},
	])


func test_scenario_view_lists_every_report_field_with_its_kind_and_options() -> void:
	var view: ScenarioView = _loaded().scenario_view()
	assert_bool(view.has_report()).is_true()
	assert_int(view.report_max_attempts()).is_equal(3)
	var fields: Array = view.report_fields()
	assert_array(fields.map(func(f: Dictionary) -> String: return f["id"])).is_equal(["attacker_ip", "attack_type", "compromised_user"])
	assert_str(fields[0]["label"]).is_equal("Attacker IP")
	assert_int(fields[0]["kind"]).is_equal(ReportState.Kind.IPV4)
	assert_int(fields[1]["kind"]).is_equal(ReportState.Kind.CHOICE)
	assert_array(fields[1]["options"]).is_equal(["Brute force", "SQL injection", "Port scan", "Phishing"])
	assert_array(fields[2]["options"]).is_empty()


func test_max_attempts_in_the_view_follows_the_scenario() -> void:
	var data: Dictionary = _data()
	data["report"]["max_attempts"] = 5
	assert_int(_loaded(data).scenario_view().report_max_attempts()).is_equal(5)
	data["report"].erase("max_attempts")
	assert_int(_loaded(data).scenario_view().report_max_attempts()).is_equal(3)


func test_no_view_holds_an_expected_answer() -> void:
	var sim: NetworkSim = _loaded()
	var seen: String = "%s %s %s %s" % [
		sim.scenario_view().report_fields(), sim.scenario_view().logs(),
		sim.report_view().fields(), sim.objective_states().map(func(s: ObjectiveState) -> String: return s.description + s.detail),
	]
	# The attacker address and the account only appear in the answers (a choice's answer is
	# also one of its listed options, so it can't be told apart).
	assert_str(seen).not_contains(ATTACKER)
	assert_str(seen).not_contains("deploy")
	for s in sim.objective_states():
		for prop in s.get_property_list():
			assert_str(str(prop["name"])).is_not_equal("equals")


func test_a_scenario_without_a_report_has_none() -> void:
	var data: Dictionary = _data()
	data.erase("logs")
	data.erase("report")
	data["objectives"] = data["objectives"].filter(func(o: Dictionary) -> bool: return o["type"] != "report")
	var sim: NetworkSim = _loaded(data)
	assert_bool(sim.scenario_view().has_report()).is_false()
	assert_int(sim.scenario_view().report_max_attempts()).is_equal(0)
	assert_array(sim.scenario_view().logs()).is_empty()
	assert_array(sim.report_view().fields()).is_empty()
	var r: ReportResult = sim.submit_report("attacker_ip", ATTACKER)
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(ReportResult.Reason.UNKNOWN_FIELD)


func test_before_any_scenario_there_is_nothing_to_report() -> void:
	var sim := NetworkSim.new()
	assert_array(sim.report_view().fields()).is_empty()
	assert_int(sim.submit_report("attacker_ip", ATTACKER).reason).is_equal(ReportResult.Reason.UNKNOWN_FIELD)


func test_report_view_starts_with_full_attempts() -> void:
	var fields: Array[Dictionary] = _loaded().report_view().fields()
	assert_int(fields.size()).is_equal(3)
	for f in fields:
		assert_int(f["attempts_left"]).is_equal(3)
		assert_bool(f["solved"]).is_false()


# --- submitting -------------------------------------------------------------


func test_a_right_answer_emits_report_submitted_and_passes_its_objective() -> void:
	var sim: NetworkSim = _loaded()
	var seen: Array[String] = []
	_record(sim.events.report_submitted, "report", seen)
	_record(sim.events.objective_updated, "objective", seen)
	var r: ReportResult = sim.submit_report("attacker_ip", ATTACKER)
	assert_bool(r.ok).is_true()
	assert_bool(r.correct).is_true()
	# `report_submitted` first, then the objective it changed.
	assert_array(seen).is_equal(["report:attacker_ip:true", "objective:found_ip:true"])
	assert_bool(_state(sim, "found_ip").passed).is_true()
	assert_bool(sim.report_view().solved("attacker_ip")).is_true()


func test_a_wrong_answer_emits_report_submitted_false_and_costs_an_attempt() -> void:
	var sim: NetworkSim = _loaded()
	var seen: Array[String] = []
	_record(sim.events.report_submitted, "report", seen)
	_record(sim.events.objective_updated, "objective", seen)
	var r: ReportResult = sim.submit_report("attacker_ip", "198.51.100.7")
	assert_bool(r.ok).is_true()
	assert_bool(r.correct).is_false()
	assert_int(r.attempts_left).is_equal(2)
	assert_array(seen).is_equal(["report:attacker_ip:false"])
	assert_int(sim.report_view().attempts_left("attacker_ip")).is_equal(2)
	assert_str(sim.report_view().field("attacker_ip")["last_value"]).is_equal("198.51.100.7")
	assert_bool(_state(sim, "found_ip").passed).is_false()


func test_the_objective_detail_counts_attempts_left() -> void:
	var sim: NetworkSim = _loaded()
	assert_str(_state(sim, "found_ip").detail).is_equal("3 attempts left")
	sim.submit_report("attacker_ip", "198.51.100.7")
	assert_str(_state(sim, "found_ip").detail).is_equal("2 attempts left")
	sim.submit_report("attacker_ip", "198.51.100.8")
	assert_str(_state(sim, "found_ip").detail).is_equal("1 attempt left")
	sim.submit_report("attacker_ip", "198.51.100.9")
	assert_str(_state(sim, "found_ip").detail).is_equal("0 attempts left")
	assert_bool(_state(sim, "found_ip").passed).is_false()


func test_a_passed_report_objective_has_no_detail() -> void:
	var sim: NetworkSim = _loaded()
	sim.submit_report("attacker_ip", ATTACKER)
	assert_str(_state(sim, "found_ip").detail).is_empty()
	assert_int(_state(sim, "found_ip").type).is_equal(ObjectiveState.Type.REPORT)


func test_a_refused_submission_emits_nothing_and_changes_nothing() -> void:
	var sim: NetworkSim = _loaded()
	var seen: Array[String] = []
	_record(sim.events.report_submitted, "report", seen)
	_record(sim.events.objective_updated, "objective", seen)
	assert_int(sim.submit_report("nope", "x").reason).is_equal(ReportResult.Reason.UNKNOWN_FIELD)
	assert_int(sim.submit_report("attacker_ip", "banana").reason).is_equal(ReportResult.Reason.INVALID_VALUE)
	assert_int(sim.submit_report("attack_type", "Smishing").reason).is_equal(ReportResult.Reason.INVALID_VALUE)
	sim.submit_report("compromised_user", "deploy")
	seen.clear()
	assert_int(sim.submit_report("compromised_user", "deploy").reason).is_equal(ReportResult.Reason.ALREADY_SOLVED)
	assert_array(seen).is_empty()
	assert_int(sim.report_view().attempts_left("attacker_ip")).is_equal(3)


func test_out_of_attempts_refuses_even_the_right_answer() -> void:
	var data: Dictionary = _data()
	data["report"]["max_attempts"] = 1
	var sim: NetworkSim = _loaded(data)
	sim.submit_report("attacker_ip", "198.51.100.7")
	var r: ReportResult = sim.submit_report("attacker_ip", ATTACKER)
	assert_bool(r.ok).is_false()
	assert_int(r.reason).is_equal(ReportResult.Reason.OUT_OF_ATTEMPTS)
	assert_bool(_state(sim, "found_ip").passed).is_false()


func test_normalization_applies_through_the_sim() -> void:
	var sim: NetworkSim = _loaded()
	assert_bool(sim.submit_report("attack_type", "  brute FORCE ").correct).is_true()
	assert_bool(sim.submit_report("compromised_user", " DEPLOY\n").correct).is_true()


# --- the mission ------------------------------------------------------------


func test_filing_every_field_completes_the_mission_once() -> void:
	var sim: NetworkSim = _loaded()
	var seen: Array[String] = []
	_record(sim.events.mission_completed, "completed", seen)
	sim.submit_report("attacker_ip", ATTACKER)
	sim.submit_report("attack_type", "Brute force")
	assert_array(seen).is_empty()
	sim.submit_report("compromised_user", "deploy")
	assert_array(seen).is_equal(["completed:m2_fixture"])
	assert_object(sim.debrief_view()).is_not_null()


func test_a_report_objective_respects_order() -> void:
	var data: Dictionary = _data()
	data["objectives"][1]["order"] = 1  # found_ip
	data["objectives"][2]["order"] = 2  # found_type
	var sim: NetworkSim = _loaded(data)
	sim.submit_report("attack_type", "Brute force")
	var locked: ObjectiveState = _state(sim, "found_type")
	assert_bool(locked.locked).is_true()
	assert_bool(locked.passed).is_false()
	sim.submit_report("attacker_ip", ATTACKER)
	assert_bool(_state(sim, "found_type").passed).is_true()


# --- reloading --------------------------------------------------------------


func test_reloading_resets_attempts_and_answers() -> void:
	var sim: NetworkSim = _loaded()
	sim.submit_report("attacker_ip", "198.51.100.7")
	sim.submit_report("compromised_user", "deploy")
	assert_array(sim.load_scenario(_data()).errors).is_empty()
	var view: ReportView = sim.report_view()
	assert_int(view.attempts_left("attacker_ip")).is_equal(3)
	assert_bool(view.solved("compromised_user")).is_false()
	assert_str(view.field("attacker_ip")["last_value"]).is_empty()


func test_loading_a_scenario_without_a_report_drops_the_old_one() -> void:
	var sim: NetworkSim = _loaded()
	assert_array(sim.load_scenario(ScenarioRunner.read("res://scenarios/m1_vlan_ping.json")).errors).is_empty()
	assert_array(sim.report_view().fields()).is_empty()
	assert_bool(sim.scenario_view().has_report()).is_false()
