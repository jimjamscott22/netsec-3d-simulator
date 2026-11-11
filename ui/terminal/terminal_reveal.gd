class_name TerminalReveal
extends RefCounted
## Splits command output into timed pieces so a ping looks like it takes time.
## The sim decides the whole result at once; this delay is only cosmetic.
##
## IOS ping: the line of `!`/`.` after the "Sending ..." line appears one
## character at a time. Windows ping: the four reply lines after "Pinging ..."
## appear one line at a time. Any other output is a single piece with no delay.

const IOS_REPLY_DELAY: float = 0.15
const IOS_TIMEOUT_DELAY: float = 0.5
const WIN_REPLY_DELAY: float = 0.35
const WIN_TIMEOUT_DELAY: float = 0.8
const WIN_REPLY_LINES: int = 4


## One piece of output: wait `delay` seconds, then append `text`.
class Step:
	extends RefCounted
	var delay: float
	var text: String

	func _init(p_delay: float, p_text: String) -> void:
		delay = p_delay
		text = p_text


## The pieces for `output`. Joining every `text` gives back `output` exactly.
static func steps(output: String) -> Array[Step]:
	var lines: PackedStringArray = output.split("\n")
	for i: int in lines.size() - 1:
		if lines[i].begins_with("Sending ") and _is_reply_marks(lines[i + 1]):
			return _ios_steps(lines, i + 1)
	if lines.size() > WIN_REPLY_LINES and lines[0].begins_with("Pinging "):
		return _windows_steps(lines)
	return [Step.new(0.0, output)]


## Total delay of all pieces, for tests and for skipping.
static func duration(pieces: Array[Step]) -> float:
	var total: float = 0.0
	for s: Step in pieces:
		total += s.delay
	return total


static func _is_reply_marks(line: String) -> bool:
	if line.is_empty():
		return false
	for c: String in line:
		if c != "!" and c != ".":
			return false
	return true


static func _ios_steps(lines: PackedStringArray, marks_at: int) -> Array[Step]:
	var out: Array[Step] = []
	var head: String = "\n".join(lines.slice(0, marks_at)) + "\n"
	out.append(Step.new(0.0, head))
	var marks: String = lines[marks_at]
	for c: String in marks:
		out.append(Step.new(IOS_REPLY_DELAY if c == "!" else IOS_TIMEOUT_DELAY, c))
	var rest: PackedStringArray = lines.slice(marks_at + 1)
	if not rest.is_empty():
		out.append(Step.new(0.0, "\n" + "\n".join(rest)))
	return out


static func _windows_steps(lines: PackedStringArray) -> Array[Step]:
	var out: Array[Step] = [Step.new(0.0, lines[0])]
	for i: int in range(1, WIN_REPLY_LINES + 1):
		var timed_out: bool = lines[i].begins_with("Request timed out")
		out.append(Step.new(WIN_TIMEOUT_DELAY if timed_out else WIN_REPLY_DELAY, "\n" + lines[i]))
	var rest: PackedStringArray = lines.slice(WIN_REPLY_LINES + 1)
	if not rest.is_empty():
		out.append(Step.new(0.0, "\n" + "\n".join(rest)))
	return out
