class_name TestCommandRegistry
extends GdUnitTestSuite

const INVALID: String = "% Invalid input detected at '^' marker."
const INCOMPLETE: String = "% Incomplete command."
const UNRECOGNIZED: String = "% Unrecognized command"

const U: CliMode.Id = CliMode.Id.USER_EXEC
const P: CliMode.Id = CliMode.Id.PRIV_EXEC
const G: CliMode.Id = CliMode.Id.GLOBAL_CONFIG
const I: CliMode.Id = CliMode.Id.INTERFACE_CONFIG
const V: CliMode.Id = CliMode.Id.VLAN_CONFIG

var _reg: CommandRegistry
var _last: Dictionary = {}


func _h(tag: String) -> Callable:
	return func(ctx: Variant, args: Array, negated: bool) -> CliResult:
		_last = {"tag": tag, "ctx": ctx, "args": args, "negated": negated}
		return CliResult.ok_output(tag)


func _caret(col: int) -> String:
	return " ".repeat(col) + "^\n" + INVALID


func _run(mode: int, line: String) -> CliResult:
	_last = {}
	return _reg.execute(mode as CliMode.Id, line)


func before_test() -> void:
	_last = {}
	_reg = CommandRegistry.new()
	_reg.register(U, "enable", _h("enable"), "Turn on privileged commands")

	_reg.register(P, "disable", _h("disable"), "Turn off privileged commands")
	_reg.register(P, "configure terminal", _h("conf-t"), "Configure from the terminal")
	_reg.register(P, "copy running-config startup-config", _h("copy"), "Copy config to NVRAM")
	_reg.register(P, "ping <ipv4>", _h("ping"), "Target IP address")
	_reg.register(P, "show running-config", _h("show-run"), "Current operating configuration")
	_reg.register(P, "show interfaces", _h("show-int"), "Interface status and configuration")
	_reg.register(P, "show ip interface brief", _h("show-ip-brief"), "Brief summary of IP status and configuration")
	_reg.register(P, "show ip route", _h("show-ip-route"), "IP routing table")
	_reg.register(P, "show vlan brief", _h("show-vlan"), "VTP all VLAN status in brief")
	_reg.describe(P, "configure", "Enter configuration mode")
	_reg.describe(P, "copy", "Copy from one file to another")
	_reg.describe(P, "ping", "Send echo messages")
	_reg.describe(P, "show", "Show running system information")
	_reg.describe(P, "show ip", "IP information")
	_reg.describe(P, "show vlan", "VTP VLAN status")

	_reg.register(G, "hostname <word>", _h("hostname"), "This system's network name", true)
	_reg.register(G, "interface <interface>", _h("interface"), "Interface to configure")
	_reg.register(G, "vlan <vlan-id>", _h("vlan"), "ISL VLAN IDs 1-4094", true)
	_reg.register(G, "ip route <ipv4> <mask> <ipv4>", _h("ip-route"), "Forwarding router's address")
	_reg.describe(G, "hostname", "Set system's network name")
	_reg.describe(G, "vlan", "VLAN commands")

	_reg.register(I, "shutdown", _h("shutdown"), "Shutdown the selected interface", true)
	_reg.register(I, "ip address <ipv4> <mask>", _h("ip-address"), "IP subnet mask", true)
	_reg.register(I, "switchport mode access", _h("sw-mode-access"), "Set trunking mode to ACCESS")
	_reg.register(I, "switchport access vlan <vlan-id>", _h("sw-access-vlan"), "VLAN ID of the VLAN", true)
	_reg.describe(I, "ip", "Interface Internet Protocol config commands")
	_reg.describe(I, "ip address", "Set the IP address of an interface")
	_reg.describe(I, "ip address <ipv4>", "IP address")
	_reg.describe(I, "switchport", "Set switching mode characteristics")

	_reg.register(V, "name <word>", _h("name"), "The ascii name for the VLAN")

	_reg.set_fallback(CliMode.Id.INTERFACE_CONFIG, CliMode.Id.GLOBAL_CONFIG)
	_reg.set_fallback(CliMode.Id.VLAN_CONFIG, CliMode.Id.GLOBAL_CONFIG)


# --- matching ---------------------------------------------------------------


