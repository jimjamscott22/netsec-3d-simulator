class_name TestServerShell
extends GdUnitTestSuite
## The server's Linux-style shell (task 2.5): the session, then each command's
## parsing (including quotes and the usage fallbacks), output and errors. File
## contents come from the M2 fixture's WEB1 and DB1 logs.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m2.json"
const AUTH: String = "/var/log/auth.log"
const ACCESS: String = "/var/log/nginx/access.log"

var _sim: NetworkSim
var _web: CliSession
var _configs: int = 0


func before_test() -> void:
	_sim = NetworkSim.new()
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	assert_array(_sim.load_scenario(data).errors).is_empty()
	_web = _sim.open_session("WEB1")
	_configs = 0
	_sim.events.config_changed.connect(func(_id: String) -> void: _configs += 1)


func _run(line: String) -> CliResult:
	return _web.submit(line)


func _ok(line: String) -> String:
	var r: CliResult = _run(line)
	assert_bool(r.ok).override_failure_message("'%s' failed: %s" % [line, r.output]).is_true()
	return r.output


func _fails(line: String) -> String:
	var r: CliResult = _run(line)
	assert_bool(r.ok).override_failure_message("'%s' should fail, printed: %s" % [line, r.output]).is_false()
	return r.output


func _usage(command: String) -> String:
	return ServerFormatters.usage(command)


# --- the session ------------------------------------------------------------


func test_a_server_gets_the_linux_shell() -> void:
	assert_bool(_web is ServerSession).is_true()
	assert_bool(_web is HostSession).is_false()
	assert_int(_web.mode()).is_equal(CliMode.Id.USER_EXEC)
	assert_bool(_web.is_password_prompt()).is_false()


func test_the_prompt_follows_the_hostname() -> void:
	assert_str(_web.prompt()).is_equal("analyst@web1:/$")
	assert_str(_sim.open_session("DB1").prompt()).is_equal("analyst@db1:/$")
	_sim.get_device("WEB1").hostname = "front"
	assert_str(_web.prompt()).is_equal("analyst@front:/$")


func test_only_a_server_has_this_registry() -> void:
	assert_object(ServerCommands.registry_for(_sim.get_device("WEB1"))).is_not_null()
	assert_object(ServerCommands.registry_for(null)).is_null()
	var t := TopoBuilder.new()
	for entry in [["router_2port", "R1"], ["switch_24", "S1"], ["pc", "PC"]]:
		t.add(entry[0], entry[1])
		assert_object(ServerCommands.registry_for(t.sim.get_device(entry[1]))).override_failure_message(entry[1]).is_null()
	assert_object(HostCommands.registry_for(_sim.get_device("WEB1"))).is_null()


func test_blank_input_prints_nothing() -> void:
	for line in ["", "   ", "\t"]:
		var r: CliResult = _run(line)
		assert_bool(r.ok).is_true()
		assert_str(r.output).is_empty()


func test_history_is_kept_by_the_session() -> void:
	_run("ls")
	_run("nope")
	_run("help")
	assert_array(_web.history()).is_equal(["ls", "nope", "help"])
	assert_str(_web.history_prev()).is_equal("help")
	assert_str(_web.history_prev()).is_equal("nope")


func test_an_unknown_command_is_not_found() -> void:
	assert_str(_fails("foo")).is_equal("bash: foo: command not found")
	assert_str(_fails("foo bar baz")).is_equal("bash: foo: command not found")
	assert_str(_fails("ipconfig")).is_equal("bash: ipconfig: command not found")
	assert_str(_fails("ping 10.0.0.1")).is_equal("bash: ping: command not found")


func test_commands_run_by_full_name_only() -> void:
	assert_str(_fails("l")).is_equal("bash: l: command not found")
	assert_str(_fails("ca %s" % AUTH)).is_equal("bash: ca: command not found")
	assert_str(_fails("gre x %s" % AUTH)).is_equal("bash: gre: command not found")


