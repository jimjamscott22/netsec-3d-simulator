class_name SourceFile
extends RefCounted
## A source file on a server (SPEC §7.5), kept as lines split into a read-only
## prefix, an editable patch region and a read-only suffix. A file has at most
## one region. Replacing the region never touches the prefix or suffix, so the
## region keeps its place even when an edit changes its line count.
##
## A file that ends in a newline keeps it. A region's text never carries a
## trailing newline: one trailing newline in written text only ends its last
## line, and an empty region is one empty line, so there is always a line to
## type on.

var _path: String
var _trailing_newline: bool
var _prefix: PackedStringArray
var _region: PackedStringArray = PackedStringArray()
var _suffix: PackedStringArray = PackedStringArray()
var _vuln_id: String = ""
var _start_region: String = ""


func _init(p_path: String, text: String) -> void:
	_path = p_path
	var normalized: String = text.replace("\r\n", "\n")
	_trailing_newline = normalized.ends_with("\n")
	if _trailing_newline:
		normalized = normalized.substr(0, normalized.length() - 1)
	_prefix = normalized.split("\n")


func path() -> String:
	return _path


## The whole file as it reads now.
func text() -> String:
	var lines: PackedStringArray = _prefix.duplicate()
	lines.append_array(_region)
	lines.append_array(_suffix)
	return "\n".join(lines) + ("\n" if _trailing_newline else "")


func line_count() -> int:
	return _prefix.size() + _region.size() + _suffix.size()


## Marks lines `first_line`..`last_line` (1-based, inclusive) as the patch
## region of `vuln_id`. False, and nothing changes, when the file already has a
## region, `vuln_id` is empty, or the range is not inside the file.
func mark_region(vuln_id: String, first_line: int, last_line: int) -> bool:
	if has_region() or vuln_id == "":
		return false
	if first_line < 1 or last_line < first_line or last_line > _prefix.size():
		return false
	var lines: PackedStringArray = _prefix
	_prefix = lines.slice(0, first_line - 1)
	_region = lines.slice(first_line - 1, last_line)
	_suffix = lines.slice(last_line)
	_vuln_id = vuln_id
	_start_region = region_text()
	return true


func has_region() -> bool:
	return _vuln_id != ""


## The id of the vuln whose region this is, or "" when the file has none.
func vuln_id() -> String:
	return _vuln_id


## The region's current lines joined by newlines; "" without a region.
func region_text() -> String:
	return "\n".join(_region)


## The region's text as the scenario first wrote it; "" without a region.
func start_region_text() -> String:
	return _start_region


## The region's current first line (1-based), or 0 without a region.
func region_first_line() -> int:
	return _prefix.size() + 1 if has_region() else 0


## The region's current last line (1-based, inclusive), or 0 without a region.
func region_last_line() -> int:
	return _prefix.size() + _region.size() if has_region() else 0


## Replaces the region's lines with `text`. False, and nothing changes, when the
## file has no region.
func replace_region(text: String) -> bool:
	if not has_region():
		return false
	var normalized: String = text.replace("\r\n", "\n")
	if normalized.ends_with("\n"):
		normalized = normalized.substr(0, normalized.length() - 1)
	_region = normalized.split("\n")
	return true