func test_exact_command_runs_handler_with_ctx() -> void:
	var r: CliResult = _reg.execute(CliMode.Id.PRIV_EXEC, "show ip interface brief", "CTX")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_equal("show-ip-brief")
	assert_str(_last["tag"]).is_equal("show-ip-brief")
	assert_str(_last["ctx"]).is_equal("CTX")
	assert_array(_last["args"]).is_empty()
	assert_bool(_last["negated"]).is_false()


func test_abbreviations(
	mode: int,
	line: String,
	tag: String,
	test_parameters := [
		[P, "sh ip int br", "show-ip-brief"],
		[P, "SHOW IP INTERFACE BRIEF", "show-ip-brief"],
		[P, "sh run", "show-run"],
		[P, "sh int", "show-int"],
		[P, "sh ip ro", "show-ip-route"],
		[P, "sh vl br", "show-vlan"],
		[P, "conf t", "conf-t"],
		[P, "  conf   t  ", "conf-t"],
		[P, "dis", "disable"],
		[P, "copy r s", "copy"],
		[P, "p 10.0.0.1", "ping"],
		[U, "en", "enable"],
		[G, "host R1", "hostname"],
		[G, "int g0/1", "interface"],
		[I, "sh", "shutdown"],
		[I, "sw mo ac", "sw-mode-access"],
	]
) -> void:
	var r: CliResult = _run(mode, line)
	assert_bool(r.ok).is_true()
	assert_str(_last.get("tag", "")).is_equal(tag)


func test_arguments_are_parsed() -> void:
	_run(G, "interface g0/1")
	assert_array(_last["args"]).is_equal(["GigabitEthernet0/1"])
	_run(G, "vlan 10")
	assert_array(_last["args"]).is_equal([10])
	_run(P, "ping 10.0.10.5")
	assert_array(_last["args"]).is_equal([IPv4.parse("10.0.10.5")])
	_run(I, "ip address 10.0.10.1 255.255.255.0")
	assert_array(_last["args"]).is_equal([IPv4.parse("10.0.10.1"), IPv4.parse("255.255.255.0")])
	_run(G, "hostname Core-SW1")
	assert_array(_last["args"]).is_equal(["Core-SW1"])


func test_blank_line_is_a_no_op() -> void:
	for line: String in ["", "   ", "\t"]:
		var r: CliResult = _run(P, line)
		assert_bool(r.ok).is_true()
		assert_str(r.output).is_empty()
		assert_dict(_last).is_empty()


func test_handler_result_is_returned_unchanged() -> void:
	var reg := CommandRegistry.new()
	reg.register(
		CliMode.Id.USER_EXEC,
		"exit",
		func(_ctx: Variant, _args: Array, _negated: bool) -> CliResult:
			var res := CliResult.ok_output("")
			res.action = CliResult.ShellAction.CLOSE_SESSION
			return res,
	)
	var r: CliResult = reg.execute(CliMode.Id.USER_EXEC, "exit")
	assert_int(r.action).is_equal(CliResult.ShellAction.CLOSE_SESSION)


func test_register_rejects_bad_patterns() -> void:
	var reg := CommandRegistry.new()
	assert_bool(reg.register(P, "", _h("x"))).is_false()
	assert_bool(reg.register(P, "x <nope>", _h("x"))).is_false()
	assert_bool(reg.register(P, "ok", _h("ok"))).is_true()
	assert_bool(reg.register(P, "ok", _h("dup"))).is_false()
	assert_bool(reg.register(P, "arg <word>", _h("a"))).is_true()
	assert_bool(reg.register(P, "arg <ipv4>", _h("b"))).is_false()


func test_quoted_arguments_when_enabled() -> void:
	var reg := CommandRegistry.new()
	reg.allow_quotes = true
	reg.register(CliMode.Id.PRIV_EXEC, "curl <word>", _h("curl"))
	var url := "http://10.0.10.5/login.php?user=' OR '1'='1"
	var r: CliResult = reg.execute(CliMode.Id.PRIV_EXEC, "curl \"%s\"" % url)
	assert_bool(r.ok).is_true()
	assert_array(_last["args"]).is_equal([url])


# --- errors -----------------------------------------------------------------


