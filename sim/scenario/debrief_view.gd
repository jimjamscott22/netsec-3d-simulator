class_name DebriefView
extends RefCounted
## Read-only end-of-mission data (SPEC §3.3), from NetworkSim.debrief_view().
## The sim only builds one once the mission has ended, so it may hold what the
## views kept back during play: the scenario's `debrief` text and how each
## objective finished. It never holds `solution`.
##
## Objective results are a snapshot taken the moment the mission ended, so
## changes made afterwards don't rewrite the record. Accessors return copies.
## A mission that ended by failing has `completed() == false`.

var _scenario_id: String
var _title: String
var _completed: bool
var _text: String
var _objectives: Array[Dictionary]
var _report: Array[Dictionary] = []


func _init(
	p_scenario_id: String,
	p_title: String,
	p_completed: bool,
	p_text: String,
	states: Array[ObjectiveState],
	p_report: Array[Dictionary] = [],
) -> void:
	_scenario_id = p_scenario_id
	_title = p_title
	_completed = p_completed
	_text = p_text
	for s in states:
		_objectives.append({"id": s.id, "description": s.description, "passed": s.passed, "failed": s.failed})
	for row in p_report:
		_report.append(row.duplicate(true))


func scenario_id() -> String:
	return _scenario_id


func title() -> String:
	return _title


## True when every objective passed, false when the mission was failed.
func completed() -> bool:
	return _completed


## The scenario's `debrief` text, or "" when it has none.
func text() -> String:
	return _text


## Each `{id: String, description: String, passed: bool, failed: bool}` as the
## mission ended, in file order.
func objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in _objectives:
		out.append(o.duplicate())
	return out


## M2: each report field as the mission ended, in file order: `{id: String,
## label: String, answer: String, last_value: String, solved: bool, evidence:
## Array}`, where each evidence entry is `{source: String, file: String, line:
## int, text: String}` (the log line the scenario cites, as the player saw it).
## Empty when the scenario has no report. This is where the answers finally
## reach the presentation layer, which is why the view exists only after the end.
func report_fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in _report:
		out.append(row.duplicate(true))
	return out
