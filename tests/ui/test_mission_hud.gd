class_name TestMissionHud
extends GdUnitTestSuite

const HUD_SCENE: PackedScene = preload("res://ui/mission_hud.tscn")
const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const MISSION: String = "m1_vlan_ping"
const TEMP_DIR: String = "user://mission_hud_test_scenarios"
const UNREACHABLE_HINT: String = "Is anything answering at the gateway address?"


func before_test() -> void:
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()


func after_test() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	Sim.load_scenario_id(MISSION)
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		for name: String in DirAccess.get_files_at(TEMP_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEMP_DIR, name])


func _hud() -> MissionHud:
	var hud: MissionHud = auto_free(HUD_SCENE.instantiate()) as MissionHud
	add_child(hud)
	return hud


func _run(device_id: String, commands: Array[String]) -> void:
	var session: CliSession = Sim.open_session(device_id)
	for line in commands:
		assert_bool(session.submit(line).ok).override_failure_message(line).is_true()


func _make_trunk() -> void:
	_run("S1", ["enable", "configure terminal", "interface gi0/1", "switchport mode trunk", "end"])


## M1 with the ping step ordered after the trunk step, and a hint for the
## reason the ping fails with at the start.
func _load_ordered_with_hint() -> void:
	var text: String = FileAccess.get_file_as_string("%s/%s.json" % [Sim.SCENARIO_DIR, MISSION])
	var data: Dictionary = JSON.parse_string(text)
	for obj: Dictionary in data["objectives"]:
		if obj["id"] == "trunk":
			obj["order"] = 1
		elif obj["id"] == "ping_ab":
			obj["order"] = 2
	data["hints"].append({"reason": "HOST_UNREACHABLE", "text": UNREACHABLE_HINT})
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEMP_DIR, MISSION], FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	Sim.scenario_dir = TEMP_DIR
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()


func _state(description: String) -> ObjectiveState:
	var s := ObjectiveState.new()
	s.description = description
	return s


