class_name LogFile
extends RefCounted
## A log file on one device: static lines in file order, numbered from 1.
## Immutable after construction, so NetworkSim can hand lines out directly.

var _source: String
var _file: String
var _lines: Array[LogLine] = []


## Builds a file from scenario `lines` entries (`{t?, text, src_ip?, geo?}`).
## The scenario validator has already checked their shape.
static func from_entries(p_source: String, p_file: String, entries: Array) -> LogFile:
	var f := LogFile.new()
	f._source = p_source
	f._file = p_file
	var number: int = 0
	for entry: Dictionary in entries:
		number += 1
		f._lines.append(LogLine.new(
			number,
			str(entry.get("t", "")),
			str(entry.get("text", "")),
			str(entry.get("src_ip", "")),
			str(entry.get("geo", "")),
		))
	return f


## The id of the device the file lives on.
func source() -> String:
	return _source


## The file's path, e.g. "/var/log/auth.log".
func file() -> String:
	return _file


func line_count() -> int:
	return _lines.size()


## Every line in file order, in a fresh array.
func lines() -> Array[LogLine]:
	return _lines.duplicate()


## Line `number` (1-based), or null when it is outside the file.
func line(number: int) -> LogLine:
	if number < 1 or number > _lines.size():
		return null
	return _lines[number - 1]
