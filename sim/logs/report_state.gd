class_name ReportState
extends RefCounted
## The player's incident report: one entry per report field, each with the
## expected answer, the attempts left and what was last filed. Built by
## ScenarioLoader from a validated scenario; changed only through
## NetworkSim.submit_report. The answers stay in here and never reach a view
## during play.
##
## Answers match case-insensitively with whitespace trimmed and runs of it
## collapsed, so "  brute   FORCE " is "Brute force".

enum Kind { IPV4, CHOICE, TEXT }

const DEFAULT_MAX_ATTEMPTS: int = 3

static var _spaces: RegEx = RegEx.create_from_string("\\s+")

var _order: Array[String] = []
## field id -> {label, kind, options, answer (normalized), answer_text (as written in
## the scenario), evidence (refs `{source, file, line}`), attempts_left, last_value, solved}
var _fields: Dictionary = {}


## `report` is the scenario's `report` object; `answers` maps field id to the
## `equals` of its `report` objective.
static func from_scenario(report: Dictionary, answers: Dictionary) -> ReportState:
	var state := ReportState.new()
	var max_attempts: int = ScenarioFields.to_int(report.get("max_attempts", DEFAULT_MAX_ATTEMPTS))
	for entry: Dictionary in report["fields"]:
		var id: String = entry["id"]
		var options: Array[String] = []
		options.assign(entry.get("options", []))
		state._order.append(id)
		var evidence: Array[Dictionary] = []
		for ref: Dictionary in entry.get("evidence", []):
			evidence.append({
				"source": str(ref["source"]),
				"file": str(ref["file"]),
				"line": ScenarioFields.to_int(ref["line"]),
			})
		state._fields[id] = {
			"label": str(entry.get("label", id)),
			"kind": Kind[(entry["kind"] as String).to_upper()],
			"options": options,
			"answer": normalize(str(answers.get(id, ""))),
			"answer_text": str(answers.get(id, "")),
			"evidence": evidence,
			"attempts_left": max_attempts,
			"last_value": "",
			"solved": false,
		}
	return state


## Lower-case, trimmed, with each run of whitespace made one space.
static func normalize(value: String) -> String:
	return _spaces.sub(value.strip_edges(), " ", true).to_lower()


func field_ids() -> Array[String]:
	return _order.duplicate()


func has_field(id: String) -> bool:
	return _fields.has(id)


## Files `value` for `field_id`. Refusals (unknown field, already solved, out of
## attempts, a value that cannot be an answer) change nothing. A right answer
## solves the field; a wrong one costs an attempt.
func submit(field_id: String, value: String) -> ReportResult:
	if not _fields.has(field_id):
		return ReportResult.refused(ReportResult.Reason.UNKNOWN_FIELD)
	var f: Dictionary = _fields[field_id]
	if f["solved"]:
		return ReportResult.refused(ReportResult.Reason.ALREADY_SOLVED, f["attempts_left"])
	if f["attempts_left"] <= 0:
		return ReportResult.refused(ReportResult.Reason.OUT_OF_ATTEMPTS)
	var filed: String = _as_answer(f, value)
	if filed.is_empty():
		return ReportResult.refused(ReportResult.Reason.INVALID_VALUE, f["attempts_left"])
	var correct: bool = normalize(filed) == f["answer"]
	f["last_value"] = filed
	if correct:
		f["solved"] = true
	else:
		f["attempts_left"] -= 1
	return ReportResult.accepted(correct, f["attempts_left"])


## Live progress for every field, with no answers.
func view() -> ReportView:
	var rows: Array[Dictionary] = []
	for id in _order:
		var f: Dictionary = _fields[id]
		rows.append({
			"id": id,
			"attempts_left": f["attempts_left"],
			"last_value": f["last_value"],
			"solved": f["solved"],
		})
	return ReportView.new(rows)


## What the end-of-mission debrief shows for each field, in file order:
## `{id, label, answer, last_value, solved, evidence: [{source, file, line}]}`.
## These are the answers, so NetworkSim only hands them out once the mission has ended.
func debrief_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in _order:
		var f: Dictionary = _fields[id]
		var evidence: Array[Dictionary] = []
		for ref: Dictionary in f["evidence"]:
			evidence.append(ref.duplicate())
		rows.append({
			"id": id,
			"label": f["label"],
			"answer": f["answer_text"],
			"last_value": f["last_value"],
			"solved": f["solved"],
			"evidence": evidence,
		})
	return rows


## The value as it would be filed, or "" when it cannot be an answer for the
## field's kind. A choice is filed as the option's own spelling.
func _as_answer(f: Dictionary, value: String) -> String:
	var typed: String = _spaces.sub(value.strip_edges(), " ", true)
	match f["kind"]:
		Kind.IPV4:
			return typed if IPv4.is_valid(typed) else ""
		Kind.CHOICE:
			for option: String in f["options"]:
				if normalize(option) == normalize(typed):
					return option
			return ""
	return typed