func _action(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


# --- line text and colour -----------------------------------------------------------


func test_line_text_for_each_status() -> void:
	var s: ObjectiveState = _state("S1 Gi0/1 is a trunk")
	assert_str(MissionHud.line_text(s)).is_equal("[ ] S1 Gi0/1 is a trunk")
	assert_that(MissionHud.line_color(s)).is_equal(MissionHud.TEXT_COLOR)

	s.detail = "reached, but not through R1"
	assert_str(MissionHud.line_text(s)).is_equal("[ ] S1 Gi0/1 is a trunk (reached, but not through R1)")

	s.passed = true
	assert_str(MissionHud.line_text(s)).is_equal("[x] S1 Gi0/1 is a trunk")
	assert_that(MissionHud.line_color(s)).is_equal(MissionHud.PASSED_COLOR)

	s.passed = false
	s.failed = true
	assert_str(MissionHud.line_text(s)).is_equal("[!] S1 Gi0/1 is a trunk (reached, but not through R1)")
	assert_that(MissionHud.line_color(s)).is_equal(MissionHud.FAILED_COLOR)


func test_locked_line_is_a_greyed_next_step_without_detail() -> void:
	var s: ObjectiveState = _state("PC-A can ping PC-B")
	s.locked = true
	s.detail = "locked until the earlier steps pass"
	assert_str(MissionHud.line_text(s)).is_equal("[ ] Next step: PC-A can ping PC-B")
	assert_that(MissionHud.line_color(s)).is_equal(MissionHud.LOCKED_COLOR)


# --- hint choice --------------------------------------------------------------------


func test_hint_is_from_the_first_failing_unlocked_objective_that_has_one() -> void:
	var passed: ObjectiveState = _state("a")
	passed.passed = true
	passed.hint = "never shown: passed"
	var locked: ObjectiveState = _state("b")
	locked.locked = true
	locked.hint = "never shown: locked"
	var no_hint: ObjectiveState = _state("c")
	var first: ObjectiveState = _state("d")
	first.hint = "first"
	var second: ObjectiveState = _state("e")
	second.hint = "second"
	var states: Array[ObjectiveState] = [passed, locked, no_hint, first, second]
	assert_str(MissionHud.hint_for(states)).is_equal("first")


func test_hint_falls_back_when_none_applies() -> void:
	var open: ObjectiveState = _state("a")
	var locked: ObjectiveState = _state("b")
	locked.locked = true
	locked.hint = "never shown: locked"
	assert_str(MissionHud.hint_for([open, locked] as Array[ObjectiveState])).is_equal(MissionHud.NO_HINT)

	var done: ObjectiveState = _state("c")
	done.passed = true
	assert_str(MissionHud.hint_for([done] as Array[ObjectiveState])).is_equal(MissionHud.ALL_DONE)
	assert_str(MissionHud.hint_for([] as Array[ObjectiveState])).is_equal(MissionHud.NO_HINT)


# --- the HUD in M1 ------------------------------------------------------------------


func test_shows_m1_objectives_spare_cables_and_prompt() -> void:
	var hud: MissionHud = _hud()
	assert_str(hud.title_text()).is_equal("Day One: Get Them Talking")
	assert_array(Array(hud.objective_lines())).is_equal([
		"[ ] PC-A can ping PC-B through the router",
		"[ ] S1 Gi0/1 is a trunk",
		"[ ] Gi0/0.10 is VLAN 10's gateway (192.168.10.1/24)",
		"[ ] Gi0/0.20 is VLAN 20's gateway (192.168.20.1/24)",
		"[x] Gi0/0 itself has no IP address",
	])
	assert_that(hud.objective_colors()[4]).is_equal(MissionHud.PASSED_COLOR)
	assert_str(hud.spare_text()).is_equal("Spare cables: 1")
	assert_str(hud.prompt_text()).is_equal("H hint · Tab objectives")
	assert_bool(hud.is_hint_shown()).is_false()
	assert_str(hud.hint_text()).is_empty()


func test_ticks_and_spare_count_update_live() -> void:
	var hud: MissionHud = _hud()
	_make_trunk()
	assert_str(hud.objective_lines()[1]).is_equal("[x] S1 Gi0/1 is a trunk")
	assert_that(hud.objective_colors()[1]).is_equal(MissionHud.PASSED_COLOR)

	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	assert_str(hud.spare_text()).is_equal("Spare cables: 0")
	assert_bool(Sim.disconnect_link("PC-B:Eth0").ok).is_true()
	assert_str(hud.spare_text()).is_equal("Spare cables: 1")


func test_the_solution_ticks_every_objective() -> void:
	var hud: MissionHud = _hud()
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	_run("S1", [
		"enable", "configure terminal", "vlan 20", "name SALES", "exit",
		"interface fa0/2", "switchport mode access", "switchport access vlan 20", "exit",
		"interface gi0/1", "switchport mode trunk", "end",
	])
	_run("R1", [
		"enable", "configure terminal", "interface gi0/0", "no shutdown", "exit",
		"interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
		"interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end",
	])
	for line: String in hud.objective_lines():
		assert_str(line).starts_with("[x] ")
	hud.toggle_hint()
	assert_str(hud.hint_text()).is_equal(MissionHud.ALL_DONE)


# --- locked steps and hints ---------------------------------------------------------


func test_locked_step_is_greyed_until_the_earlier_step_passes() -> void:
	_load_ordered_with_hint()
	var hud: MissionHud = _hud()
	assert_str(hud.objective_lines()[0]).is_equal("[ ] Next step: PC-A can ping PC-B through the router")
	assert_that(hud.objective_colors()[0]).is_equal(MissionHud.LOCKED_COLOR)

	_make_trunk()
	assert_str(hud.objective_lines()[0]).is_equal("[ ] PC-A can ping PC-B through the router")
	assert_that(hud.objective_colors()[0]).is_equal(MissionHud.TEXT_COLOR)


func test_hint_shows_only_when_asked_and_hides_when_it_no_longer_applies() -> void:
	_load_ordered_with_hint()
	var hud: MissionHud = _hud()
	assert_str(hud.hint_text()).is_empty()

	# The ping step is locked, so its hint is withheld.
	hud.toggle_hint()
	assert_str(hud.hint_text()).is_equal(MissionHud.NO_HINT)

	# Unlocking the ping step changes which hint applies: the old one goes away
	# and the new one waits for another press.
	_make_trunk()
	assert_bool(hud.is_hint_shown()).is_false()
	assert_str(hud.hint_text()).is_empty()

	hud.toggle_hint()
	assert_str(hud.hint_text()).is_equal(UNREACHABLE_HINT)

	# A change that leaves the same hint in place keeps it on screen.
	_run("R1", ["enable", "configure terminal", "hostname Edge", "end"])
	assert_str(hud.hint_text()).is_equal(UNREACHABLE_HINT)

	hud.toggle_hint()
	assert_str(hud.hint_text()).is_empty()


func test_hint_and_objectives_keys() -> void:
	_load_ordered_with_hint()
	var hud: MissionHud = _hud()
	_make_trunk()
	hud._unhandled_input(_action("hint"))
	assert_str(hud.hint_text()).is_equal(UNREACHABLE_HINT)
	hud._unhandled_input(_action("toggle_objectives"))
	assert_bool(hud.objectives_visible()).is_false()
	hud._unhandled_input(_action("toggle_objectives"))
	assert_bool(hud.objectives_visible()).is_true()

	hud.hide()
	hud._unhandled_input(_action("hint"))
	assert_bool(hud.is_hint_shown()).is_true()


func test_loading_a_scenario_resets_hint_and_list() -> void:
	var hud: MissionHud = _hud()
	hud.toggle_hint()
	hud.toggle_objectives()
	_load_ordered_with_hint()
	assert_bool(hud.is_hint_shown()).is_false()
	assert_str(hud.hint_text()).is_empty()
	assert_bool(hud.objectives_visible()).is_true()
	assert_str(hud.objective_lines()[0]).starts_with("[ ] Next step: ")


# --- in the main scene --------------------------------------------------------------


func test_hud_hides_while_the_terminal_is_open() -> void:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	var hud: MissionHud = main.get_node("MissionHUD") as MissionHud
	var term: Terminal = main.get_node("Terminal") as Terminal
	assert_bool(hud.visible).is_true()
	assert_bool(term.open("R1")).is_true()
	assert_bool(hud.visible).is_false()
	term.close()
	assert_bool(hud.visible).is_true()
