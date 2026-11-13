class_name TestMissionCard
extends GdUnitTestSuite

const CARD_SCENE: PackedScene = preload("res://ui/mission_card.tscn")
const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const MISSION: String = "m1_vlan_ping"
const S1_FIX: Array[String] = [
	"enable", "configure terminal", "vlan 20", "name SALES", "exit",
	"interface fa0/2", "switchport mode access", "switchport access vlan 20", "exit",
	"interface gi0/1", "switchport mode trunk", "end",
]
const R1_FIX: Array[String] = [
	"enable", "configure terminal", "interface gi0/0", "no shutdown", "exit",
	"interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
	"interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end",
]


func before_test() -> void:
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()


func after_test() -> void:
	Sim.load_scenario_id(MISSION)


func _card() -> MissionCard:
	var card: MissionCard = auto_free(CARD_SCENE.instantiate()) as MissionCard
	add_child(card)
	return card


func _run(device_id: String, commands: Array[String]) -> void:
	var session: CliSession = Sim.open_session(device_id)
	for line in commands:
		assert_bool(session.submit(line).ok).override_failure_message(line).is_true()


## Everything but R1's commands, which the caller types.
func _solve_all_but_r1() -> void:
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	_run("S1", S1_FIX)


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	return k


# --- briefing -----------------------------------------------------------------------


func test_starts_hidden() -> void:
	var card: MissionCard = _card()
	assert_bool(card.visible).is_false()
	assert_bool(card.is_open()).is_false()
	assert_int(card.kind()).is_equal(MissionCard.Kind.NONE)


func test_briefing_shows_the_ticket() -> void:
	var card: MissionCard = _card()
	assert_bool(card.show_briefing()).is_true()
	assert_bool(card.visible).is_true()
	assert_int(card.kind()).is_equal(MissionCard.Kind.BRIEFING)
	assert_str(card.label_text()).is_equal("NEW TICKET")
	assert_str(card.heading_text()).is_equal("Day One: Get Them Talking")
	assert_str(card.body_text()).is_equal(Sim.scenario_view().briefing())
	assert_str(card.results_text()).is_empty()
	assert_str(card.button_text()).is_equal("Start")


# --- debrief ------------------------------------------------------------------------


func test_no_debrief_during_play() -> void:
	var card: MissionCard = _card()
	assert_bool(card.show_debrief()).is_false()
	assert_bool(card.visible).is_false()
	_solve_all_but_r1()
	assert_bool(card.show_debrief()).is_false()


func test_debrief_after_the_mission_is_completed() -> void:
	var card: MissionCard = _card()
	_solve_all_but_r1()
	_run("R1", R1_FIX)
	assert_bool(card.show_debrief()).is_true()
	assert_int(card.kind()).is_equal(MissionCard.Kind.DEBRIEF)
	assert_str(card.label_text()).is_equal("TICKET RESOLVED")
	assert_str(card.heading_text()).is_equal("Day One: Get Them Talking")
	assert_str(card.results_text()).is_equal("\n".join([
		"[x] PC-A can ping PC-B through the router",
		"[x] S1 Gi0/1 is a trunk",
		"[x] Gi0/0.10 is VLAN 10's gateway (192.168.10.1/24)",
		"[x] Gi0/0.20 is VLAN 20's gateway (192.168.20.1/24)",
		"[x] Gi0/0 itself has no IP address",
	]))
	assert_str(card.body_text()).is_equal(Sim.debrief_view().text())
	assert_str(card.body_text()).contains("switchport mode trunk")
	assert_str(card.button_text()).is_equal("Continue")


# --- closing ------------------------------------------------------------------------


func test_enter_escape_and_the_button_close_it() -> void:
	var card: MissionCard = _card()
	var closed: Array[MissionCard.Kind] = []
	card.closed.connect(func(k: MissionCard.Kind) -> void: closed.append(k))

	for close_with: Callable in [
		func() -> void: card._input(_key(KEY_ENTER)),
		func() -> void: card._input(_key(KEY_ESCAPE)),
		func() -> void: (card.find_children("*", "Button", true, false)[0] as Button).pressed.emit(),
	]:
		card.show_briefing()
		close_with.call()
		assert_bool(card.visible).is_false()
		assert_bool(card.is_open()).is_false()
	assert_array(closed).is_equal([
		MissionCard.Kind.BRIEFING, MissionCard.Kind.BRIEFING, MissionCard.Kind.BRIEFING,
	])


func test_other_keys_leave_it_open() -> void:
	var card: MissionCard = _card()
	card.show_briefing()
	card._input(_key(KEY_H))
	card._input(_key(KEY_TAB))
	assert_bool(card.is_open()).is_true()


func test_close_when_closed_does_nothing() -> void:
	var card: MissionCard = _card()
	var closed: Array[MissionCard.Kind] = []
	card.closed.connect(func(k: MissionCard.Kind) -> void: closed.append(k))
	card.close()
	assert_array(closed).is_empty()


# --- in the main scene --------------------------------------------------------------


func _main() -> Node:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	return main


func test_main_opens_with_the_briefing_and_reloads_show_it_again() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	assert_int(card.kind()).is_equal(MissionCard.Kind.BRIEFING)
	card.close()
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	assert_int(card.kind()).is_equal(MissionCard.Kind.BRIEFING)


func test_debrief_waits_for_the_terminal_to_close() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	var term: Terminal = main.get_node("Terminal") as Terminal
	term.reveal_enabled = false
	card.close()
	_solve_all_but_r1()

	assert_bool(term.open("R1")).is_true()
	for line in R1_FIX:
		term.submit_line(line)
	assert_object(Sim.debrief_view()).is_not_null()
	assert_bool(card.is_open()).is_false()

	term.close()
	assert_int(card.kind()).is_equal(MissionCard.Kind.DEBRIEF)


func test_debrief_shows_at_once_when_no_terminal_is_open() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	card.close()
	_run("R1", R1_FIX)
	_run("S1", S1_FIX)
	assert_bool(card.is_open()).is_false()
	# Plugging in PC-B is the last fix.
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	assert_int(card.kind()).is_equal(MissionCard.Kind.DEBRIEF)


func test_continue_on_the_debrief_asks_for_the_menu_but_start_does_not() -> void:
	var main: Node = _main()
	var card: MissionCard = main.get_node("MissionCard") as MissionCard
	var asked: Array[int] = [0]
	main.menu_requested.connect(func() -> void: asked[0] += 1)
	card.close()
	assert_int(asked[0]).is_equal(0)

	_run("R1", R1_FIX)
	_run("S1", S1_FIX)
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()
	assert_int(card.kind()).is_equal(MissionCard.Kind.DEBRIEF)
	card.close()
	assert_int(asked[0]).is_equal(1)