func test_ambiguous_prefix() -> void:
	var r: CliResult = _run(P, "co")
	assert_bool(r.ok).is_false()
	assert_str(r.output).is_equal('% Ambiguous command:  "co"')
	assert_str(_run(P, "show i").output).is_equal('% Ambiguous command:  "show i"')
	assert_str(_run(P, "  co  ").output).is_equal('% Ambiguous command:  "co"')
	assert_str(_run(V, "n").output).is_equal('% Ambiguous command:  "n"')
	assert_str(_run(I, "i").output).is_equal('% Ambiguous command:  "i"')
	assert_dict(_last).is_empty()


func test_incomplete(
	mode: int,
	line: String,
	test_parameters := [
		[P, "show"],
		[P, "show ip"],
		[P, "show ip interface"],
		[P, "configure"],
		[P, "ping"],
		[G, "hostname"],
		[G, "interface"],
		[G, "vlan"],
		[I, "ip address"],
		[I, "ip address 10.0.0.1"],
		[I, "interface"],
		[G, "d"],
	]
) -> void:
	var r: CliResult = _run(mode, line)
	assert_bool(r.ok).is_false()
	assert_str(r.output).is_equal(INCOMPLETE)
	assert_dict(_last).is_empty()


func test_invalid_marker_column(
	mode: int,
	line: String,
	col: int,
	test_parameters := [
		[P, "show ipp", 5],
		[P, "  show ipp", 7],
		[P, "configure termx", 10],
		[P, "ping 10.0.10", 5],
		[P, "ping 1.1.1.1 2", 13],
		[P, "show running-config extra", 20],
		[G, "vlan 5000", 5],
		[G, "interface bogus", 10],
		[I, "ip address 10.0.0.1 255.0.255.0", 20],
	]
) -> void:
	var r: CliResult = _run(mode, line)
	assert_bool(r.ok).is_false()
	assert_str(r.output).is_equal(_caret(col))
	assert_dict(_last).is_empty()


func test_marker_is_shifted_by_prompt_width() -> void:
	var r: CliResult = _reg.execute(CliMode.Id.PRIV_EXEC, "show ipp", null, 3)
	assert_str(r.output).is_equal(_caret(8))


func test_handler_invalid_input_puts_the_marker_under_that_word() -> void:
	var reg := CommandRegistry.new()
	reg.register(G, "interface <interface>", func(_c: Variant, _a: Array, _n: bool) -> CliResult:
		return CliResult.invalid_input(1))
	reg.register(G, "shutdown", func(_c: Variant, _a: Array, negated: bool) -> CliResult:
		return CliResult.invalid_input(1 if negated else 0), "", true)
	var r: CliResult = reg.execute(G, "int  g0/1", null, 6)
	assert_bool(r.ok).is_false()
	assert_str(r.output).is_equal(" ".repeat(6 + 5) + "^\n" + INVALID)
	assert_str(reg.execute(G, "shut", null, 6).output).is_equal(" ".repeat(6) + "^\n" + INVALID)
	assert_str(reg.execute(G, "no shut", null, 6).output).is_equal(" ".repeat(6 + 3) + "^\n" + INVALID)


func test_wrong_mode_is_invalid_input() -> void:
	assert_str(_run(P, "hostname foo").output).is_equal(_caret(0))
	assert_str(_run(G, "disable").output).is_equal(_caret(0))
	assert_str(_run(G, "shutdown").output).is_equal(_caret(0))
	assert_str(_run(I, "bogus").output).is_equal(_caret(0))
	assert_dict(_last).is_empty()


func test_unknown_single_word_in_exec_translates(
	mode: int,
	line: String,
	word: String,
	test_parameters := [[U, "foo", "foo"], [P, "foo", "foo"], [P, "Foo", "Foo"], [P, "shutdown", "shutdown"]]
) -> void:
	var r: CliResult = _run(mode, line)
	assert_bool(r.ok).is_false()
	var expected := 'Translating "%s"... % Unknown command or computer name, or unable to find computer address'
	assert_str(r.output).is_equal(expected.replace("%s", word))


func test_unknown_multi_word_in_exec_is_invalid_input() -> void:
	assert_str(_run(P, "foo bar").output).is_equal(_caret(0))
	assert_str(_run(U, "foo bar").output).is_equal(_caret(0))


# --- no ---------------------------------------------------------------------