func test_the_shell_never_changes_sim_state() -> void:
	for line in ["ls", "ls /var/log", "cat %s" % AUTH, "grep root %s" % AUTH, "tail %s" % AUTH, "service http status", "help", "ls /nope"]:
		_run(line)
	assert_int(_configs).is_equal(0)
	assert_int(_sim.query_logs("WEB1", AUTH, null).size()).is_equal(5)


# --- ls ---------------------------------------------------------------------


func test_ls_lists_the_root_and_marks_directories() -> void:
	assert_str(_ok("ls")).is_equal("var/")
	assert_str(_ok("ls /")).is_equal("var/")


func test_ls_walks_down_the_tree() -> void:
	assert_str(_ok("ls /var")).is_equal("log/")
	assert_str(_ok("ls /var/log")).is_equal("auth.log\nnginx/")
	assert_str(_ok("ls /var/log/nginx")).is_equal("access.log")


func test_ls_on_another_server_lists_its_own_files() -> void:
	var db: CliSession = _sim.open_session("DB1")
	assert_str(db.submit("ls /var/log").output).is_equal("auth.log")


func test_ls_accepts_relative_paths_and_stray_slashes() -> void:
	for typed in ["var/log", "/var/log/", "//var//log", "var/log/"]:
		assert_str(_ok("ls " + typed)).override_failure_message(typed).is_equal("auth.log\nnginx/")


func test_ls_of_a_file_prints_the_path_as_typed() -> void:
	assert_str(_ok("ls %s" % AUTH)).is_equal(AUTH)
	assert_str(_ok("ls var/log/auth.log")).is_equal("var/log/auth.log")


func test_ls_of_a_missing_path_fails() -> void:
	assert_str(_fails("ls /nope")).is_equal("ls: cannot access '/nope': No such file or directory")
	assert_str(_fails("ls /var/lo")).is_equal("ls: cannot access '/var/lo': No such file or directory")


func test_ls_of_a_server_with_no_files_is_empty() -> void:
	var t := TopoBuilder.new()
	t.add("server", "SRV")
	var s: CliSession = t.sim.open_session("SRV")
	var r: CliResult = s.submit("ls")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_empty()


func test_ls_options_and_extra_words_print_usage() -> void:
	assert_str(_fails("ls -l")).is_equal(_usage("ls"))
	assert_str(_fails("ls -la /var")).is_equal(_usage("ls"))
	assert_str(_fails("ls /var /etc")).is_equal(_usage("ls"))


# --- cat --------------------------------------------------------------------


func test_cat_prints_the_whole_file_in_order() -> void:
	var out: PackedStringArray = _ok("cat %s" % AUTH).split("\n")
	assert_int(out.size()).is_equal(5)
	assert_str(out[0]).is_equal("2026-03-14T02:11:05Z sshd[811]: Failed password for root from 203.0.113.45 port 51122 ssh2")
	assert_str(out[4]).is_equal("cron[12]: session opened for user root")


func test_cat_takes_a_relative_path() -> void:
	assert_str(_ok("cat var/log/nginx/access.log")).is_equal(_ok("cat %s" % ACCESS))


func test_cat_of_a_missing_file_or_a_directory_fails() -> void:
	assert_str(_fails("cat /nope.log")).is_equal("cat: /nope.log: No such file or directory")
	assert_str(_fails("cat /var/log")).is_equal("cat: /var/log: Is a directory")
	assert_str(_fails("cat /")).is_equal("cat: /: Is a directory")


func test_cat_needs_exactly_one_file() -> void:
	assert_str(_fails("cat")).is_equal(_usage("cat"))
	assert_str(_fails("cat %s %s" % [AUTH, ACCESS])).is_equal(_usage("cat"))
	assert_str(_fails("cat -n %s" % AUTH)).is_equal(_usage("cat"))


# --- grep -------------------------------------------------------------------


func test_grep_prints_the_matching_lines_in_order() -> void:
	var out: PackedStringArray = _ok("grep Failed %s" % AUTH).split("\n")
	assert_int(out.size()).is_equal(2)
	assert_str(out[0]).contains("port 51122")
	assert_str(out[1]).contains("port 51124")


