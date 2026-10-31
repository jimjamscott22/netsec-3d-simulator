class_name ObjectiveEvaluator
extends RefCounted
## Objectives are pure predicates over sim state (references/scenario-schema.md).
## This computes them from a validated scenario and remembers each one's last
## result, so NetworkSim can emit `objective_updated` only when a result changes.
## It never emits anything itself: only NetworkSim does.

const LOCKED_DETAIL: String = "locked until the earlier steps pass"

var _objectives: Array[Dictionary] = []
## PingResult.FailReason -> hint text.
var _hints: Dictionary = {}
## objective id -> `passed` as of the last call to changes().
var _last: Dictionary = {}


func _init(data: Dictionary) -> void:
	for obj: Dictionary in data["objectives"]:
		_objectives.append(obj.duplicate(true))
	for hint: Dictionary in data.get("hints", []):
		_hints[PingResult.FailReason[hint["reason"]]] = hint["text"]


## Every objective's state right now, in file order.
func evaluate(sim: NetworkSim) -> Array[ObjectiveState]:
	var states: Array[ObjectiveState] = []
	for obj in _objectives:
		states.append(_evaluate_one(sim, obj))
	_apply_locks(states)
	return states


## The states whose `passed` differs from the previous call, in file order. Also
## remembers `states`, so call it once per evaluation.
func changes(states: Array[ObjectiveState]) -> Array[ObjectiveState]:
	var out: Array[ObjectiveState] = []
	for s in states:
		if _last.get(s.id, false) != s.passed:
			out.append(s)
		_last[s.id] = s.passed
	return out


static func all_passed(states: Array[ObjectiveState]) -> bool:
	if states.is_empty():
		return false
	for s in states:
		if not s.passed:
			return false
	return true


# --- one objective ---------------------------------------------------------------


func _evaluate_one(sim: NetworkSim, obj: Dictionary) -> ObjectiveState:
	var s := ObjectiveState.new()
	s.id = obj["id"]
	s.description = obj["description"]
	s.order = ScenarioFields.to_int(obj.get("order", 0))
	if obj["type"] == "ping":
		s.type = ObjectiveState.Type.PING
		_evaluate_ping(sim, obj, s)
	else:
		s.type = ObjectiveState.Type.CONFIG
		s.passed = _config_matches(sim.device_view(obj["device"]), _path_keys(obj["path"]), obj["equals"])
	return s


func _evaluate_ping(sim: NetworkSim, obj: Dictionary, s: ObjectiveState) -> void:
	var r: PingResult = sim.ping(obj["from"], obj["to_ip"])
	if not r.success:
		s.fail_reason = r.fail_reason
		s.hint = _hints.get(r.fail_reason, "")
		return
	var answered_by: String = r.hops.back() if not r.hops.is_empty() else ""
	var to_device: String = obj.get("to_device", "")
	if not to_device.is_empty() and answered_by != to_device:
		s.detail = "reached, but %s answered, not %s" % [answered_by, to_device]
		return
	var via: String = obj.get("via", "")
	if not via.is_empty() and not r.hops.has(via):
		s.detail = "reached, but not through %s" % via
		return
	s.passed = true


## An ordered objective is locked while any objective with a lower `order` has
## not passed. Lower ones are settled first, so a locked objective (never passed)
## keeps everything above it locked too. Unordered objectives are never locked.
func _apply_locks(states: Array[ObjectiveState]) -> void:
	var ordered: Array[ObjectiveState] = []
	ordered.assign(states.filter(func(s: ObjectiveState) -> bool: return s.order > 0))
	ordered.sort_custom(func(a: ObjectiveState, b: ObjectiveState) -> bool: return a.order < b.order)
	for s in ordered:
		for lower in ordered:
			if lower.order >= s.order:
				break
			if not lower.passed:
				s.locked = true
				s.passed = false
				s.fail_reason = PingResult.FailReason.NONE
				s.hint = ""
				s.detail = LOCKED_DETAIL
				break


# --- config objectives -----------------------------------------------------------


func _path_keys(path: Variant) -> Array[String]:
	var keys: Array[String] = []
	if path is String:
		keys.append(path)
	else:
		keys.assign(path)
	return keys


func _config_matches(view: DeviceView, keys: Array[String], equals: Variant) -> bool:
	if keys[0] == "interfaces" and keys.size() == 2:
		return _interface_matches(view.interface(keys[1]), equals)
	return _same(_read(view, keys), equals)


## `equals` null means the interface doesn't exist; an object means every key in
## it must match (each value may be null for "not set").
func _interface_matches(iface: Dictionary, equals: Variant) -> bool:
	if equals == null:
		return iface.is_empty()
	if iface.is_empty():
		return false
	var wanted: Dictionary = equals
	for field: String in wanted:
		if not _same(_field(iface, field), wanted[field]):
			return false
	return true


## The leaf a path points at, with "not set" and "doesn't exist" as null.
func _read(view: DeviceView, keys: Array[String]) -> Variant:
	match keys[0]:
		"hostname":
			return view.hostname()
		"interfaces":
			var iface: Dictionary = view.interface(keys[1])
			return null if iface.is_empty() else _field(iface, keys[2])
		"vlans":
			return view.vlans().get(ScenarioFields.parse_vlan_key(keys[1]))
		"gateway":
			return _blank_as_null(view.gateway())
		"locked":
			return view.locked()
		_:
			# Hosts and servers: ip and mask live on their one interface.
			var nic: Dictionary = view.interface(view.interface_names()[0])
			return _blank_as_null(nic[keys[0]])


func _field(iface: Dictionary, field: String) -> Variant:
	match field:
		"admin_up", "access_vlan":
			return iface[field]
		"ip", "mask":
			return _blank_as_null(iface[field])
		"dot1q_vlan":
			return null if int(iface["dot1q_vlan"]) == 0 else iface["dot1q_vlan"]
		"mode":
			return "trunk" if iface["mode"] == Interface.Mode.TRUNK else "access"
		"trunk_allowed":
			return null if iface["trunk_allowed_all"] else iface["trunk_allowed"]
	return null


func _blank_as_null(text: String) -> Variant:
	return null if text.is_empty() else text


## JSON numbers arrive as floats, so numbers compare as integers and lists of
## VLANs compare as sets.
func _same(actual: Variant, expected: Variant) -> bool:
	var actual_nil: bool = typeof(actual) == TYPE_NIL
	var expected_nil: bool = typeof(expected) == TYPE_NIL
	if actual_nil or expected_nil:
		return actual_nil and expected_nil
	if expected is Array:
		return actual is Array and _vlan_set(actual) == _vlan_set(expected)
	if expected is int or expected is float:
		return (actual is int or actual is float) and ScenarioFields.to_int(actual) == ScenarioFields.to_int(expected)
	if expected is bool:
		return actual is bool and actual == expected
	return actual is String and actual == expected


func _vlan_set(list: Array) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in list:
		out.append(ScenarioFields.to_int(v))
	out.sort()
	return out
