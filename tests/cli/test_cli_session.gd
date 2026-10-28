class_name TestCliSession
extends GdUnitTestSuite

const USER: CliMode.Id = CliMode.Id.USER_EXEC
const PRIV: CliMode.Id = CliMode.Id.PRIV_EXEC
const GLOBAL: CliMode.Id = CliMode.Id.GLOBAL_CONFIG
const IFACE: CliMode.Id = CliMode.Id.INTERFACE_CONFIG
const VLAN: CliMode.Id = CliMode.Id.VLAN_CONFIG
const LINE: CliMode.Id = CliMode.Id.LINE_CONFIG

var _topo: TopoBuilder
var _router: Device
var _reg: CommandRegistry
var _s: CliSession


func _ok(text: String = "") -> CliResult:
	return CliResult.ok_output(text)


## Stand-in context-entering commands keep these tests about the session alone;
## the real ones (IosCommands) are tested in test_ios_commands.gd.
func before_test() -> void:
	_topo = TopoBuilder.new()
	_router = _topo.add("router_2port", "R1")
	_reg = CommandRegistry.new()
	CliSession.register_core(_reg)
	_reg.register(GLOBAL, "interface <interface>", func(ctx: CliSession, args: Array, _n: bool) -> CliResult:
		ctx.enter_interface(args[0])
		return _ok())
	_reg.register(GLOBAL, "vlan <vlan-id>", func(ctx: CliSession, args: Array, _n: bool) -> CliResult:
		ctx.enter_vlan(args[0])
		return _ok())
	_reg.register(GLOBAL, "line vty <line-range>", func(ctx: CliSession, args: Array, _n: bool) -> CliResult:
		var r: Vector2i = args[0]
		ctx.enter_line("vty %d %d" % [r.x, r.y])
		return _ok())
	_reg.register(GLOBAL, "hostname <word>", func(_ctx: CliSession, args: Array, _n: bool) -> CliResult:
		_router.hostname = args[0]
		return _ok())
	_s = CliSession.new(_topo.sim, "R1", _reg)


func _run(line: String) -> CliResult:
	return _s.submit(line)


func _to_global() -> void:
	_run("enable")
	_run("configure terminal")


# --- prompts and transitions ------------------------------------------------


func test_starts_in_user_exec() -> void:
	assert_int(_s.mode()).is_equal(USER)
	assert_str(_s.prompt()).is_equal("R1>")
	assert_bool(_s.is_password_prompt()).is_false()


func test_every_mode_transition_and_prompt() -> void:
	var steps: Array = [
		["enable", PRIV, "R1#"],
		["configure terminal", GLOBAL, "R1(config)#"],
		["interface g0/1", IFACE, "R1(config-if)#"],
		["exit", GLOBAL, "R1(config)#"],
		["vlan 10", VLAN, "R1(config-vlan)#"],
		["exit", GLOBAL, "R1(config)#"],
		["line vty 0 4", LINE, "R1(config-line)#"],
		["exit", GLOBAL, "R1(config)#"],
		["exit", PRIV, "R1#"],
		["disable", USER, "R1>"],
	]
	for step: Array in steps:
		var r: CliResult = _run(step[0])
		assert_bool(r.ok).override_failure_message("'%s' failed: %s" % [step[0], r.output]).is_true()
		assert_int(_s.mode()).override_failure_message("after '%s'" % step[0]).is_equal(step[1])
		assert_str(_s.prompt()).override_failure_message("after '%s'" % step[0]).is_equal(step[2])


func test_abbreviated_transitions() -> void:
	_run("en")
	_run("conf t")
	_run("int g0/1")
	assert_int(_s.mode()).is_equal(IFACE)
	_run("ex")
	_run("end")
	assert_int(_s.mode()).is_equal(PRIV)


func test_configure_terminal_prints_the_ios_banner() -> void:
	_run("enable")
	assert_str(_run("configure terminal").output).is_equal("Enter configuration commands, one per line.  End with CNTL/Z.")


func test_end_returns_to_priv_exec_from_every_config_mode() -> void:
	for entry: String in ["interface g0/1", "vlan 10", "line vty 0 4"]:
		_to_global()
		_run(entry)
		var r: CliResult = _run("end")
		assert_bool(r.ok).is_true()
		assert_int(_s.mode()).is_equal(PRIV)
		assert_array(_s.mode_stack()).is_equal([PRIV])
	_to_global()
	_run("end")
	assert_int(_s.mode()).is_equal(PRIV)


func test_end_is_invalid_in_exec_modes() -> void:
	assert_bool(_run("end").ok).is_false()
	_run("enable")
	assert_bool(_run("end").ok).is_false()
	assert_int(_s.mode()).is_equal(PRIV)


func test_exit_closes_the_session_from_exec_modes() -> void:
	var r: CliResult = _run("exit")
	assert_int(r.action).is_equal(CliResult.ShellAction.CLOSE_SESSION)
	_run("enable")
	r = _run("exit")
	assert_int(r.action).is_equal(CliResult.ShellAction.CLOSE_SESSION)


