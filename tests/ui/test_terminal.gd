class_name TestTerminal
extends GdUnitTestSuite

const TERMINAL_SCENE: PackedScene = preload("res://ui/terminal/terminal.tscn")
const MISSION: String = "m1_vlan_ping"
const TEMP_DIR: String = "user://terminal_test_scenarios"


func before_test() -> void:
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()


func after_test() -> void:
	Sim.scenario_dir = Sim.SCENARIO_DIR
	Sim.load_scenario_id(MISSION)
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		for name: String in DirAccess.get_files_at(TEMP_DIR):
			DirAccess.remove_absolute("%s/%s" % [TEMP_DIR, name])


func _terminal(reveal: bool = false) -> Terminal:
	var term: Terminal = auto_free(TERMINAL_SCENE.instantiate()) as Terminal
	add_child(term)
	term.reveal_enabled = reveal
	return term


func _key(code: Key, unicode: int = 0, ctrl: bool = false) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.unicode = unicode
	k.ctrl_pressed = ctrl
	return k


func _lines(term: Terminal) -> PackedStringArray:
	return term.transcript().split("\n")


# --- opening and closing ----------------------------------------------------------


func test_starts_hidden_and_closed() -> void:
	var term: Terminal = _terminal()
	assert_bool(term.visible).is_false()
	assert_bool(term.is_open()).is_false()


func test_open_shows_hostname_and_prompt() -> void:
	var term: Terminal = _terminal()
	var signals: Array[String] = []
	term.opened.connect(func(id: String) -> void: signals.append(id))
	assert_bool(term.open("R1")).is_true()
	assert_bool(term.visible).is_true()
	assert_bool(term.is_open()).is_true()
	assert_str(term.device_id()).is_equal("R1")
	assert_str(term.title_text()).is_equal("Router  ·  R1")
	assert_str(term.prompt_text()).is_equal("Router>")
	assert_str(term.transcript()).is_empty()
	assert_array(signals).is_equal(["R1"])


func test_pc_opens_the_windows_shell() -> void:
	var term: Terminal = _terminal()
	assert_bool(term.open("PC-A")).is_true()
	assert_str(term.title_text()).is_equal("PC-A")
	assert_str(term.prompt_text()).is_equal("C:\\>")


func test_unknown_device_stays_closed() -> void:
	var term: Terminal = _terminal()
	assert_bool(term.open("nope")).is_false()
	assert_bool(term.visible).is_false()


func test_escape_closes() -> void:
	var term: Terminal = _terminal()
	var closed: Array[bool] = []
	term.closed.connect(func() -> void: closed.append(true))
	term.open("R1")
	assert_bool(term.handle_key(_key(KEY_ESCAPE))).is_true()
	assert_bool(term.visible).is_false()
	assert_bool(term.is_open()).is_false()
	assert_array(closed).has_size(1)


func test_exit_from_exec_closes_the_session() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("exit")
	assert_bool(term.is_open()).is_false()
	assert_bool(term.visible).is_false()


func test_pc_exit_closes_too() -> void:
	var term: Terminal = _terminal()
	term.open("PC-A")
	term.submit_line("exit")
	assert_bool(term.is_open()).is_false()


func test_reopening_starts_a_fresh_session() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	term.close()
	term.open("R1")
	assert_str(term.prompt_text()).is_equal("Router>")
	assert_str(term.transcript()).is_empty()


func test_loading_a_scenario_closes_the_terminal() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	Sim.load_scenario_id(MISSION)
	assert_bool(term.is_open()).is_false()


# --- typing -----------------------------------------------------------------------


func test_enter_echoes_the_line_and_updates_the_prompt() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.set_input_text("en")
	term.handle_key(_key(KEY_ENTER))
	assert_str(term.transcript()).is_equal("Router>en\n")
	assert_str(term.prompt_text()).is_equal("Router#")
	assert_str(term.input_text()).is_empty()


func test_output_follows_the_echo() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	term.submit_line("conf t")
	assert_str(term.transcript()).is_equal(
		"Router>enable\nRouter#conf t\nEnter configuration commands, one per line.  End with CNTL/Z.\n"
	)
	assert_str(term.prompt_text()).is_equal("Router(config)#")


func test_hostname_change_updates_title_and_prompt() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	for line: String in ["enable", "configure terminal", "hostname R1"]:
		term.submit_line(line)
	assert_str(term.prompt_text()).is_equal("R1(config)#")
	assert_str(term.title_text()).is_equal("R1")


func test_invalid_input_marker_sits_under_the_bad_word() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	term.submit_line("show bogus")
	var lines: PackedStringArray = _lines(term)
	assert_str(lines[1]).is_equal("Router#show bogus")
	assert_int(lines[2].find("^")).is_equal(lines[1].find("bogus"))


func test_up_and_down_walk_history() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	term.submit_line("show ip interface brief")
	term.handle_key(_key(KEY_UP))
	assert_str(term.input_text()).is_equal("show ip interface brief")
	term.handle_key(_key(KEY_UP))
	assert_str(term.input_text()).is_equal("enable")
	term.handle_key(_key(KEY_DOWN))
	assert_str(term.input_text()).is_equal("show ip interface brief")
	term.handle_key(_key(KEY_DOWN))
	assert_str(term.input_text()).is_empty()


