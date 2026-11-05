class_name ScenarioRunner
extends RefCounted
## Test support for the scenario smoke test (task 1.20): finds every scenario
## file, loads it into a fresh `NetworkSim` and replays its `solution` through
## the same public API the game uses (`connect_link` and CLI sessions).
##
## Nothing here asserts. Problems come back as strings, so the smoke suite can
## report every broken scenario at once and this harness can be tested against
## deliberately broken scenarios. Test-only: it reads files, so it can never
## live under `res://sim/`.

const SCENARIO_DIR: String = "res://scenarios"


## Every `*.json` file name in the scenarios folder, sorted. A scenario's `id`
## must equal its file name without the extension.
static func scenario_files() -> Array[String]:
	var names: Array[String] = []
	for name: String in DirAccess.get_files_at(SCENARIO_DIR):
		if name.ends_with(".json"):
			names.append(name)
	names.sort()
	return names


static func file_id(file_name: String) -> String:
	return file_name.get_basename()


## Parses a scenario file; empty when it is missing or not a JSON object.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	return {}


## Ids of the objectives that are not passing right now, in file order.
static func failing_ids(sim: NetworkSim) -> Array[String]:
	var ids: Array[String] = []
	for s: ObjectiveState in sim.objective_states():
		if not s.passed:
			ids.append(s.id)
	return ids


## Replays the `solution` steps in order. Stops at the first step the sim
## refuses, because later steps would only produce noise. Returns the errors
## (empty when every step was accepted).
static func apply_solution(sim: NetworkSim, data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var steps: Array = data.get("solution", [])
	for i in steps.size():
		var step: Dictionary = steps[i]
		var error: String = _apply_step(sim, step)
		if not error.is_empty():
			errors.append("solution[%d]: %s" % [i, error])
			break
	return errors


## Runs the whole smoke test for one scenario and returns every problem found:
## it must load cleanly, must not already be complete at the start, its
## `solution` must be playable, and afterwards every objective must pass and
## `mission_completed` must have fired exactly once for this scenario.
static func smoke(data: Dictionary, file_id_: String) -> Array[String]:
	var sim := NetworkSim.new()
	var loaded: LoadResult = sim.load_scenario(data, file_id_)
	if not loaded.errors.is_empty():
		var errors: Array[String] = []
		for e: String in loaded.errors:
			errors.append("load: %s" % e)
		return errors

	var problems: Array[String] = []
	var failing_at_start: Array[String] = failing_ids(sim)
	if failing_at_start.is_empty():
		problems.append("start: every objective already passes, so the mission is trivial")

	var completed: Array[String] = []
	sim.events.mission_completed.connect(func(scenario_id: String) -> void: completed.append(scenario_id))

	var step_errors: Array[String] = apply_solution(sim, data)
	problems.append_array(step_errors)
	if not step_errors.is_empty():
		return problems  # the end state is meaningless after a refused step

	var failing_after: Array[String] = failing_ids(sim)
	if not failing_after.is_empty():
		problems.append("after solution: objectives still failing: %s" % ", ".join(failing_after))
	elif completed != [file_id_]:
		problems.append("after solution: expected one mission_completed for '%s', got %s" % [file_id_, str(completed)])
	return problems


static func _apply_step(sim: NetworkSim, step: Dictionary) -> String:
	if step.has("link"):
		var link: Dictionary = step["link"]
		var r: LinkResult = sim.connect_link(link["a"], link["b"])
		if r.ok:
			return ""
		return "link %s <-> %s refused (%s)" % [link["a"], link["b"], LinkResult.Reason.keys()[r.reason]]
	if step.has("device"):
		var device: String = step["device"]
		if sim.get_device(device) == null:
			return "unknown device '%s'" % device
		var session: CliSession = sim.open_session(device)
		for line: String in step["commands"]:
			var result: CliResult = session.submit(line)
			if not result.ok:
				return "%s: '%s' -> %s" % [device, line, result.output.strip_edges()]
		return ""
	return "unsupported step type (has neither 'link' nor 'device')"
