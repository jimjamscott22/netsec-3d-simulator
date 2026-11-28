class_name TestSourceFile
extends GdUnitTestSuite
## SourceFile: a file kept as prefix + patch region + suffix (task 3.1).

const TEXT: String = "<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\n  $q = \"SELECT '\" . $user . \"'\";\n  $res = $db->query($q);\n  return $res->fetch();\n}\n"


func _marked() -> SourceFile:
	var f := SourceFile.new("/var/www/login.php", TEXT)
	assert_bool(f.mark_region("sqli_login", 4, 5)).is_true()
	return f


func test_a_file_without_a_region_reads_back_unchanged() -> void:
	var f := SourceFile.new("/var/www/login.php", TEXT)
	assert_str(f.path()).is_equal("/var/www/login.php")
	assert_str(f.text()).is_equal(TEXT)
	assert_int(f.line_count()).is_equal(7)
	assert_bool(f.has_region()).is_false()
	assert_str(f.vuln_id()).is_empty()
	assert_str(f.region_text()).is_empty()
	assert_int(f.region_first_line()).is_equal(0)
	assert_int(f.region_last_line()).is_equal(0)
	assert_bool(f.replace_region("x")).is_false()
	assert_str(f.text()).is_equal(TEXT)


func test_a_file_without_a_final_newline_keeps_that() -> void:
	assert_str(SourceFile.new("/a", "one\ntwo").text()).is_equal("one\ntwo")
	assert_int(SourceFile.new("/a", "one\ntwo").line_count()).is_equal(2)


func test_crlf_line_endings_become_lf() -> void:
	var f := SourceFile.new("/a", "one\r\ntwo\r\n")
	assert_str(f.text()).is_equal("one\ntwo\n")
	f.mark_region("v", 2, 2)
	f.replace_region("2\r\n3")
	assert_str(f.text()).is_equal("one\n2\n3\n")


func test_marking_a_region_keeps_the_text_and_records_its_range() -> void:
	var f: SourceFile = _marked()
	assert_str(f.text()).is_equal(TEXT)
	assert_bool(f.has_region()).is_true()
	assert_str(f.vuln_id()).is_equal("sqli_login")
	assert_str(f.region_text()).is_equal("  $q = \"SELECT '\" . $user . \"'\";\n  $res = $db->query($q);")
	assert_str(f.start_region_text()).is_equal(f.region_text())
	assert_int(f.region_first_line()).is_equal(4)
	assert_int(f.region_last_line()).is_equal(5)


func test_a_region_can_span_the_first_or_last_line() -> void:
	var f := SourceFile.new("/a", "one\ntwo\nthree\n")
	assert_bool(f.mark_region("v", 1, 3)).is_true()
	assert_str(f.region_text()).is_equal("one\ntwo\nthree")
	f.replace_region("ONE")
	assert_str(f.text()).is_equal("ONE\n")


func test_bad_regions_are_refused() -> void:
	var f := SourceFile.new("/a", "one\ntwo\nthree\n")
	assert_bool(f.mark_region("v", 0, 1)).is_false()
	assert_bool(f.mark_region("v", 3, 2)).is_false()
	assert_bool(f.mark_region("v", 3, 4)).is_false()
	assert_bool(f.mark_region("", 1, 1)).is_false()
	assert_bool(f.has_region()).is_false()
	assert_bool(f.mark_region("v", 2, 2)).is_true()
	# One region per file: a second one, even elsewhere, is refused.
	assert_bool(f.mark_region("w", 3, 3)).is_false()
	assert_str(f.vuln_id()).is_equal("v")
	assert_str(f.text()).is_equal("one\ntwo\nthree\n")


func test_replacing_the_region_changes_only_the_region() -> void:
	var f: SourceFile = _marked()
	assert_bool(f.replace_region("  $res = $db->prepare(\"SELECT ?\");\n  $res->execute([$user]);")).is_true()
	assert_str(f.text()).is_equal("<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\n  $res = $db->prepare(\"SELECT ?\");\n  $res->execute([$user]);\n  return $res->fetch();\n}\n")
	assert_str(f.start_region_text()).is_equal("  $q = \"SELECT '\" . $user . \"'\";\n  $res = $db->query($q);")


func test_a_longer_patch_moves_the_suffix_down_and_keeps_it_intact() -> void:
	var f: SourceFile = _marked()
	f.replace_region("a\nb\nc\nd")
	assert_int(f.region_first_line()).is_equal(4)
	assert_int(f.region_last_line()).is_equal(7)
	assert_int(f.line_count()).is_equal(9)
	assert_str(f.text()).is_equal("<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\na\nb\nc\nd\n  return $res->fetch();\n}\n")
	# A later, shorter save still lands between the same prefix and suffix.
	f.replace_region("z")
	assert_int(f.region_last_line()).is_equal(4)
	assert_str(f.text()).is_equal("<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\nz\n  return $res->fetch();\n}\n")


func test_one_trailing_newline_ends_the_last_region_line() -> void:
	var f: SourceFile = _marked()
	f.replace_region("x\n")
	assert_str(f.region_text()).is_equal("x")
	assert_int(f.region_last_line()).is_equal(4)
	f.replace_region("x\n\n")
	assert_str(f.region_text()).is_equal("x\n")
	assert_int(f.region_last_line()).is_equal(5)


func test_an_empty_region_is_one_empty_line() -> void:
	var f: SourceFile = _marked()
	f.replace_region("")
	assert_str(f.region_text()).is_empty()
	assert_int(f.region_first_line()).is_equal(4)
	assert_int(f.region_last_line()).is_equal(4)
	assert_str(f.text()).is_equal("<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\n\n  return $res->fetch();\n}\n")