func test_exit_in_config_modes_does_not_close() -> void:
	_to_global()
	_run("interface g0/1")
	assert_int(_run("exit").action).is_equal(CliResult.ShellAction.NONE)
	assert_int(_run("exit").action).is_equal(CliResult.ShellAction.NONE)
	assert_int(_s.mode()).is_equal(PRIV)


func test_disable_and_enable_only_move_between_exec_modes() -> void:
	_run("enable")
	assert_bool(_run("enable").ok).is_true()
	assert_int(_s.mode()).is_equal(PRIV)
	_run("disable")
	assert_int(_s.mode()).is_equal(USER)
	assert_bool(_run("disable").ok).is_false()
	_to_global()
	assert_bool(_run("disable").ok).is_false()
	assert_int(_s.mode()).is_equal(GLOBAL)


func test_configure_terminal_needs_priv_exec() -> void:
	var r: CliResult = _run("conf t")
	assert_bool(r.ok).is_false()
	# The ^ is shifted by the prompt width ("R1>" is 3 columns).
	assert_str(r.output).is_equal("   ^\n% Invalid input detected at '^' marker.")
	assert_int(_s.mode()).is_equal(USER)


# --- context ----------------------------------------------------------------


func test_interface_context_is_canonical() -> void:
	_to_global()
	_run("interface g0/1")
	assert_str(_s.context_interface()).is_equal("GigabitEthernet0/1")
	_run("exit")
	assert_str(_s.context_interface()).is_equal("")


func test_vlan_and_line_context() -> void:
	_to_global()
	_run("vlan 10")
	assert_int(_s.context_vlan()).is_equal(10)
	_run("exit")
	assert_int(_s.context_vlan()).is_equal(0)
	_run("line vty 0 4")
	assert_str(_s.context_line()).is_equal("vty 0 4")


func test_global_command_in_a_sub_mode_switches_context() -> void:
	_to_global()
	_run("interface g0/1")
	_run("interface g0/0")
	assert_int(_s.mode()).is_equal(IFACE)
	assert_str(_s.context_interface()).is_equal("GigabitEthernet0/0")
	assert_array(_s.mode_stack()).is_equal([PRIV, GLOBAL, IFACE])
	_run("vlan 20")
	assert_int(_s.mode()).is_equal(VLAN)
	assert_int(_s.context_vlan()).is_equal(20)
	assert_str(_s.context_interface()).is_equal("")
	assert_array(_s.mode_stack()).is_equal([PRIV, GLOBAL, VLAN])
	_run("exit")
	assert_array(_s.mode_stack()).is_equal([PRIV, GLOBAL])


func test_global_command_that_enters_no_mode_keeps_the_sub_mode() -> void:
	_to_global()
	_run("interface g0/1")
	_run("hostname Core")
	assert_int(_s.mode()).is_equal(IFACE)
	assert_str(_s.context_interface()).is_equal("GigabitEthernet0/1")
	assert_str(_s.prompt()).is_equal("Core(config-if)#")


func test_subinterface_prompt() -> void:
	_to_global()
	_run("interface g0/0.10")
	assert_str(_s.prompt()).is_equal("R1(config-subif)#")
	assert_int(_s.mode()).is_equal(IFACE)


func test_prompt_follows_the_live_hostname() -> void:
	_to_global()
	assert_str(_s.prompt()).is_equal("R1(config)#")
	_run("hostname Edge-RTR")
	assert_str(_s.prompt()).is_equal("Edge-RTR(config)#")
	_run("end")
	assert_str(_s.prompt()).is_equal("Edge-RTR#")
	_run("disable")
	assert_str(_s.prompt()).is_equal("Edge-RTR>")


func test_errors_use_the_current_prompt_width() -> void:
	_to_global()
	_run("hostname Edge-RTR")
	var r: CliResult = _run("bogus")
	assert_str(r.output).is_equal(" ".repeat("Edge-RTR(config)#".length()) + "^\n% Invalid input detected at '^' marker.")


# --- enable password ----------------------------------------------------------


func test_enable_without_a_secret_goes_straight_to_priv() -> void:
	_run("enable")
	assert_int(_s.mode()).is_equal(PRIV)
	assert_bool(_s.is_password_prompt()).is_false()


func test_enable_with_a_secret_asks_for_the_password() -> void:
	_router.enable_secret = "cisco123"
	var r: CliResult = _run("enable")
	assert_bool(r.ok).is_true()
	assert_bool(_s.is_password_prompt()).is_true()
	assert_str(_s.prompt()).is_equal("Password:")
	assert_int(_s.mode()).is_equal(USER)
	r = _run("cisco123")
	assert_bool(r.ok).is_true()
	assert_bool(_s.is_password_prompt()).is_false()
	assert_int(_s.mode()).is_equal(PRIV)
	assert_str(_s.prompt()).is_equal("R1#")