func test_grep_is_case_sensitive_and_dash_i_is_not() -> void:
	assert_str(_ok("grep failed %s" % AUTH)).is_empty()
	assert_int(_ok("grep -i failed %s" % AUTH).split("\n").size()).is_equal(2)
	assert_int(_ok("grep -i FAILED %s" % AUTH).split("\n").size()).is_equal(2)


func test_grep_takes_a_quoted_pattern_with_spaces() -> void:
	assert_int(_ok('grep "Failed password" %s' % AUTH).split("\n").size()).is_equal(2)
	assert_int(_ok('grep -i "accepted password for deploy" %s' % AUTH).split("\n").size()).is_equal(2)


func test_grep_matches_the_timestamp_and_the_text() -> void:
	assert_str(_ok("grep 02:11:40Z %s" % AUTH)).contains("Accepted password for deploy from 198.51.100.7")


func test_grep_pattern_is_a_regular_expression() -> void:
	assert_int(_ok('grep "for (root|deploy) from" %s' % AUTH).split("\n").size()).is_equal(4)
	assert_int(_ok("grep ^2026-03-14T02:12 %s" % AUTH).split("\n").size()).is_equal(1)


func test_grep_with_no_match_prints_nothing_and_is_not_an_error() -> void:
	assert_str(_ok("grep banana %s" % AUTH)).is_empty()


func test_grep_with_a_bad_regular_expression_fails() -> void:
	assert_str(_fails('grep "(oops" %s' % AUTH)).is_equal("grep: invalid regular expression '(oops'")
	assert_str(_fails('grep -i "[" %s' % AUTH)).is_equal("grep: invalid regular expression '['")


func test_grep_of_a_missing_file_or_a_directory_fails() -> void:
	assert_str(_fails("grep x /nope")).is_equal("grep: /nope: No such file or directory")
	assert_str(_fails("grep x /var")).is_equal("grep: /var: Is a directory")
	assert_str(_fails("grep -i x /nope")).is_equal("grep: /nope: No such file or directory")


func test_grep_options_it_does_not_have_print_usage() -> void:
	assert_str(_fails("grep -v x %s" % AUTH)).is_equal(_usage("grep"))
	assert_str(_fails("grep -i x")).is_equal(_usage("grep"))
	assert_str(_fails("grep -i")).is_equal(_usage("grep"))
	assert_str(_fails("grep x")).is_equal(_usage("grep"))
	assert_str(_fails("grep")).is_equal(_usage("grep"))
	assert_str(_fails("grep a b c")).is_equal(_usage("grep"))
	assert_str(_fails('grep "" %s' % AUTH)).is_equal(_usage("grep"))


func test_grep_an_option_word_after_dash_i_is_still_a_pattern_slot() -> void:
	# `grep -i -x file` is not a search for "-x".
	assert_str(_fails("grep -i -x %s" % AUTH)).is_equal(_usage("grep"))


# --- tail -------------------------------------------------------------------


func test_tail_prints_the_last_ten_lines_or_the_whole_short_file() -> void:
	assert_str(_ok("tail %s" % AUTH)).is_equal(_ok("cat %s" % AUTH))


func test_tail_n_prints_the_last_n_lines() -> void:
	var cat: PackedStringArray = _ok("cat %s" % AUTH).split("\n")
	assert_str(_ok("tail -n 2 %s" % AUTH)).is_equal("\n".join(cat.slice(3)))
	assert_str(_ok("tail -n 1 %s" % AUTH)).is_equal(cat[4])


func test_tail_n_zero_prints_nothing_and_a_large_n_prints_everything() -> void:
	assert_str(_ok("tail -n 0 %s" % AUTH)).is_empty()
	assert_str(_ok("tail -n 999 %s" % AUTH)).is_equal(_ok("cat %s" % AUTH))


func test_tail_defaults_to_ten_lines_of_a_longer_file() -> void:
	var entries: Array = []
	for n in 25:
		entries.append({"text": "line %d" % (n + 1)})
	var data: Dictionary = ScenarioRunner.read(FIXTURE)
	data["logs"][0]["lines"] = entries
	data["report"]["fields"][0].erase("evidence")
	assert_array(_sim.load_scenario(data).errors).is_empty()
	var out: PackedStringArray = _sim.open_session("WEB1").submit("tail %s" % AUTH).output.split("\n")
	assert_int(out.size()).is_equal(10)
	assert_str(out[0]).is_equal("line 16")
	assert_str(out[9]).is_equal("line 25")


