class_name TestCliTokenizer
extends GdUnitTestSuite


func _texts(tokens: Array[CliToken]) -> PackedStringArray:
	var out := PackedStringArray()
	for t: CliToken in tokens:
		out.append(t.text)
	return out


func test_splits_on_whitespace() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize("  show \t ip   int  br ")
	assert_array(_texts(tokens)).is_equal(["show", "ip", "int", "br"])


func test_empty_and_blank_lines() -> void:
	assert_int(CliTokenizer.tokenize("").size()).is_equal(0)
	assert_int(CliTokenizer.tokenize("   \t ").size()).is_equal(0)


func test_records_columns() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize("  sh  ip")
	assert_int(tokens[0].start).is_equal(2)
	assert_int(tokens[0].end).is_equal(4)
	assert_int(tokens[1].start).is_equal(6)
	assert_int(tokens[1].end).is_equal(8)


func test_plain_mode_keeps_quotes_literal() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize('curl "a b"')
	assert_array(_texts(tokens)).is_equal(["curl", '"a', 'b"'])
	assert_bool(tokens[1].quoted).is_false()


func test_quoted_mode_holds_spaces_and_single_quotes() -> void:
	var line := "curl \"http://10.0.10.5/login.php?user=' OR '1'='1\""
	var tokens: Array[CliToken] = CliTokenizer.tokenize(line, true)
	assert_array(_texts(tokens)).is_equal(["curl", "http://10.0.10.5/login.php?user=' OR '1'='1"])
	assert_bool(tokens[1].quoted).is_true()
	assert_int(tokens[1].start).is_equal(5)
	assert_int(tokens[1].end).is_equal(line.length())


func test_quoted_mode_empty_quotes_is_an_empty_token() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize('grep "" f', true)
	assert_array(_texts(tokens)).is_equal(["grep", "", "f"])
	assert_bool(tokens[1].quoted).is_true()


func test_quoted_mode_unterminated_runs_to_end_of_line() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize('curl "a b', true)
	assert_array(_texts(tokens)).is_equal(["curl", "a b"])
	assert_bool(tokens[1].quoted).is_true()


func test_quoted_mode_quote_inside_a_word_is_literal() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize('echo a"b c', true)
	assert_array(_texts(tokens)).is_equal(["echo", 'a"b', "c"])


func test_quoted_mode_plain_words_unchanged() -> void:
	var tokens: Array[CliToken] = CliTokenizer.tokenize("ls /var/log", true)
	assert_array(_texts(tokens)).is_equal(["ls", "/var/log"])
	assert_bool(tokens[0].quoted).is_false()


func test_ends_with_whitespace() -> void:
	assert_bool(CliTokenizer.ends_with_whitespace("show ")).is_true()
	assert_bool(CliTokenizer.ends_with_whitespace("show\t")).is_true()
	assert_bool(CliTokenizer.ends_with_whitespace("show")).is_false()
	assert_bool(CliTokenizer.ends_with_whitespace("")).is_false()
