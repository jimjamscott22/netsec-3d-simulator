class_name TestM2LogTriage
extends GdUnitTestSuite
## The real M2 mission (task 2.9). The smoke test already proves its solution works;
## these tests pin what makes it a fair puzzle: the logs really point at one
## attacker, the lookalikes are not the answer, the evidence lines say what the
## report claims, and no live view gives the answer away.

const PATH: String = "res://scenarios/m2_log_triage.json"
const ATTACKER: String = "203.0.113.45"
const AUTH: String = "/var/log/auth.log"


func _data() -> Dictionary:
	var data: Dictionary = ScenarioRunner.read(PATH)
	assert_bool(data.is_empty()).is_false()
	return data


func _sim() -> NetworkSim:
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(_data()).errors).is_empty()
	return sim


func _auth(sim: NetworkSim) -> Array[LogLine]:
	return sim.query_logs("WEB1", AUTH, null)


func _count(lines: Array[LogLine], ip: String, needle: String) -> int:
	var n: int = 0
	for line: LogLine in lines:
		if line.src_ip() == ip and line.text().contains(needle):
			n += 1
	return n


func test_it_is_a_valid_scenario_of_a_sensible_size() -> void:
	assert_array(ScenarioValidator.validate(_data(), "m2_log_triage")).is_empty()
	var total: int = 0
	for entry: Dictionary in _sim().scenario_view().logs():
		total += entry["lines"]
	assert_int(total).is_between(150, 300)


func test_exactly_one_address_fails_a_lot_and_then_gets_in() -> void:
	var lines: Array[LogLine] = _auth(_sim())
	var failures: Dictionary = {}
	for line: LogLine in lines:
		if line.text().contains("Failed password") and not line.src_ip().is_empty():
			failures[line.src_ip()] = int(failures.get(line.src_ip(), 0)) + 1
	var heavy: Array[String] = []
	for ip: String in failures:
		if failures[ip] >= 10:
			heavy.append(ip)
	assert_array(heavy).is_equal([ATTACKER])
	assert_int(_count(lines, ATTACKER, "Accepted password")).is_equal(1)


func test_the_lookalikes_are_not_the_answer() -> void:
	var lines: Array[LogLine] = _auth(_sim())
	# A scanner fails a few times and never gets in.
	assert_int(_count(lines, "192.0.2.88", "Failed password")).is_between(1, 9)
	assert_int(_count(lines, "192.0.2.88", "Accepted")).is_equal(0)
	# The deploy account also logs in legitimately, so the name alone proves nothing.
	assert_int(_count(lines, "198.51.100.7", "Accepted publickey for deploy")).is_greater(0)


func test_the_attacker_succeeds_after_every_one_of_the_failures() -> void:
	var lines: Array[LogLine] = _auth(_sim())
	var last_failure: int = 0
	var accepted: int = 0
	for line: LogLine in lines:
		if line.src_ip() != ATTACKER:
			continue
		if line.text().contains("Failed password"):
			last_failure = line.number()
		elif line.text().contains("Accepted password for deploy"):
			accepted = line.number()
	assert_int(accepted).is_greater(last_failure)


func test_every_evidence_line_says_what_the_field_claims() -> void:
	var sim: NetworkSim = _sim()
	_fail_attack_type(sim)
	var by_id: Dictionary = {}
	for f: Dictionary in sim.debrief_view().report_fields():
		by_id[f["id"]] = f
	for e: Dictionary in by_id["attacker_ip"]["evidence"]:
		assert_str(e["text"]).contains(ATTACKER)
	var first: Dictionary = by_id["attacker_ip"]["evidence"][0]
	assert_str(first["text"]).contains("Failed password")
	assert_str(by_id["attacker_ip"]["evidence"][1]["text"]).contains("Accepted password for deploy from " + ATTACKER)
	for e: Dictionary in by_id["attack_type"]["evidence"]:
		assert_str(e["text"]).contains("Failed password")
		assert_str(e["text"]).contains(ATTACKER)
	assert_str(by_id["compromised_user"]["evidence"][0]["text"]).contains("Accepted password for deploy")


func test_no_live_view_shows_an_answer_or_a_log_line() -> void:
	var sim: NetworkSim = _sim()
	var seen: PackedStringArray = []
	seen.append(str(sim.scenario_view().logs()))
	seen.append(str(sim.scenario_view().report_fields()))
	seen.append(str(sim.report_view().fields()))
	for s: String in seen:
		assert_str(s).not_contains(ATTACKER)
		# "Brute force" is one of the options the player sees, so only the
		# account name stands for the other answers here.
		assert_str(s).not_contains("deploy")
	assert_object(sim.debrief_view()).is_null()


func test_the_choice_is_not_a_coin_flip() -> void:
	for f: Dictionary in _sim().scenario_view().report_fields():
		if f["id"] == "attack_type":
			assert_int((f["options"] as Array).size()).is_greater_equal(6)


func test_it_starts_unsolved_and_fails_for_good_on_three_wrong_answers() -> void:
	var sim: NetworkSim = _sim()
	for state: ObjectiveState in sim.objective_states():
		assert_bool(state.passed).is_false()
	_fail_attack_type(sim)
	assert_bool(sim.debrief_view().completed()).is_false()


func test_the_solution_is_all_report_steps_and_completes_it() -> void:
	var data: Dictionary = _data()
	for step: Dictionary in data["solution"]:
		assert_bool(step.has("report")).is_true()
	var sim := NetworkSim.new()
	assert_array(sim.load_scenario(data).errors).is_empty()
	assert_array(ScenarioRunner.apply_solution(sim, data)).is_empty()
	assert_bool(sim.debrief_view().completed()).is_true()


func _fail_attack_type(sim: NetworkSim) -> void:
	for wrong: String in ["Port scan", "Phishing", "Malware"]:
		sim.submit_report("attack_type", wrong)