func test_no_negates_negatable_commands() -> void:
	_run(I, "no shutdown")
	assert_str(_last["tag"]).is_equal("shutdown")
	assert_bool(_last["negated"]).is_true()
	assert_array(_last["args"]).is_empty()
	_run(I, "no sh")
	assert_bool(_last["negated"]).is_true()
	_run(I, "shutdown")
	assert_bool(_last["negated"]).is_false()


func test_no_may_omit_trailing_arguments() -> void:
	_run(I, "no ip address")
	assert_str(_last["tag"]).is_equal("ip-address")
	assert_bool(_last["negated"]).is_true()
	assert_array(_last["args"]).is_empty()
	_run(I, "no ip address 10.0.0.1 255.255.255.0")
	assert_array(_last["args"]).is_equal([IPv4.parse("10.0.0.1"), IPv4.parse("255.255.255.0")])
	_run(G, "no hostname")
	assert_array(_last["args"]).is_empty()
	_run(G, "no vlan 10")
	assert_array(_last["args"]).is_equal([10])
	_run(I, "no sw ac vl 5")
	assert_str(_last["tag"]).is_equal("sw-access-vlan")
	assert_array(_last["args"]).is_equal([5])


func test_positive_form_still_needs_its_arguments() -> void:
	assert_str(_run(I, "ip address").output).is_equal(INCOMPLETE)
	assert_str(_run(I, "no ip address 10.0.0.1").output).is_equal(INCOMPLETE)
	assert_str(_run(I, "no").output).is_equal(INCOMPLETE)


func test_no_rejects_non_negatable_commands() -> void:
	assert_str(_run(G, "no interface g0/1").output).is_equal(_caret(3))
	assert_str(_run(I, "no switchport mode access").output).is_equal(_caret(14))
	assert_str(_run(I, "no bogus").output).is_equal(_caret(3))
	assert_str(_run(I, "no no shutdown").output).is_equal(_caret(3))
	assert_dict(_last).is_empty()


# --- fallback and do ----------------------------------------------------------


func test_sub_mode_falls_back_to_global_commands() -> void:
	_run(I, "interface g0/2")
	assert_str(_last["tag"]).is_equal("interface")
	assert_array(_last["args"]).is_equal(["GigabitEthernet0/2"])
	_run(I, "hostname R2")
	assert_str(_last["tag"]).is_equal("hostname")
	_run(V, "vlan 20")
	assert_str(_last["tag"]).is_equal("vlan")
	_run(I, "no hostname")
	assert_bool(_last["negated"]).is_true()


func test_fallback_is_one_way() -> void:
	assert_str(_run(G, "shutdown").output).is_equal(_caret(0))
	assert_str(_run(G, "name x").output).is_equal(_caret(0))


func test_same_keyword_in_mode_and_fallback() -> void:
	_run(I, "ip address 1.1.1.1 255.0.0.0")
	assert_str(_last["tag"]).is_equal("ip-address")
	_run(I, "ip route 10.0.0.0 255.0.0.0 1.1.1.1")
	assert_str(_last["tag"]).is_equal("ip-route")
	assert_str(_run(G, "ip address 1.1.1.1 255.0.0.0").output).is_equal(_caret(3))


func test_do_runs_exec_commands_from_config_modes() -> void:
	_run(G, "do show ip interface brief")
	assert_str(_last["tag"]).is_equal("show-ip-brief")
	_run(G, "do sh ip int br")
	assert_str(_last["tag"]).is_equal("show-ip-brief")
	_run(I, "do sh run")
	assert_str(_last["tag"]).is_equal("show-run")
	_run(V, "do ping 10.0.0.1")
	assert_str(_last["tag"]).is_equal("ping")


func test_do_errors() -> void:
	assert_str(_run(G, "do").output).is_equal(INCOMPLETE)
	assert_str(_run(G, "do show ipp").output).is_equal(_caret(8))
	assert_str(_run(G, "do hostname x").output).is_equal(_caret(3))
	assert_str(_run(G, "do foo").output).is_equal(_caret(3))
	assert_str(_run(P, "do show running-config").output).is_equal(_caret(0))


# --- ? help -----------------------------------------------------------------


