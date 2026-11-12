extends Node
## The `Sim` autoload (SPEC §3.2): owns the one `NetworkSim`, is the only code
## that reads `res://scenarios/*.json`, re-emits the core's signals, and is the
## only path from `world/` and `ui/` into the core.
##
## No `class_name`: the global name `Sim` comes from the autoload entry in
## `project.godot`, and a class of the same name would clash with it. Tests
## instantiate it through `preload("res://game/sim.gd")`.
##
## What it exposes is deliberately narrow. Reads come back as read-only views
## (`scenario_view`, `device_view`, `objective_states`,
## `debrief_view`), never as `NetworkSim`
## internals. Device configuration changes only through a `CliSession` from
## `open_session`, so the `set_*` methods are not forwarded.

const SCENARIO_DIR: String = "res://scenarios"

## A scenario finished loading and `scenario_view()` / `device_view()` are ready.
## Loading itself emits no core signals (the world builds from the views once),
## so this is the cue to do that.
signal scenario_loaded(scenario_id: String)

# The core's signals, re-emitted unchanged. See SimEvents.
signal link_changed(a_port: String, b_port: String, connected: bool)
signal interface_state_changed(port: String, oper_up: bool)
signal config_changed(device_id: String)
signal objective_updated(objective_id: String, passed: bool)
signal mission_completed(scenario_id: String)

## Where scenario files are read from. Tests point it at a temp folder to feed
## in broken files; nothing else should change it.
var scenario_dir: String = SCENARIO_DIR

var _net: NetworkSim = NetworkSim.new()


func _init() -> void:
	# One NetworkSim for the life of the autoload. A later load replaces its
	# state in place, so these connections never need redoing.
	var events: SimEvents = _net.events
	events.link_changed.connect(link_changed.emit)
	events.interface_state_changed.connect(interface_state_changed.emit)
	events.config_changed.connect(config_changed.emit)
	events.objective_updated.connect(objective_updated.emit)
	events.mission_completed.connect(mission_completed.emit)


## Loads `res://scenarios/<scenario_id>.json`, replacing all sim state. A missing
## file, bad JSON or an invalid scenario returns every problem and leaves the
## current state untouched. Emits `scenario_loaded` on success only.
func load_scenario_id(scenario_id: String) -> LoadResult:
	if not _is_valid_id(scenario_id):
		return LoadResult.failure(["scenario id '%s': must be snake_case (a-z, 0-9, _)" % scenario_id])
	var path: String = "%s/%s.json" % [scenario_dir, scenario_id]
	if not FileAccess.file_exists(path):
		return LoadResult.failure(["%s: no such scenario file" % path])
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return LoadResult.failure(["%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]])
	if not json.data is Dictionary:
		return LoadResult.failure(["%s: the top level must be a JSON object" % path])
	var result: LoadResult = _net.load_scenario(json.data, scenario_id)
	if result.ok:
		scenario_loaded.emit(scenario_id)
	return result


## Static scenario data, or null until a scenario has loaded.
func scenario_view() -> ScenarioView:
	return _net.scenario_view()


## A read-only snapshot of one device, or null if there is no such device.
func device_view(id: String) -> DeviceView:
	return _net.device_view(id)


func objective_states() -> Array[ObjectiveState]:
	return _net.objective_states()


## The end-of-mission record, or null until the mission has ended.
func debrief_view() -> DebriefView:
	return _net.debrief_view()


func spare_cables() -> int:
	return _net.spare_cables()


func connect_link(a: String, b: String) -> LinkResult:
	return _net.connect_link(a, b)


func disconnect_link(port: String) -> LinkResult:
	return _net.disconnect_link(port)


func ping(src_id: String, dst_ip: String) -> PingResult:
	return _net.ping(src_id, dst_ip)


## A terminal session on a device, or null if there is no such device.
func open_session(device_id: String) -> CliSession:
	return _net.open_session(device_id)


## Only a bare file stem: nothing that could walk out of the scenarios folder.
static func _is_valid_id(scenario_id: String) -> bool:
	if scenario_id.is_empty():
		return false
	for i in scenario_id.length():
		var c: String = scenario_id[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true