func test_tail_n_rejects_a_bad_count() -> void:
	for bad in ["abc", "-3", "+3", "1.5", "2x"]:
		assert_str(_fails("tail -n %s %s" % [bad, AUTH])).override_failure_message(bad).is_equal(
			"tail: invalid number of lines: '%s'" % bad
		)


func test_tail_of_a_missing_file_or_a_directory_fails() -> void:
	assert_str(_fails("tail /nope")).is_equal("tail: /nope: No such file or directory")
	assert_str(_fails("tail -n 2 /var/log")).is_equal("tail: /var/log: Is a directory")


func test_tail_usage() -> void:
	for line in ["tail", "tail -n", "tail -n 2", "tail -x %s" % AUTH, "tail a b", "tail -n 2 a b"]:
		assert_str(_fails(line)).override_failure_message(line).is_equal(_usage("tail"))


# --- service ----------------------------------------------------------------


func _server_with_service() -> CliSession:
	(_sim.get_device("WEB1") as Server).services = [{"id": "http", "port": 80, "root": "/var/www"}]
	return _sim.open_session("WEB1")


func test_service_status_of_a_known_service() -> void:
	var s: CliSession = _server_with_service()
	var r: CliResult = s.submit("service http status")
	assert_bool(r.ok).is_true()
	assert_str(r.output).is_equal("● http.service\n     Loaded: loaded\n     Active: active (running)\n     Listen: 80/tcp")


func test_service_status_of_an_unknown_service_fails() -> void:
	assert_str(_fails("service http status")).is_equal("http: unrecognized service")
	var s: CliSession = _server_with_service()
	assert_str(s.submit("service ssh status").output).is_equal("ssh: unrecognized service")
	# Names are case-sensitive, as on Linux.
	assert_bool(s.submit("service HTTP status").ok).is_false()


func test_service_needs_a_name_and_status() -> void:
	for line in ["service", "service http", "service http restart", "service http status now"]:
		assert_str(_fails(line)).override_failure_message(line).is_equal(_usage("service"))


# --- help and exit ----------------------------------------------------------


const HELP: String = """Commands:
  ls        List files and directories
  cat       Print a file
  grep      Print the lines of a file that match a pattern
  tail      Print the last lines of a file (10 by default)
  service   Show the status of a service
  help      List the commands, or explain one
  exit      Close the terminal"""


func test_help_lists_the_commands() -> void:
	assert_str(_ok("help")).is_equal(HELP)


func test_help_explains_one_command() -> void:
	assert_str(_ok("help grep")).is_equal(
		"grep: Print the lines of a file that match a pattern\nUsage: grep [-i] <pattern> <file>"
	)
	assert_str(_ok("help help")).is_equal("help: List the commands, or explain one\nUsage: help\n       help <command>")


func test_help_for_an_unknown_command() -> void:
	assert_str(_ok("help nope")).is_equal("bash: help: no help topics match 'nope'.")


func test_exit_closes_the_session() -> void:
	var r: CliResult = _run("exit")
	assert_bool(r.ok).is_true()
	assert_int(r.action).is_equal(CliResult.ShellAction.CLOSE_SESSION)


# --- ? and Tab --------------------------------------------------------------


func test_question_mark_lists_the_commands() -> void:
	var out: String = _web.help("")
	for name in ["ls", "cat", "grep", "tail", "service", "help", "exit"]:
		assert_str(out).contains(name)


func test_question_mark_after_grep_offers_the_option_and_the_pattern() -> void:
	var out: String = _web.help("grep ")
	assert_str(out).contains("-i")
	assert_str(out).contains("WORD")


func test_tab_completes_a_command_name() -> void:
	assert_str(_web.complete("ser")).is_equal("service ")
	assert_str(_web.complete("gr")).is_equal("grep ")
