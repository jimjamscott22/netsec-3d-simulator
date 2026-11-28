class_name Vuln
extends RefCounted
## One vulnerability on a server (SPEC §7.5): where its patch region starts in
## its file, what fixes are accepted, the hint shown on a rejected save, the
## exploit the simulated HTTP checks, and `patch_rev`, the number of saves so
## far. Everything here except `id`, the region range and `hint` is hidden
## server metadata: no view hands it to the presentation layer.

var id: String
var kind: String = ""
var service: String = ""
var route: String = ""
## Path of the file that holds the region.
var file: String
## The region's line range in the starting file, 1-based and inclusive.
var first_line: int
var last_line: int
var accept: Array[String] = []
var accept_fixtures: Array[String] = []
var reject_fixtures: Array[String] = []
var hint: String = ""
## `{param, payload, vulnerable_body, patched_body}`.
var exploit: Dictionary = {}
## Saves of this vuln's region so far; NetworkSim.write_patch bumps it.
var patch_rev: int = 0


func _init(p_id: String, p_file: String, p_first_line: int, p_last_line: int) -> void:
	id = p_id
	file = p_file
	first_line = p_first_line
	last_line = p_last_line


## Builds a vuln from a scenario `vulns` entry. The scenario validator checks
## the entry's shape; missing optional keys are left empty here.
static func from_entry(entry: Dictionary) -> Vuln:
	var region: Dictionary = entry.get("region", {})
	var v := Vuln.new(
		str(entry.get("id", "")),
		str(region.get("file", "")),
		ScenarioFields.to_int(region.get("first_line", 0)),
		ScenarioFields.to_int(region.get("last_line", 0)),
	)
	v.kind = str(entry.get("kind", ""))
	v.service = str(entry.get("service", ""))
	v.route = str(entry.get("route", ""))
	v.accept.assign(_strings(entry.get("accept", [])))
	v.accept_fixtures.assign(_strings(entry.get("accept_fixtures", [])))
	v.reject_fixtures.assign(_strings(entry.get("reject_fixtures", [])))
	v.hint = str(entry.get("hint", ""))
	var exploit_entry: Variant = entry.get("exploit", {})
	if exploit_entry is Dictionary:
		v.exploit = (exploit_entry as Dictionary).duplicate(true)
	return v


static func _strings(value: Variant) -> Array:
	if not value is Array:
		return []
	return (value as Array).map(func(s: Variant) -> String: return str(s))
