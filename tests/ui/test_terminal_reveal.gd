class_name TestTerminalReveal
extends GdUnitTestSuite

const IOS_OK: String = "Type escape sequence to abort.\nSending 5, 100-byte ICMP Echos to 192.168.10.10, timeout is 2 seconds:\n!!!!!\nSuccess rate is 100 percent (5/5), round-trip min/avg/max = 1/2/4 ms"
const IOS_FAIL: String = "Type escape sequence to abort.\nSending 5, 100-byte ICMP Echos to 10.0.0.9, timeout is 2 seconds:\n.....\nSuccess rate is 0 percent (0/5)"
const WIN_FAIL: String = "Pinging 192.168.20.10 with 32 bytes of data:\nRequest timed out.\nRequest timed out.\nRequest timed out.\nRequest timed out.\n\nPing statistics for 192.168.20.10:\n    Packets: Sent = 4, Received = 0, Lost = 4 (100% loss),"
const WIN_OK: String = "Pinging 192.168.10.1 with 32 bytes of data:\nReply from 192.168.10.1: bytes=32 time<1ms TTL=128\nReply from 192.168.10.1: bytes=32 time<1ms TTL=128\nReply from 192.168.10.1: bytes=32 time<1ms TTL=128\nReply from 192.168.10.1: bytes=32 time<1ms TTL=128\n\nPing statistics for 192.168.10.1:"


func _joined(steps: Array[TerminalReveal.Step]) -> String:
	var out: String = ""
	for s: TerminalReveal.Step in steps:
		out += s.text
	return out


func test_plain_output_is_one_instant_step() -> void:
	var steps: Array[TerminalReveal.Step] = TerminalReveal.steps("Router uptime\nline two")
	assert_int(steps.size()).is_equal(1)
	assert_float(steps[0].delay).is_equal(0.0)
	assert_str(steps[0].text).is_equal("Router uptime\nline two")


func test_ios_success_reveals_each_bang() -> void:
	var steps: Array[TerminalReveal.Step] = TerminalReveal.steps(IOS_OK)
	assert_str(_joined(steps)).is_equal(IOS_OK)
	# Header, five marks, then the summary.
	assert_int(steps.size()).is_equal(7)
	assert_float(steps[0].delay).is_equal(0.0)
	assert_str(steps[0].text).ends_with("timeout is 2 seconds:\n")
	for i: int in range(1, 6):
		assert_str(steps[i].text).is_equal("!")
		assert_float(steps[i].delay).is_equal(TerminalReveal.IOS_REPLY_DELAY)
	assert_str(steps[6].text).starts_with("\nSuccess rate is 100 percent")
	assert_float(steps[6].delay).is_equal(0.0)


func test_ios_failure_dots_wait_longer() -> void:
	var steps: Array[TerminalReveal.Step] = TerminalReveal.steps(IOS_FAIL)
	assert_str(_joined(steps)).is_equal(IOS_FAIL)
	assert_str(steps[1].text).is_equal(".")
	assert_float(steps[1].delay).is_equal(TerminalReveal.IOS_TIMEOUT_DELAY)
	assert_float(TerminalReveal.duration(steps)).is_equal_approx(5 * TerminalReveal.IOS_TIMEOUT_DELAY, 0.0001)


func test_windows_reveals_four_reply_lines() -> void:
	var steps: Array[TerminalReveal.Step] = TerminalReveal.steps(WIN_OK)
	assert_str(_joined(steps)).is_equal(WIN_OK)
	assert_int(steps.size()).is_equal(6)
	assert_str(steps[0].text).is_equal("Pinging 192.168.10.1 with 32 bytes of data:")
	for i: int in range(1, 5):
		assert_str(steps[i].text).starts_with("\nReply from")
		assert_float(steps[i].delay).is_equal(TerminalReveal.WIN_REPLY_DELAY)


func test_windows_timeouts_wait_longer() -> void:
	var steps: Array[TerminalReveal.Step] = TerminalReveal.steps(WIN_FAIL)
	assert_str(_joined(steps)).is_equal(WIN_FAIL)
	assert_float(steps[1].delay).is_equal(TerminalReveal.WIN_TIMEOUT_DELAY)


func test_marks_without_a_sending_line_are_not_a_ping() -> void:
	assert_int(TerminalReveal.steps("!!!!!").size()).is_equal(1)
	assert_int(TerminalReveal.steps("Sending mail\nnot marks").size()).is_equal(1)


func test_short_pinging_text_is_not_a_windows_ping() -> void:
	# The usage line or a bad host must not be split.
	var text: String = "Pinging is fun\nonly two lines"
	assert_int(TerminalReveal.steps(text).size()).is_equal(1)