func test_tab_completes_a_unique_prefix() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	term.set_input_text("conf")
	assert_bool(term.handle_key(_key(KEY_TAB))).is_true()
	assert_str(term.input_text()).is_equal("configure ")


func test_question_mark_prints_help_and_keeps_the_line() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	term.set_input_text("show ")
	assert_bool(term.handle_key(_key(KEY_SLASH, "?".unicode_at(0)))).is_true()
	var lines: PackedStringArray = _lines(term)
	assert_str(lines[1]).is_equal("Router#show ?")
	assert_str(term.transcript()).contains("ip")
	assert_str(term.input_text()).is_equal("show ")


func test_ctrl_z_ends_config_mode() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	for line: String in ["enable", "configure terminal", "interface g0/0"]:
		term.submit_line(line)
	term.set_input_text("desc")
	assert_bool(term.handle_key(_key(KEY_Z, 0, true))).is_true()
	assert_str(term.prompt_text()).is_equal("Router#")
	assert_str(term.transcript()).ends_with("Router(config-if)#desc^Z\n")
	assert_str(term.input_text()).is_empty()


func test_plain_letters_go_to_the_line_edit() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	assert_bool(term.handle_key(_key(KEY_A, "a".unicode_at(0)))).is_false()


func test_keys_reach_the_terminal_through_the_input_box() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	var input: LineEdit = term.find_child("Input", true, false) as LineEdit
	input.text = "enable"
	input.gui_input.emit(_key(KEY_ENTER))
	assert_str(term.prompt_text()).is_equal("Router#")


func test_config_change_through_the_terminal_reaches_the_sim() -> void:
	var term: Terminal = _terminal()
	term.open("R1")
	for line: String in ["enable", "conf t", "int g0/0", "no shutdown", "end"]:
		term.submit_line(line)
	assert_bool(Sim.device_view("R1").interface("Gi0/0")["admin_up"]).is_true()


# --- password prompt --------------------------------------------------------------


func _load_with_enable_secret(secret: String) -> void:
	var json := JSON.new()
	assert_int(json.parse(FileAccess.get_file_as_string("res://scenarios/%s.json" % MISSION))).is_equal(OK)
	var data: Dictionary = json.data
	for device: Dictionary in data["devices"]:
		if device["id"] == "R1":
			device["config"]["enable_secret"] = secret
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var file := FileAccess.open("%s/%s.json" % [TEMP_DIR, MISSION], FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	Sim.scenario_dir = TEMP_DIR
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()


func test_password_is_hidden_and_never_echoed() -> void:
	_load_with_enable_secret("class")
	var term: Terminal = _terminal()
	term.open("R1")
	term.submit_line("enable")
	assert_str(term.prompt_text()).is_equal("Password:")
	var input: LineEdit = term.find_child("Input", true, false) as LineEdit
	assert_bool(input.secret).is_true()
	# `?` is part of a password, not a help request, and history is off.
	assert_bool(term.handle_key(_key(KEY_SLASH, "?".unicode_at(0)))).is_false()
	assert_bool(term.handle_key(_key(KEY_UP))).is_false()
	term.submit_line("class")
	assert_str(term.transcript()).is_equal("Router>enable\nPassword:\n")
	assert_str(term.prompt_text()).is_equal("Router#")
	assert_bool(input.secret).is_false()


# --- ping reveal ------------------------------------------------------------------


func test_windows_ping_reveals_one_line_at_a_time() -> void:
	var term: Terminal = _terminal(true)
	term.open("PC-A")
	term.submit_line("ping 192.168.20.10")
	assert_bool(term.is_revealing()).is_true()
	assert_str(term.transcript()).is_equal("C:\\>ping 192.168.20.10\nPinging 192.168.20.10 with 32 bytes of data:")
	# Keys other than Esc wait for the reveal.
	term.set_input_text("ipconfig")
	assert_bool(term.handle_key(_key(KEY_ENTER))).is_true()
	assert_str(term.transcript()).not_contains("ipconfig")

	term._advance(TerminalReveal.WIN_TIMEOUT_DELAY)
	assert_int(term.transcript().count("Request timed out.")).is_equal(1)
	term._advance(TerminalReveal.WIN_TIMEOUT_DELAY * 3)
	assert_int(term.transcript().count("Request timed out.")).is_equal(4)
	assert_bool(term.is_revealing()).is_false()
	assert_str(term.transcript()).ends_with("Lost = 4 (100% loss),\n")


func test_ios_ping_reveals_one_mark_at_a_time() -> void:
	var term: Terminal = _terminal(true)
	term.open("R1")
	term.submit_line("enable")
	term.submit_line("ping 192.168.10.10")
	assert_bool(term.is_revealing()).is_true()
	assert_str(term.transcript()).ends_with("timeout is 2 seconds:\n")
	term._advance(TerminalReveal.IOS_TIMEOUT_DELAY)
	assert_str(term.transcript()).ends_with("seconds:\n.")
	term._advance(TerminalReveal.IOS_TIMEOUT_DELAY * 4)
	assert_bool(term.is_revealing()).is_false()
	assert_str(term.transcript()).ends_with("Success rate is 0 percent (0/5)\n")


func test_escape_during_reveal_closes() -> void:
	var term: Terminal = _terminal(true)
	term.open("PC-A")
	term.submit_line("ping 192.168.20.10")
	term.handle_key(_key(KEY_ESCAPE))
	assert_bool(term.is_open()).is_false()
	assert_bool(term.is_revealing()).is_false()
