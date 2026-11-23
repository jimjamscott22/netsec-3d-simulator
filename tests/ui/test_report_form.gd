class_name TestReportForm
extends GdUnitTestSuite
## The incident report form (task 2.8): rows come from the mission's report
## fields, attempts left and results come from the sim, nothing is per mission.

const FORM_SCENE: PackedScene = preload("res://ui/report_form.tscn")
const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const FIXTURE_ID: String = "m2_fixture"
const TEMP_DIR: String = "user://report_form_test_scenarios"
const MISSION: String = "m1_vlan_ping"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEMP_DIR, FIXTURE_ID], FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(FIXTURE))
	file.close()
	Sim.scenario_dir = TEMP_DIR
	assert_array(Sim.load_scenario_id(FIXTURE_ID).errors).is_empty()


func after_test() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	Sim.load_scenario_id(MISSION)
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		for name: String in DirAccess.get_files_at(TEMP_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEMP_DIR, name])


func _form() -> ReportForm:
	var form: ReportForm = auto_free(FORM_SCENE.instantiate()) as ReportForm
	add_child(form)
	return form


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	return k


# --- opening and closing ----------------------------------------------------------


func test_starts_hidden() -> void:
	var form: ReportForm = _form()
	assert_bool(form.visible).is_false()
	assert_bool(form.is_open()).is_false()


func test_open_builds_one_row_per_report_field_in_file_order() -> void:
	var form: ReportForm = _form()
	assert_bool(form.open()).is_true()
	assert_bool(form.visible).is_true()
	var expected: Array[String] = []
	for field: Dictionary in Sim.scenario_view().report_fields():
		expected.append(field["id"])
	assert_array(form.field_ids()).is_equal(expected)
	assert_array(form.field_ids()).is_not_empty()
	for id: String in form.field_ids():
		assert_str(form.status_text(id)).is_equal("3 attempts left")
		assert_bool(form.is_locked(id)).is_false()


func test_open_refuses_a_mission_without_a_report() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	var form: ReportForm = _form()
	assert_bool(form.open()).is_false()
	assert_bool(form.visible).is_false()


func test_close_signals_and_loading_a_mission_closes() -> void:
	var form: ReportForm = _form()
	var closed: Array[bool] = []
	form.closed.connect(func() -> void: closed.append(true))
	form.open()
	assert_bool(form.visible).is_true()
	Sim.scenario_dir = TEMP_DIR
	Sim.load_scenario_id(FIXTURE_ID)
	assert_bool(form.visible).is_false()
	form.open()
	form.close()
	assert_bool(form.visible).is_false()
	assert_array(closed).has_size(2)


# --- submitting --------------------------------------------------------------------


func test_a_wrong_answer_costs_an_attempt_and_says_so() -> void:
	var form: ReportForm = _form()
	form.open()
	form.set_value("attacker_ip", "198.51.100.7")
	var result: ReportResult = form.submit("attacker_ip")
	assert_bool(result.ok).is_true()
	assert_bool(result.correct).is_false()
	assert_str(form.feedback("attacker_ip")).is_equal(ReportForm.WRONG_NOTE)
	assert_str(form.status_text("attacker_ip")).is_equal("2 attempts left")
	assert_bool(form.is_locked("attacker_ip")).is_false()
	# Only that field paid.
	assert_str(form.status_text("compromised_user")).is_equal("3 attempts left")


func test_the_last_attempt_reads_in_the_singular() -> void:
	assert_str(ReportForm.attempts_text(1)).is_equal("1 attempt left")
	assert_str(ReportForm.attempts_text(2)).is_equal("2 attempts left")


func test_a_right_answer_solves_and_locks_the_field() -> void:
	var form: ReportForm = _form()
	form.open()
	form.set_value("attack_type", "Brute force")
	assert_bool(form.submit("attack_type").correct).is_true()
	assert_str(form.feedback("attack_type")).is_equal(ReportForm.CORRECT_NOTE)
	assert_str(form.status_text("attack_type")).is_equal(ReportForm.SOLVED_NOTE)
	assert_bool(form.is_locked("attack_type")).is_true()
	assert_str(form.value_of("attack_type")).is_equal("Brute force")


