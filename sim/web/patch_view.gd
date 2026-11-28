class_name PatchView
extends RefCounted
## Read-only metadata for one patch region, from NetworkSim.patch_views()
## (SPEC §3.3): the vuln's id, the region's current line range in the file
## (1-based, inclusive) and the hint shown on a rejected save. It never holds
## the accepted fixes, fixtures or exploit.

var _vuln_id: String
var _first_line: int
var _last_line: int
var _hint: String


func _init(p_vuln_id: String, p_first_line: int, p_last_line: int, p_hint: String) -> void:
	_vuln_id = p_vuln_id
	_first_line = p_first_line
	_last_line = p_last_line
	_hint = p_hint


func vuln_id() -> String:
	return _vuln_id


func first_line() -> int:
	return _first_line


func last_line() -> int:
	return _last_line


func hint() -> String:
	return _hint
