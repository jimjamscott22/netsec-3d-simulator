class_name DebriefView
extends RefCounted
## Read-only end-of-mission data (SPEC §3.3), from NetworkSim.debrief_view().
## The sim only builds one once the mission has ended, so it may hold what the
## views kept back during play: the scenario's `debrief` text and how each
## objective finished. It never holds `solution`.
##
## Objective results are a snapshot taken the moment the mission ended, so
## changes made afterwards don't rewrite the record. Accessors return copies.

var _scenario_id: String
var _title: String
var _completed: bool
var _text: String
var _objectives: Array[Dictionary]


func _init(
	p_scenario_id: String,
	p_title: String,
	p_completed: bool,
	p_text: String,
	states: Array[ObjectiveState],
) -> void:
	_scenario_id = p_scenario_id
	_title = p_title
	_completed = p_completed
	_text = p_text
	for s in states:
		_objectives.append({"id": s.id, "description": s.description, "passed": s.passed})


func scenario_id() -> String:
	return _scenario_id


func title() -> String:
	return _title


## True when every objective passed. (A failed mission arrives in M2.)
func completed() -> bool:
	return _completed


## The scenario's `debrief` text, or "" when it has none.
func text() -> String:
	return _text


## Each `{id: String, description: String, passed: bool}` as the mission ended,
## in file order.
func objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in _objectives:
		out.append(o.duplicate())
	return out