func test_help_lists_next_keywords() -> void:
	var expected: String = "\n".join([
		"  configure  Enter configuration mode",
		"  copy       Copy from one file to another",
		"  disable    Turn off privileged commands",
		"  ping       Send echo messages",
		"  show       Show running system information",
	])
	assert_str(_reg.help(P, "")).is_equal(expected)
	expected = "\n".join([
		"  interfaces      Interface status and configuration",
		"  ip              IP information",
		"  running-config  Current operating configuration",
		"  vlan            VTP VLAN status",
	])
	assert_str(_reg.help(P, "show ")).is_equal(expected)
	assert_str(_reg.help(P, "sh ")).is_equal(expected)


func test_help_single_keyword_and_cr() -> void:
	assert_str(_reg.help(P, "show ip interface ")).is_equal("  brief  Brief summary of IP status and configuration")
	assert_str(_reg.help(P, "show running-config ")).is_equal("  <cr>")
	assert_str(_reg.help(P, "ping 10.0.0.1 ")).is_equal("  <cr>")


func test_help_shows_argument_placeholder() -> void:
	assert_str(_reg.help(P, "ping ")).is_equal("  A.B.C.D  Target IP address")
	assert_str(_reg.help(G, "vlan ")).is_equal("  <1-4094>  ISL VLAN IDs 1-4094")
	assert_str(_reg.help(G, "hostname ")).is_equal("  WORD  This system's network name")
	assert_str(_reg.help(G, "interface ")).is_equal("  <interface>  Interface to configure")


func test_help_after_no_lists_negatable_commands_and_cr() -> void:
	var expected: String = "\n".join([
		"  hostname    Set system's network name",
		"  ip          Interface Internet Protocol config commands",
		"  shutdown    Shutdown the selected interface",
		"  switchport  Set switching mode characteristics",
		"  vlan        VLAN commands",
	])
	assert_str(_reg.help(I, "no ")).is_equal(expected)
	assert_str(_reg.help(I, "no ip address ")).is_equal("\n".join([
		"  A.B.C.D  IP address",
		"  <cr>",
	]))
	assert_str(_reg.help(I, "no shutdown ")).is_equal("  <cr>")


func test_help_for_partial_word_lists_completions() -> void:
	assert_str(_reg.help(P, "c")).is_equal("configure  copy")
	assert_str(_reg.help(P, "s")).is_equal("show")
	assert_str(_reg.help(P, "show ip")).is_equal("ip")
	assert_str(_reg.help(I, "s")).is_equal("shutdown  switchport")
	assert_str(_reg.help(I, "h")).is_equal("hostname")
	assert_str(_reg.help(G, "d")).is_equal("do")
	assert_str(_reg.help(G, "do sh")).is_equal("show")


func test_help_offers_no_and_do_in_config_modes() -> void:
	var text: String = _reg.help(G, "")
	assert_bool(text.contains("  do ")).is_true()
	assert_bool(text.contains("  no ")).is_true()
	assert_bool(_reg.help(P, "").contains("  no ")).is_false()


func test_help_on_bad_input() -> void:
	assert_str(_reg.help(P, "zz")).is_equal(UNRECOGNIZED)
	assert_str(_reg.help(P, "zz ")).is_equal(UNRECOGNIZED)
	assert_str(_reg.help(P, "show zz ")).is_equal(UNRECOGNIZED)
	assert_str(_reg.help(P, "show zz")).is_equal(UNRECOGNIZED)
	assert_str(_reg.help(P, "co ")).is_equal('% Ambiguous command:  "co"')


# --- Tab --------------------------------------------------------------------


func test_tab_completes_a_unique_prefix(
	mode: int,
	line: String,
	expected: String,
	test_parameters := [
		[P, "sh", "show "],
		[P, "  sh", "  show "],
		[P, "sh ip int", "sh ip interface "],
		[P, "con", "configure "],
		[P, "show running-config", "show running-config "],
		[G, "d", "do "],
		[G, "do sh", "do show "],
		[I, "hos", "hostname "],
	]
) -> void:
	assert_str(_reg.complete(mode as CliMode.Id, line)).is_equal(expected)


func test_tab_does_nothing_when_ambiguous_or_unknown(
	mode: int,
	line: String,
	test_parameters := [
		[P, "co"],
		[P, "show i"],
		[P, "show "],
		[P, ""],
		[P, "zz"],
		[P, "sh zz"],
		[P, "ping 10.0.0"],
	]
) -> void:
	assert_str(_reg.complete(mode as CliMode.Id, line)).is_equal(line)