func test_a_value_that_cannot_be_an_answer_costs_nothing_and_explains() -> void:
	var form: ReportForm = _form()
	form.open()
	form.set_value("attacker_ip", "not an ip")
	assert_bool(form.submit("attacker_ip").ok).is_false()
	assert_str(form.feedback("attacker_ip")).is_equal("That is not a valid IPv4 address.")
	assert_str(form.status_text("attacker_ip")).is_equal("3 attempts left")


func test_an_empty_box_or_unpicked_choice_is_not_sent() -> void:
	var form: ReportForm = _form()
	form.open()
	var seen: Array[String] = []
	Sim.report_submitted.connect(func(field: String, _c: bool) -> void: seen.append(field))
	assert_bool(form.submit("compromised_user").ok).is_false()
	assert_str(form.feedback("compromised_user")).is_equal("Type an answer first.")
	assert_str(form.value_of("attack_type")).is_empty()
	assert_bool(form.submit("attack_type").ok).is_false()
	assert_str(form.feedback("attack_type")).is_equal("Pick one of the options first.")
	assert_array(seen).is_empty()


func test_choice_fields_list_the_mission_options() -> void:
	var form: ReportForm = _form()
	form.open()
	var list: OptionButton = form.get_node("Root").find_child("Input", true, false) as OptionButton
	assert_object(list).is_not_null()
	var options: Array = []
	for field: Dictionary in Sim.scenario_view().report_fields():
		if field["id"] == "attack_type":
			options = field["options"]
	assert_int(list.item_count).is_equal(options.size())
	assert_int(list.selected).is_equal(-1)


func test_running_out_of_attempts_locks_the_field() -> void:
	var form: ReportForm = _form()
	form.open()
	for wrong: String in ["Port scan", "Phishing"]:
		form.set_value("attack_type", wrong)
		form.submit("attack_type")
	assert_str(form.status_text("attack_type")).is_equal("1 attempt left")
	form.set_value("attack_type", "SQL injection")
	form.submit("attack_type")
	assert_str(form.status_text("attack_type")).is_equal(ReportForm.LOCKED_NOTE)
	assert_bool(form.is_locked("attack_type")).is_true()
	# The sim ended the mission, so the other fields refuse too.
	form.set_value("compromised_user", "deploy")
	assert_bool(form.submit("compromised_user").ok).is_false()
	assert_str(form.feedback("compromised_user")).is_equal("The mission is over.")


func test_the_form_follows_a_submission_made_elsewhere() -> void:
	var form: ReportForm = _form()
	form.open()
	Sim.submit_report("compromised_user", "deploy")
	assert_str(form.status_text("compromised_user")).is_equal(ReportForm.SOLVED_NOTE)
	assert_str(form.value_of("compromised_user")).is_equal("deploy")


func test_refusal_wording_covers_every_reason() -> void:
	for reason: ReportResult.Reason in ReportResult.Reason.values():
		if reason == ReportResult.Reason.NONE:
			continue
		var result: ReportResult = ReportResult.refused(reason)
		assert_str(ReportForm.feedback_text(result, ReportState.Kind.TEXT)).is_not_empty()


# --- wired into the game -----------------------------------------------------------


func test_the_log_viewer_offers_the_report_and_opens_the_form() -> void:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	var viewer: LogViewer = main.get_node("LogViewer") as LogViewer
	var form: ReportForm = main.get_node("ReportForm") as ReportForm
	viewer.open()
	assert_bool(viewer.report_offered()).is_true()
	assert_bool(viewer.handle_key(_key(KEY_F2))).is_true()
	assert_bool(viewer.is_open()).is_false()
	assert_bool(form.is_open()).is_true()
	assert_bool((main.get_node("MissionHUD") as CanvasLayer).visible).is_false()
	form.close()
	assert_bool((main.get_node("MissionHUD") as CanvasLayer).visible).is_true()
