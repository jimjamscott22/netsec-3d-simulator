class_name TestFailedCard
extends GdUnitTestSuite
## The failed-mission card (task 2.8b, SPEC §7.2 step 6): running out of
## attempts stops play and shows the failed objective, the answers and the
## evidence, with Retry and Main menu.

const CARD_SCENE: PackedScene = preload("res://ui/mission_card.tscn")
const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const FIXTURE_ID: String = "m2_fixture"
const TEMP_DIR: String = "user://failed_card_test_scenarios"
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


func _card() -> MissionCard:
	var card: MissionCard = auto_free(CARD_SCENE.instantiate()) as MissionCard
	add_child(card)
	return card


func _main() -> Node:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	return main


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	return k


func _fail_once_and_show(card: MissionCard) -> void:
	if Sim.debrief_view() == null:
		_fail()
	assert_bool(card.show_debrief()).is_true()


func _fail() -> void:
	for wrong: String in ["Port scan", "Phishing", "SQL injection"]:
		Sim.submit_report("attack_type", wrong)


# --- the card ----------------------------------------------------------------------


func test_there_is_no_failed_card_during_play() -> void:
	var card: MissionCard = _card()
	Sim.submit_report("attack_type", "Port scan")
	assert_bool(card.show_debrief()).is_false()
	assert_bool(card.is_open()).is_false()


func test_failed_card_names_the_failed_objective_and_the_answers() -> void:
	var card: MissionCard = _card()
	Sim.submit_report("attacker_ip", "198.51.100.7")
	_fail()
	assert_bool(card.show_debrief()).is_true()
	assert_int(card.kind()).is_equal(MissionCard.Kind.FAILED)
	assert_str(card.label_text()).is_equal("TICKET FAILED")
	assert_str(card.button_text()).is_equal("Retry")
	assert_str(card.secondary_button_text()).is_equal("Main menu")
	assert_str(card.results_text()).contains("[!] Report the attack type")
	assert_str(card.results_text()).contains("[ ] Report the attacker's IP")
	assert_str(card.body_text()).starts_with("Failed: Report the attack type")
	var report: String = card.report_block_text()
	assert_str(report).contains("Attacker IP\n  Answer: 203.0.113.45  (you filed: 198.51.100.7)")
	assert_str(report).contains("Attack type\n  Answer: Brute force  (you filed: SQL injection)")
	assert_str(report).contains("Compromised account\n  Answer: deploy  (not filed)")
	assert_str(report).contains("Evidence: WEB1 /var/log/auth.log line 1: 2026-03-14T02:11:05Z sshd[811]: Failed password")


func test_a_failed_card_does_not_use_the_resolved_green() -> void:
	var card: MissionCard = _card()
	_fail()
	card.show_debrief()
	var results: Label = card.find_children("*", "Label", true, false).filter(
		func(l: Label) -> bool: return l.text.begins_with("[")
	)[0]
	assert_bool(results.get_theme_color("font_color") == MissionCard.PASSED_INK).is_false()


func test_report_text_golden() -> void:
	var fields: Array[Dictionary] = [
		{"id": "a", "label": "Attacker IP", "answer": "1.2.3.4", "last_value": "", "solved": true,
			"evidence": [{"source": "WEB1", "file": "/var/log/auth.log", "line": 3, "text": "bad login"}]},
		{"id": "b", "label": "Type", "answer": "Brute force", "last_value": "Phishing", "solved": false,
			"evidence": []},
	]
	assert_str(MissionCard.report_text(fields)).is_equal("\n".join([
		"Attacker IP",
		"  Answer: 1.2.3.4  (solved)",
		"  Evidence: WEB1 /var/log/auth.log line 3: bad login",
		"",
		"Type",
		"  Answer: Brute force  (you filed: Phishing)",
	]))
	assert_str(MissionCard.report_text([])).is_empty()


func test_a_card_without_a_report_hides_the_answers_block() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	var card: MissionCard = _card()
	card.show_briefing()
	assert_str(card.report_block_text()).is_empty()
	assert_str(card.secondary_button_text()).is_empty()


func test_escape_does_not_dismiss_it_and_enter_retries() -> void:
	var card: MissionCard = _card()
	var asked: Array[String] = []
	card.retry_requested.connect(func() -> void: asked.append("retry"))
	card.menu_requested.connect(func() -> void: asked.append("menu"))
	_fail()
	card.show_debrief()
	card._input(_key(KEY_ESCAPE))
	assert_bool(card.is_open()).is_true()
	assert_array(asked).is_empty()
	card._input(_key(KEY_ENTER))
	assert_bool(card.is_open()).is_false()
	assert_array(asked).is_equal(["retry"])