func test_wrong_password_reprompts_then_gives_up_after_three() -> void:
	_router.enable_secret = "cisco123"
	_run("enable")
	assert_str(_run("wrong1").output).is_empty()
	assert_bool(_s.is_password_prompt()).is_true()
	assert_str(_run("wrong2").output).is_empty()
	assert_bool(_s.is_password_prompt()).is_true()
	var r: CliResult = _run("wrong3")
	assert_bool(r.ok).is_false()
	assert_str(r.output).is_equal("% Bad secrets")
	assert_bool(_s.is_password_prompt()).is_false()
	assert_int(_s.mode()).is_equal(USER)
	assert_str(_s.prompt()).is_equal("R1>")


func test_password_attempts_reset_on_the_next_enable() -> void:
	_router.enable_secret = "cisco123"
	_run("enable")
	_run("a")
	_run("b")
	_run("c")
	_run("enable")
	_run("a")
	_run("cisco123")
	assert_int(_s.mode()).is_equal(PRIV)


func test_password_is_checked_exactly_and_is_not_a_command() -> void:
	_router.enable_secret = "disable"
	_run("enable")
	_run("Disable")
	assert_bool(_s.is_password_prompt()).is_true()
	_run("disable")
	assert_int(_s.mode()).is_equal(PRIV)


func test_priv_exec_does_not_ask_again() -> void:
	_run("enable")
	_router.enable_secret = "x"
	_run("enable")
	assert_bool(_s.is_password_prompt()).is_false()
	assert_int(_s.mode()).is_equal(PRIV)


# --- Ctrl+Z -------------------------------------------------------------------


func test_ctrl_z_acts_as_end() -> void:
	_to_global()
	_run("interface g0/1")
	var r: CliResult = _s.ctrl_z()
	assert_bool(r.ok).is_true()
	assert_int(_s.mode()).is_equal(PRIV)


func test_ctrl_z_in_exec_modes_does_nothing() -> void:
	var r: CliResult = _s.ctrl_z()
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_empty()
	assert_int(_s.mode()).is_equal(USER)
	_run("enable")
	_s.ctrl_z()
	assert_int(_s.mode()).is_equal(PRIV)


# --- history ------------------------------------------------------------------


func test_history_records_commands_in_order() -> void:
	_run("enable")
	_run("configure terminal")
	_run("hostname A")
	assert_array(_s.history()).is_equal(["enable", "configure terminal", "hostname A"])


func test_history_skips_blank_and_consecutive_duplicates() -> void:
	_run("enable")
	_run("")
	_run("   ")
	_run("enable")
	_run("disable")
	_run("enable")
	assert_array(_s.history()).is_equal(["enable", "disable", "enable"])


func test_history_records_failed_commands_too() -> void:
	_run("bogus")
	assert_array(_s.history()).is_equal(["bogus"])


func test_history_up_and_down() -> void:
	_run("enable")
	_run("configure terminal")
	_run("hostname A")
	assert_str(_s.history_prev()).is_equal("hostname A")
	assert_str(_s.history_prev()).is_equal("configure terminal")
	assert_str(_s.history_prev()).is_equal("enable")
	assert_str(_s.history_prev()).is_equal("enable")
	assert_str(_s.history_next()).is_equal("configure terminal")
	assert_str(_s.history_next()).is_equal("hostname A")
	assert_str(_s.history_next()).is_equal("")
	assert_str(_s.history_next()).is_equal("")


func test_history_navigation_with_nothing_recorded() -> void:
	assert_str(_s.history_prev()).is_equal("")
	assert_str(_s.history_next()).is_equal("")


func test_history_cursor_resets_after_a_command() -> void:
	_run("enable")
	_run("configure terminal")
	_s.history_prev()
	_s.history_prev()
	_run("hostname A")
	assert_str(_s.history_prev()).is_equal("hostname A")


func test_history_is_capped() -> void:
	_run("enable")
	_run("configure terminal")
	for i in CliSession.HISTORY_MAX + 5:
		_run("hostname H%d" % i)
	assert_int(_s.history().size()).is_equal(CliSession.HISTORY_MAX)
	assert_str(_s.history()[CliSession.HISTORY_MAX - 1]).is_equal("hostname H%d" % (CliSession.HISTORY_MAX + 4))


func test_passwords_are_not_recorded() -> void:
	_router.enable_secret = "cisco123"
	_run("enable")
	_run("cisco123")
	assert_array(_s.history()).is_equal(["enable"])


# --- help and Tab -------------------------------------------------------------


func test_help_and_complete_use_the_current_mode() -> void:
	assert_str(_s.complete("en")).is_equal("enable ")
	assert_str(_s.complete("conf")).is_equal("conf")
	_run("enable")
	assert_str(_s.complete("conf")).is_equal("configure ")
	assert_str(_s.help("configure ")).is_equal("  terminal  Configure from the terminal")
	_to_global()
	assert_str(_s.help("h")).is_equal("hostname")


func test_help_and_complete_are_inert_at_the_password_prompt() -> void:
	_router.enable_secret = "x"
	_run("enable")
	assert_str(_s.help("")).is_empty()
	assert_str(_s.complete("en")).is_equal("en")
