class_name TestDebriefReport
extends GdUnitTestSuite
## The report part of debrief_view (task 2.8b): the answers and the cited log
## lines exist only once the mission has ended, whether it was won or failed.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const ATTACKER: String = "203.0.113.45"
const M1: String = "res://scenarios/m1_vlan_ping.json"


func _loaded() -> NetworkSim:
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(ScenarioRunner.read(FIXTURE)).errors).is_empty()
	return sim


func _fail(sim: NetworkSim) -> void:
	for wrong: String in ["Port scan", "Phishing", "SQL injection"]:
		sim.submit_report("attack_type", wrong)


func _field(view: DebriefView, id: String) -> Dictionary:
	for f: Dictionary in view.report_fields():
		if f["id"] == id:
			return f
	return {}


func test_there_are_no_answers_during_play() -> void:
	var sim: NetworkSim = _loaded()
	assert_object(sim.debrief_view()).is_null()
	sim.submit_report("attack_type", "Port scan")
	assert_object(sim.debrief_view()).is_null()
	# The live views still carry no answer.
	for f: Dictionary in sim.report_view().fields():
		assert_bool(f.has("answer")).is_false()
	for f: Dictionary in sim.scenario_view().report_fields():
		assert_bool(f.has("answer")).is_false()
		assert_bool(f.has("evidence")).is_false()


func test_a_failed_mission_reveals_every_answer() -> void:
	var sim: NetworkSim = _loaded()
	sim.submit_report("attacker_ip", "198.51.100.7")
	_fail(sim)
	var view: DebriefView = sim.debrief_view()
	assert_bool(view.completed()).is_false()
	assert_array(view.report_fields().map(func(f: Dictionary) -> String: return f["id"])).is_equal(
		["attacker_ip", "attack_type", "compromised_user"]
	)
	assert_str(_field(view, "attacker_ip")["answer"]).is_equal(ATTACKER)
	assert_str(_field(view, "attack_type")["answer"]).is_equal("Brute force")
	assert_str(_field(view, "compromised_user")["answer"]).is_equal("deploy")
	assert_str(_field(view, "attacker_ip")["label"]).is_equal("Attacker IP")


func test_what_the_player_filed_is_kept_with_each_answer() -> void:
	var sim: NetworkSim = _loaded()
	sim.submit_report("attacker_ip", "198.51.100.7")
	sim.submit_report("compromised_user", "deploy")
	_fail(sim)
	var view: DebriefView = sim.debrief_view()
	var ip: Dictionary = _field(view, "attacker_ip")
	assert_str(ip["last_value"]).is_equal("198.51.100.7")
	assert_bool(ip["solved"]).is_false()
	assert_bool(_field(view, "compromised_user")["solved"]).is_true()
	assert_str(_field(view, "attack_type")["last_value"]).is_equal("SQL injection")


func test_evidence_resolves_to_the_log_lines_as_the_player_saw_them() -> void:
	var sim: NetworkSim = _loaded()
	_fail(sim)
	var evidence: Array = _field(sim.debrief_view(), "attacker_ip")["evidence"]
	assert_int(evidence.size()).is_equal(2)
	var first: LogLine = sim.query_logs("WEB1", "/var/log/auth.log", null)[0]
	assert_str(evidence[0]["source"]).is_equal("WEB1")
	assert_str(evidence[0]["file"]).is_equal("/var/log/auth.log")
	assert_int(evidence[0]["line"]).is_equal(1)
	assert_str(evidence[0]["text"]).is_equal(first.full_text())
	assert_int(evidence[1]["line"]).is_equal(5)
	assert_str(evidence[1]["text"]).is_equal("cron[12]: session opened for user root")


func test_a_field_without_evidence_has_an_empty_list() -> void:
	var sim: NetworkSim = _loaded()
	_fail(sim)
	var view: DebriefView = sim.debrief_view()
	assert_array(_field(view, "attack_type")["evidence"]).is_empty()
	assert_array(_field(view, "compromised_user")["evidence"]).is_empty()


func test_a_completed_mission_has_the_answers_too() -> void:
	# Drop the fixture's config objective so the report alone can complete it.
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	var kept: Array = []
	for o: Dictionary in data["objectives"]:
		if o["type"] == "report":
			kept.append(o)
	data["objectives"] = kept
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(data).errors).is_empty()
	sim.submit_report("attacker_ip", ATTACKER)
	sim.submit_report("attack_type", "brute force")
	sim.submit_report("compromised_user", "deploy")
	var view: DebriefView = sim.debrief_view()
	assert_object(view).is_not_null()
	assert_bool(view.completed()).is_true()
	assert_bool(_field(view, "attacker_ip")["solved"]).is_true()
	assert_str(_field(view, "attack_type")["answer"]).is_equal("Brute force")
	assert_int((_field(view, "attacker_ip")["evidence"] as Array).size()).is_equal(2)


func test_the_view_hands_out_copies() -> void:
	var sim: NetworkSim = _loaded()
	_fail(sim)
	var view: DebriefView = sim.debrief_view()
	var fields: Array[Dictionary] = view.report_fields()
	fields[0]["answer"] = "tampered"
	(fields[0]["evidence"] as Array).clear()
	assert_str(_field(view, "attacker_ip")["answer"]).is_equal(ATTACKER)
	assert_int((_field(view, "attacker_ip")["evidence"] as Array).size()).is_equal(2)


func test_a_mission_without_a_report_has_no_report_rows() -> void:
	var data: Dictionary = ScenarioRunner.read(M1)
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(data).errors).is_empty()
	assert_array(ScenarioRunner.apply_solution(sim, data)).is_empty()
	var view: DebriefView = sim.debrief_view()
	assert_object(view).is_not_null()
	assert_array(view.report_fields()).is_empty()


func test_reloading_clears_the_debrief() -> void:
	var sim: NetworkSim = _loaded()
	_fail(sim)
	assert_object(sim.debrief_view()).is_not_null()
	assert_array(sim.load_scenario(ScenarioRunner.read(FIXTURE)).errors).is_empty()
	assert_object(sim.debrief_view()).is_null()