func test_the_failed_card_lets_focus_keys_through_and_blocks_the_rest() -> void:
	for code: Key in MissionCard.FOCUS_KEYS:
		assert_bool(MissionCard.blocks_key(MissionCard.Kind.FAILED, code)).is_false()
		# The other cards still swallow everything.
		assert_bool(MissionCard.blocks_key(MissionCard.Kind.BRIEFING, code)).is_true()
		assert_bool(MissionCard.blocks_key(MissionCard.Kind.DEBRIEF, code)).is_true()
	for code: Key in [KEY_W, KEY_ENTER, KEY_ESCAPE, KEY_SPACE, KEY_E]:
		assert_bool(MissionCard.blocks_key(MissionCard.Kind.FAILED, code)).is_true()


func test_enter_and_space_pick_the_button_with_focus() -> void:
	var card: MissionCard = _card()
	var asked: Array[String] = []
	card.retry_requested.connect(func() -> void: asked.append("retry"))
	card.menu_requested.connect(func() -> void: asked.append("menu"))
	for press: Key in [KEY_ENTER, KEY_SPACE]:
		_fail_once_and_show(card)
		var buttons: Array[Node] = card.find_children("*", "Button", true, false)
		(buttons[1] as Button).grab_focus()
		card._input(_key(press))
		assert_bool(card.is_open()).is_false()
	assert_array(asked).is_equal(["menu", "menu"])
	for press: Key in [KEY_ENTER, KEY_SPACE]:
		_fail_once_and_show(card)
		var buttons: Array[Node] = card.find_children("*", "Button", true, false)
		(buttons[0] as Button).grab_focus()
		card._input(_key(press))
	assert_array(asked).is_equal(["menu", "menu", "retry", "retry"])


func test_the_buttons_ask_for_retry_and_the_menu() -> void:
	var card: MissionCard = _card()
	var asked: Array[String] = []
	card.retry_requested.connect(func() -> void: asked.append("retry"))
	card.menu_requested.connect(func() -> void: asked.append("menu"))
	_fail()
	card.show_debrief()
	var buttons: Array[Node] = card.find_children("*", "Button", true, false)
	(buttons[1] as Button).pressed.emit()
	assert_array(asked).is_equal(["menu"])
	assert_bool(card.is_open()).is_false()
	card.show_debrief()
	(buttons[0] as Button).pressed.emit()
	assert_array(asked).is_equal(["menu", "retry"])


# --- in the game -------------------------------------------------------------------


func test_failing_from_the_report_form_stops_play_and_shows_the_card() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	var form: ReportForm = main.get_node("ReportForm") as ReportForm
	card.close()
	form.open()
	for wrong: String in ["Port scan", "Phishing", "SQL injection"]:
		form.set_value("attack_type", wrong)
		form.submit("attack_type")
	assert_bool(form.is_open()).is_false()
	assert_int(card.kind()).is_equal(MissionCard.Kind.FAILED)
	assert_bool((main.get_node("MissionHUD") as CanvasLayer).visible).is_true()


func test_retry_reloads_the_mission_from_its_start() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	card.close()
	Sim.submit_report("attacker_ip", "203.0.113.45")
	_fail()
	assert_int(card.kind()).is_equal(MissionCard.Kind.FAILED)
	card._input(_key(KEY_ENTER))
	assert_object(Sim.debrief_view()).is_null()
	assert_int(Sim.report_view().attempts_left("attack_type")).is_equal(3)
	assert_bool(Sim.report_view().solved("attacker_ip")).is_false()
	assert_int(card.kind()).is_equal(MissionCard.Kind.BRIEFING)


func test_main_menu_choice_asks_main_for_the_menu() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	card.close()
	var asked: Array[int] = [0]
	main.menu_requested.connect(func() -> void: asked[0] += 1)
	_fail()
	(card.find_children("*", "Button", true, false)[1] as Button).pressed.emit()
	assert_int(asked[0]).is_equal(1)


func test_an_open_debrief_wait_is_dropped_when_the_mission_fails() -> void:
	# A mission that fails shows its card at once, even with the terminal open.
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	var terminal: Terminal = main.get_node("Terminal") as Terminal
	card.close()
	assert_bool(terminal.open("WEB1")).is_true()
	_fail()
	assert_bool(terminal.is_open()).is_false()
	assert_int(card.kind()).is_equal(MissionCard.Kind.FAILED)
