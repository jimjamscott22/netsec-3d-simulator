class_name ScenarioValidator
extends RefCounted
## Checks a parsed scenario against the schema (references/scenario-schema.md)
## before anything is built. Pure data in, a list of "<json path>: <problem>"
## strings out: empty means valid. Every problem is reported, not just the
## first, and a mistake is reported once: if a device's model is bad, its
## interfaces are not also flagged. Keys and objective types that belong to a
## later milestone are named as such instead of being called unknown.

const SCHEMA_VERSION: int = 1

const TOP_LEVEL_KEYS: Array[String] = [
	"schema_version", "id", "sequence", "title", "briefing", "devices", "links",
	"spare_cables", "reserved_ports", "objectives", "hints", "debrief", "solution",
]
const FUTURE_TOP_LEVEL: Dictionary = {"logs": "M2", "report": "M2"}

const DEVICE_KEYS: Array[String] = ["id", "type", "model", "hostname", "rack", "slot", "desk", "config"]
const TYPE_KINDS: Dictionary = {
	"router": Device.Kind.ROUTER,
	"switch": Device.Kind.SWITCH,
	"host": Device.Kind.HOST,
	"server": Device.Kind.SERVER,
}
const FUTURE_NET_CONFIG: Dictionary = {"users": "M4", "domain_name": "M4", "lines": "M4"}
const FUTURE_SERVER_CONFIG: Dictionary = {"files": "M3", "services": "M3", "vulns": "M3"}

const LINK_KEYS: Array[String] = ["a", "b", "locked"]
const OBJECTIVE_COMMON_KEYS: Array[String] = ["id", "type", "description", "order"]
const OBJECTIVE_PARAMS: Dictionary = {
	"ping": ["from", "to_ip", "to_device", "via"],
	"config": ["device", "path", "equals"],
}
const FUTURE_OBJECTIVES: Dictionary = {
	"report": "M2", "vuln_patched": "M3", "exploit_test": "M3", "ssh": "M4", "no_ping": "M5",
}
const ROUTE_KEYS: Array[String] = ["network", "mask", "next_hop"]
const HOST_CONFIG_PATHS: Array[String] = ["hostname", "ip", "mask", "gateway", "locked"]

static var _plain_key: RegEx = _compile("^[A-Za-z_][A-Za-z0-9_]*$")
static var _scenario_id: RegEx = _compile("^[a-z][a-z0-9_]*$")
static var _device_id: RegEx = _compile("^[A-Za-z0-9][A-Za-z0-9_-]*$")

var _errors: Array[String] = []
## device id -> {type, model}; either is "" when that field was itself invalid.
var _devices: Dictionary = {}
var _reserved: Dictionary = {}  # canonical port -> true
var _start_ports: Dictionary = {}  # canonical port -> index of the link using it


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


## `file_id` is the file's base name; when given, `id` must equal it.
static func validate(data: Variant, file_id: String = "") -> Array[String]:
	var v := ScenarioValidator.new()
	v._check_root(data, file_id)
	return v._errors


# --- helpers ---------------------------------------------------------------------


func _err(path: String, message: String) -> void:
	_errors.append("%s: %s" % [path, message])


func _key(path: String, key: String) -> String:
	var part: String = ".%s" % key if _plain_key.search(key) != null else '["%s"]' % key
	return part.trim_prefix(".") if path.is_empty() else path + part


func _type_name(value: Variant) -> String:
	return type_string(typeof(value))


## Reports and returns false unless `value` is a JSON object.
func _expect_dict(value: Variant, path: String) -> bool:
	if value is Dictionary:
		return true
	_err(path, "must be an object")
	return false


func _expect_array(value: Variant, path: String) -> bool:
	if value is Array:
		return true
	_err(path, "must be an array")
	return false


func _expect_string(value: Variant, path: String) -> bool:
	if value is String and not (value as String).is_empty():
		return true
	_err(path, "must be a non-empty string")
	return false


func _expect_int(value: Variant, path: String, minimum: int) -> bool:
	if ScenarioFields.is_int(value) and ScenarioFields.to_int(value) >= minimum:
		return true
	_err(path, "must be an integer of at least %d" % minimum)
	return false


## Flags every key not in `allowed`; `future` keys are named by milestone.
func _check_keys(obj: Dictionary, path: String, allowed: Array, future: Dictionary = {}) -> void:
	for k: Variant in obj:
		var name: String = str(k)
		if allowed.has(name):
			continue
		if future.has(name):
			_err(_key(path, name), "is not supported yet (arrives in %s)" % future[name])
		else:
			_err(_key(path, name), "unknown key")


## Checks a required field exists; reports "required" if not.
func _need(obj: Dictionary, key: String, path: String) -> bool:
	if obj.has(key):
		return true
	_err(_key(path, key), "required")
	return false


# --- top level -------------------------------------------------------------------


func _check_root(data: Variant, file_id: String) -> void:
	if not data is Dictionary:
		_err("$", "a scenario must be a JSON object")
		return
	var d: Dictionary = data
	_check_schema_version(d)
	_check_id(d, file_id)
	if _need(d, "sequence", ""):
		_expect_int(d["sequence"], "sequence", 1)
	for key in ["title", "briefing"]:
		if _need(d, key, ""):
			_expect_string(d[key], key)
	_check_devices(d)
	_check_reserved_ports(d)
	_check_links(d)
	if d.has("spare_cables"):
		_expect_int(d["spare_cables"], "spare_cables", 0)
	_check_objectives(d)
	_check_hints(d)
	if d.has("debrief"):
		_expect_string(d["debrief"], "debrief")
	_check_solution(d)
	_check_keys(d, "", TOP_LEVEL_KEYS, FUTURE_TOP_LEVEL)


func _check_schema_version(d: Dictionary) -> void:
	if not _need(d, "schema_version", ""):
		return
	var v: Variant = d["schema_version"]
	if not ScenarioFields.is_int(v) or ScenarioFields.to_int(v) != SCHEMA_VERSION:
		_err("schema_version", "must be %d" % SCHEMA_VERSION)


func _check_id(d: Dictionary, file_id: String) -> void:
	if not _need(d, "id", ""):
		return
	var v: Variant = d["id"]
	if not v is String or _scenario_id.search(v) == null:
		_err("id", "must be snake_case (lowercase letters, digits and underscores, starting with a letter)")
	elif not file_id.is_empty() and v != file_id:
		_err("id", 'must match the file name "%s"' % file_id)


# --- devices ---------------------------------------------------------------------


func _check_devices(d: Dictionary) -> void:
	if not _need(d, "devices", ""):
		return
	if not _expect_array(d["devices"], "devices"):
		return
	var list: Array = d["devices"]
	if list.is_empty():
		_err("devices", "needs at least one device")
		return
	var placements: Dictionary = {}  # "rack_a/3" or "desk_1" -> device id
	for i in list.size():
		_check_device(list[i], "devices[%d]" % i, placements)


func _check_device(entry: Variant, path: String, placements: Dictionary) -> void:
	if not _expect_dict(entry, path):
		return
	var dev: Dictionary = entry
	_check_keys(dev, path, DEVICE_KEYS)
	var id: String = _check_device_id(dev, path)
	var type: String = _check_device_type(dev, path)
	var model: String = _check_device_model(dev, path, type)
	if not id.is_empty():
		_devices[id] = {"type": type, "model": model}
	if dev.has("hostname"):
		var hn: String = _hostname_problem(dev["hostname"])
		if not hn.is_empty():
			_err(_key(path, "hostname"), "must " + hn)
	_check_placement(dev, path, type, id, placements)
	if dev.has("config"):
		_check_device_config(dev["config"], _key(path, "config"), type, model)


func _hostname_problem(value: Variant) -> String:
	return ScenarioFields.check_value(ScenarioFields.Kind.NAME, value)


## Returns the id if it is valid and not a repeat, else "".
func _check_device_id(dev: Dictionary, path: String) -> String:
	if not _need(dev, "id", path):
		return ""
	var v: Variant = dev["id"]
	var p: String = _key(path, "id")
	if not v is String or _device_id.search(v) == null:
		_err(p, "must be letters, digits, '-' or '_' (no spaces or ':')")
		return ""
	if _devices.has(v):
		_err(p, 'duplicate device id "%s"' % v)
		return ""
	return v


func _check_device_type(dev: Dictionary, path: String) -> String:
	if not _need(dev, "type", path):
		return ""
	var v: Variant = dev["type"]
	if not v is String or not TYPE_KINDS.has(v):
		_err(_key(path, "type"), "must be one of router, switch, host, server")
		return ""
	return v


func _check_device_model(dev: Dictionary, path: String, type: String) -> String:
	if not _need(dev, "model", path):
		return ""
	var v: Variant = dev["model"]
	var p: String = _key(path, "model")
	if not v is String or not DeviceModels.has_model(v):
		_err(p, "unknown model %s" % (('"%s"' % v) if v is String else _type_name(v)))
		return ""
	if not type.is_empty() and DeviceModels.kind_of(v) != TYPE_KINDS[type]:
		_err(p, 'model "%s" is not a %s' % [v, type])
		return ""
	return v


## Hosts sit at a desk; everything else is racked.
func _check_placement(dev: Dictionary, path: String, type: String, id: String, placements: Dictionary) -> void:
	var racked: bool = type != "host"
	if type.is_empty():
		return
	var spot: String = ""
	if racked:
		if dev.has("desk"):
			_err(_key(path, "desk"), "only hosts use desk; racked devices use rack and slot")
		var rack_ok: bool = _need(dev, "rack", path) and _expect_string(dev["rack"], _key(path, "rack"))
		var slot_ok: bool = _need(dev, "slot", path) and _expect_int(dev["slot"], _key(path, "slot"), 1)
		if rack_ok and slot_ok:
			spot = "%s/%d" % [dev["rack"], ScenarioFields.to_int(dev["slot"])]
	else:
		for key in ["rack", "slot"]:
			if dev.has(key):
				_err(_key(path, key), "hosts use desk, not rack and slot")
		if _need(dev, "desk", path) and _expect_string(dev["desk"], _key(path, "desk")):
			spot = str(dev["desk"])
	if spot.is_empty() or id.is_empty():
		return
	if placements.has(spot):
		_err(path, 'same spot as "%s" (%s)' % [placements[spot], spot])
	else:
		placements[spot] = id


# --- device config ---------------------------------------------------------------


func _check_device_config(value: Variant, path: String, type: String, model: String) -> void:
	if not _expect_dict(value, path):
		return
	var cfg: Dictionary = value
	match type:
		"router", "switch":
			_check_net_config(cfg, path, type, model)
		"host", "server":
			_check_host_config(cfg, path, type)


func _check_net_config(cfg: Dictionary, path: String, type: String, model: String) -> void:
	var own: String = "vlans" if type == "switch" else "routes"
	var other: String = "routes" if type == "switch" else "vlans"
	_check_keys(cfg, path, ["interfaces", "enable_secret", own, other], FUTURE_NET_CONFIG)
	if cfg.has(other):
		_err(_key(path, other), "only %s have %s" % [("routers" if other == "routes" else "switches"), other])
	if cfg.has("enable_secret"):
		var bad: String = ScenarioFields.check_value(ScenarioFields.Kind.STRING, cfg["enable_secret"])
		if not bad.is_empty():
			_err(_key(path, "enable_secret"), "must " + bad)
	if cfg.has("interfaces"):
		_check_interfaces(cfg["interfaces"], _key(path, "interfaces"), type, model)
	if type == "switch" and cfg.has("vlans"):
		_check_vlans(cfg["vlans"], _key(path, "vlans"))
	if type == "router" and cfg.has("routes"):
		_check_routes(cfg["routes"], _key(path, "routes"))


func _check_interfaces(value: Variant, path: String, type: String, model: String) -> void:
	if not _expect_dict(value, path):
		return
	var seen: Dictionary = {}  # canonical name -> the key as written
	for k: Variant in value:
		var written: String = str(k)
		var p: String = _key(path, written)
		var canonical: String = IfName.normalize(written)
		if canonical.is_empty():
			_err(p, 'invalid interface name "%s"' % written)
			continue
		if seen.has(canonical):
			_err(p, 'same interface as "%s"' % seen[canonical])
			continue
		seen[canonical] = written
		var problem: String = _interface_problem(canonical, type, model)
		if not problem.is_empty():
			_err(p, problem)
			continue
		var fields: Variant = value[k]
		if _expect_dict(fields, p):
			_check_interface_fields(fields, p, type, IfName.is_subinterface(canonical))


## "" when `canonical` can exist on this device (a router may also have
## subinterfaces of its real ports); otherwise why not. A device with an
## unknown model is not checked.
func _interface_problem(canonical: String, type: String, model: String) -> String:
	var sub: bool = IfName.is_subinterface(canonical)
	if sub and type != "router":
		return "subinterfaces exist only on routers"
	if model.is_empty():
		return ""
	var real: String = IfName.parent_of(canonical) if sub else canonical
	if DeviceModels.interface_names(model).has(real):
		return ""
	return 'unknown interface "%s" for model %s' % [canonical, model]


func _check_interface_fields(fields: Dictionary, path: String, type: String, is_sub: bool) -> void:
	var table: Dictionary = ScenarioFields.ROUTER_INTERFACE_FIELDS if type == "router" else ScenarioFields.SWITCH_INTERFACE_FIELDS
	for k: Variant in fields:
		var name: String = str(k)
		var p: String = _key(path, name)
		if not table.has(name):
			_err(p, "unknown key" if not _field_of_other_type(name, type) else "not valid on a %s interface" % type)
		elif name == "dot1q_vlan" and not is_sub:
			_err(p, "only subinterfaces have dot1q_vlan")
		else:
			var bad: String = ScenarioFields.check_value(table[name], fields[k])
			if not bad.is_empty():
				_err(p, "must " + bad)
	if type == "router" and fields.has("ip") != fields.has("mask"):
		_err(path, "ip and mask must be given together")


func _field_of_other_type(name: String, type: String) -> bool:
	var other: Dictionary = ScenarioFields.SWITCH_INTERFACE_FIELDS if type == "router" else ScenarioFields.ROUTER_INTERFACE_FIELDS
	return other.has(name)


func _check_vlans(value: Variant, path: String) -> void:
	if not _expect_dict(value, path):
		return
	for k: Variant in value:
		var p: String = _key(path, str(k))
		if ScenarioFields.parse_vlan_key(str(k)) == -1:
			_err(p, "VLAN ids are numbers from 1 to 4094")
			continue
		var bad: String = ScenarioFields.check_value(ScenarioFields.Kind.NAME, value[k])
		if not bad.is_empty():
			_err(p, "name must " + bad)


func _check_routes(value: Variant, path: String) -> void:
	if not _expect_array(value, path):
		return
	var routes: Array = value
	for i in routes.size():
		var p: String = "%s[%d]" % [path, i]
		if not _expect_dict(routes[i], p):
			continue
		var route: Dictionary = routes[i]
		_check_keys(route, p, ROUTE_KEYS)
		var good: Dictionary = {}
		for key in ROUTE_KEYS:
			if not _need(route, key, p):
				continue
			var kind: ScenarioFields.Kind = ScenarioFields.Kind.MASK if key == "mask" else ScenarioFields.Kind.IPV4
			var bad: String = ScenarioFields.check_value(kind, route[key])
			if bad.is_empty():
				good[key] = route[key]
			else:
				_err(_key(p, key), "must " + bad)
		if good.has("network") and good.has("mask"):
			var net: int = IPv4.parse(good["network"])
			var mask: int = IPv4.parse_mask(good["mask"])
			if IPv4.network(net, mask) != net:
				_err(_key(p, "network"), "%s is not a network address for mask %s" % [good["network"], good["mask"]])


func _check_host_config(cfg: Dictionary, path: String, type: String) -> void:
	_check_keys(cfg, path, ScenarioFields.HOST_FIELDS.keys(), FUTURE_SERVER_CONFIG if type == "server" else {})
	for k: Variant in cfg:
		var name: String = str(k)
		if ScenarioFields.HOST_FIELDS.has(name):
			var bad: String = ScenarioFields.check_value(ScenarioFields.HOST_FIELDS[name], cfg[k])
			if not bad.is_empty():
				_err(_key(path, name), "must " + bad)
	if cfg.has("ip") != cfg.has("mask"):
		_err(path, "ip and mask must be given together")


# --- ports, reserved ports, links ------------------------------------------------


## The canonical "<device>:<Interface>" for a valid socket, or "" after
## reporting why not. Only physical interfaces have sockets.
func _check_port(value: Variant, path: String) -> String:
	if not value is String or not (value as String).contains(":"):
		_err(path, 'must be a port such as "S1:Fa0/1"')
		return ""
	var text: String = value
	var dev_id: String = IfName.port_device(text)
	var raw: String = IfName.port_iface(text)
	if not _devices.has(dev_id):
		_err(path, 'unknown device "%s"' % dev_id)
		return ""
	var canonical: String = IfName.normalize(raw)
	if canonical.is_empty():
		_err(path, 'invalid interface name "%s"' % raw)
		return ""
	if IfName.is_subinterface(canonical):
		_err(path, "a subinterface has no socket; cables use physical ports")
		return ""
	var model: String = _devices[dev_id]["model"]
	if not model.is_empty() and not DeviceModels.interface_names(model).has(canonical):
		_err(path, 'unknown interface "%s" for model %s' % [canonical, model])
		return ""
	return "%s:%s" % [dev_id, canonical]


func _check_reserved_ports(d: Dictionary) -> void:
	if not d.has("reserved_ports"):
		return
	if not _expect_array(d["reserved_ports"], "reserved_ports"):
		return
	var list: Array = d["reserved_ports"]
	for i in list.size():
		var p: String = "reserved_ports[%d]" % i
		var port: String = _check_port(list[i], p)
		if port.is_empty():
			continue
		if _reserved.has(port):
			_err(p, "%s is already reserved" % port)
		_reserved[port] = true


func _check_links(d: Dictionary) -> void:
	if not _need(d, "links", ""):
		return
	if not _expect_array(d["links"], "links"):
		return
	var list: Array = d["links"]
	for i in list.size():
		var p: String = "links[%d]" % i
		if not _expect_dict(list[i], p):
			continue
		var link: Dictionary = list[i]
		_check_keys(link, p, LINK_KEYS)
		var ends: Array[String] = []
		for end in ["a", "b"]:
			var port: String = ""
			if _need(link, end, p):
				port = _check_port(link[end], _key(p, end))
			ends.append(port)
			if not port.is_empty():
				_check_start_port(port, _key(p, end), i)
		if not ends[0].is_empty() and not ends[1].is_empty() and IfName.port_device(ends[0]) == IfName.port_device(ends[1]):
			_err(p, "a cable needs two different devices")
		if link.has("locked") and not link["locked"] is bool:
			_err(_key(p, "locked"), "must be true or false")


## A start link may not use a reserved port or a port another link has.
func _check_start_port(port: String, path: String, link_index: int) -> void:
	if _reserved.has(port):
		_err(path, "%s is reserved; no cable may use it" % port)
	if _start_ports.has(port):
		_err(path, "%s is already used by links[%d]" % [port, _start_ports[port]])
	else:
		_start_ports[port] = link_index


# --- objectives ------------------------------------------------------------------


func _check_objectives(d: Dictionary) -> void:
	if not _need(d, "objectives", ""):
		return
	if not _expect_array(d["objectives"], "objectives"):
		return
	var list: Array = d["objectives"]
	if list.is_empty():
		_err("objectives", "needs at least one objective")
		return
	var ids: Dictionary = {}
	for i in list.size():
		_check_objective(list[i], "objectives[%d]" % i, ids)


func _check_objective(entry: Variant, path: String, ids: Dictionary) -> void:
	if not _expect_dict(entry, path):
		return
	var obj: Dictionary = entry
	_check_objective_id(obj, path, ids)
	if _need(obj, "description", path):
		_expect_string(obj["description"], _key(path, "description"))
	if obj.has("order"):
		_expect_int(obj["order"], _key(path, "order"), 1)
	var type: String = ""
	if _need(obj, "type", path):
		var v: Variant = obj["type"]
		if v is String and OBJECTIVE_PARAMS.has(v):
			type = v
		elif v is String and FUTURE_OBJECTIVES.has(v):
			_err(_key(path, "type"), '"%s" is not supported yet (arrives in %s)' % [v, FUTURE_OBJECTIVES[v]])
		else:
			_err(_key(path, "type"), "unknown objective type" if v is String else "must be a string")
	if type.is_empty():
		return
	var allowed: Array = OBJECTIVE_COMMON_KEYS.duplicate()
	allowed.append_array(OBJECTIVE_PARAMS[type])
	_check_keys(obj, path, allowed)
	if type == "ping":
		_check_ping_objective(obj, path)
	else:
		_check_config_objective(obj, path)


func _check_objective_id(obj: Dictionary, path: String, ids: Dictionary) -> void:
	if not _need(obj, "id", path):
		return
	var v: Variant = obj["id"]
	var p: String = _key(path, "id")
	if not v is String or _scenario_id.search(v) == null:
		_err(p, "must be snake_case (lowercase letters, digits and underscores, starting with a letter)")
	elif ids.has(v):
		_err(p, 'duplicate objective id "%s"' % v)
	else:
		ids[v] = true


## The device id in obj[key] if it names a scenario device, else "".
func _device_ref(obj: Dictionary, key: String, path: String, required: bool) -> String:
	if not obj.has(key):
		if required:
			_err(_key(path, key), "required")
		return ""
	var v: Variant = obj[key]
	var p: String = _key(path, key)
	if not v is String:
		_err(p, "must be a device id")
		return ""
	if not _devices.has(v):
		_err(p, 'unknown device "%s"' % v)
		return ""
	return v


func _check_ping_objective(obj: Dictionary, path: String) -> void:
	var from: String = _device_ref(obj, "from", path, true)
	if not from.is_empty() and _devices[from]["type"] == "switch":
		_err(_key(path, "from"), "a switch has no address to ping from")
	if _need(obj, "to_ip", path):
		var bad: String = ScenarioFields.check_value(ScenarioFields.Kind.IPV4, obj["to_ip"])
		if not bad.is_empty():
			_err(_key(path, "to_ip"), "must " + bad)
	_device_ref(obj, "to_device", path, false)
	var via: String = _device_ref(obj, "via", path, false)
	if not via.is_empty() and not _devices[via]["type"].is_empty() and _devices[via]["type"] != "router":
		_err(_key(path, "via"), "must be a router (only routers forward packets)")


# --- config objectives ---------------------------------------------------------------


func _check_config_objective(obj: Dictionary, path: String) -> void:
	var dev: String = _device_ref(obj, "device", path, true)
	var has_equals: bool = _need(obj, "equals", path)
	if not obj.has("path"):
		_err(_key(path, "path"), "required")
		return
	var keys: Array[String] = _path_keys(obj["path"], _key(path, "path"))
	# A device whose type was itself invalid can't be checked further.
	if keys.is_empty() or dev.is_empty() or _devices[dev]["type"].is_empty():
		return
	var leaf: Variant = _check_config_path(keys, _key(path, "path"), _devices[dev]["type"], _devices[dev]["model"])
	if leaf != null and has_equals:
		_check_equals(obj["equals"], _key(path, "equals"), leaf)


## A path is a key or an array of keys; both become a list of keys.
func _path_keys(value: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if value is String and not (value as String).is_empty():
		out.append(value)
		return out
	if not value is Array or (value as Array).is_empty():
		_err(path, "must be a key or a non-empty array of keys")
		return out
	for part: Variant in value:
		if not part is String or (part as String).is_empty():
			_err(path, "every key must be a non-empty string")
			out.clear()
			return out
		out.append(part)
	return out


## Validates the path against the device's config and returns what `equals`
## must look like, as {kind, fields?}; null (after reporting) if the path is bad.
## Valid paths: hostname; interfaces/<name>[/<field>]; vlans/<id> (switch);
## ip, mask, gateway, locked (host or server).
func _check_config_path(keys: Array[String], path: String, type: String, model: String) -> Variant:
	var head: String = keys[0]
	if type == "host" or type == "server":
		if keys.size() == 1 and HOST_CONFIG_PATHS.has(head):
			return {"kind": "hostname"} if head == "hostname" else {"kind": ScenarioFields.HOST_FIELDS[head]}
		_err(path, 'unknown config path for a %s (use one of %s)' % [type, ", ".join(HOST_CONFIG_PATHS)])
		return null
	if head == "hostname" and keys.size() == 1:
		return {"kind": "hostname"}
	if head == "vlans" and type == "switch" and keys.size() == 2:
		if ScenarioFields.parse_vlan_key(keys[1]) == -1:
			_err(path, "VLAN ids are numbers from 1 to 4094")
			return null
		return {"kind": "vlan_name"}
	if head == "interfaces" and keys.size() >= 2 and keys.size() <= 3:
		return _check_interface_path(keys, path, type, model)
	var options: String = "hostname, interfaces" + (", vlans" if type == "switch" else "")
	_err(path, "unknown config path for a %s (start with one of %s)" % [type, options])
	return null


func _check_interface_path(keys: Array[String], path: String, type: String, model: String) -> Variant:
	var canonical: String = IfName.normalize(keys[1])
	if canonical.is_empty():
		_err(path, 'invalid interface name "%s"' % keys[1])
		return null
	var problem: String = _interface_problem(canonical, type, model)
	if not problem.is_empty():
		_err(path, problem)
		return null
	var table: Dictionary = ScenarioFields.ROUTER_INTERFACE_FIELDS if type == "router" else ScenarioFields.SWITCH_INTERFACE_FIELDS
	if keys.size() == 2:
		return {"kind": "interface", "fields": table, "sub": IfName.is_subinterface(canonical)}
	if not table.has(keys[2]):
		_err(path, 'unknown interface field "%s" (use one of %s)' % [keys[2], ", ".join(table.keys())])
		return null
	if keys[2] == "dot1q_vlan" and not IfName.is_subinterface(canonical):
		_err(path, "only subinterfaces have dot1q_vlan")
		return null
	return {"kind": table[keys[2]]}


## `equals` must fit the leaf the path points at. null is always allowed: it
## means "not set" (or, for an interface or VLAN, "doesn't exist").
func _check_equals(value: Variant, path: String, leaf: Dictionary) -> void:
	if value == null:
		return
	var kind: Variant = leaf["kind"]
	if kind is String and kind == "interface":
		_check_interface_equals(value, path, leaf)
		return
	var bad: String
	if kind is String:
		bad = ScenarioFields.check_value(ScenarioFields.Kind.NAME, value)
	else:
		bad = ScenarioFields.check_value(kind, value)
	if not bad.is_empty():
		_err(path, "must " + bad + " (or null)")


func _check_interface_equals(value: Variant, path: String, leaf: Dictionary) -> void:
	if not value is Dictionary:
		_err(path, "must be an object of interface fields (or null)")
		return
	var table: Dictionary = leaf["fields"]
	for k: Variant in value:
		var name: String = str(k)
		var p: String = _key(path, name)
		if not table.has(name):
			_err(p, 'unknown interface field (use one of %s)' % ", ".join(table.keys()))
		elif name == "dot1q_vlan" and not leaf["sub"]:
			_err(p, "only subinterfaces have dot1q_vlan")
		elif value[k] != null:
			var bad: String = ScenarioFields.check_value(table[name], value[k])
			if not bad.is_empty():
				_err(p, "must " + bad + " (or null)")


# --- hints and solution ----------------------------------------------------------


func _check_hints(d: Dictionary) -> void:
	if not d.has("hints"):
		return
	if not _expect_array(d["hints"], "hints"):
		return
	var reasons: Array = PingResult.FailReason.keys()
	reasons.erase("NONE")
	var seen: Dictionary = {}
	var list: Array = d["hints"]
	for i in list.size():
		var p: String = "hints[%d]" % i
		if not _expect_dict(list[i], p):
			continue
		var hint: Dictionary = list[i]
		_check_keys(hint, p, ["reason", "text"])
		if _need(hint, "reason", p):
			var r: Variant = hint["reason"]
			if not r is String or not reasons.has(r):
				_err(_key(p, "reason"), "must be a ping fail reason (%s)" % ", ".join(reasons))
			elif seen.has(r):
				_err(_key(p, "reason"), 'a second hint for "%s"' % r)
			else:
				seen[r] = true
		if _need(hint, "text", p):
			_expect_string(hint["text"], _key(p, "text"))


func _check_solution(d: Dictionary) -> void:
	if not _need(d, "solution", ""):
		return
	if not _expect_array(d["solution"], "solution"):
		return
	var list: Array = d["solution"]
	if list.is_empty():
		_err("solution", "needs at least one step")
		return
	var used: Dictionary = _start_ports.duplicate()
	var cables: int = 0
	for i in list.size():
		cables += _check_solution_step(list[i], "solution[%d]" % i, used)
	# An invalid spare_cables is already reported; don't pile a second error on it.
	var spare: int = 0
	if d.has("spare_cables"):
		var v: Variant = d["spare_cables"]
		spare = ScenarioFields.to_int(v) if ScenarioFields.is_int(v) and ScenarioFields.to_int(v) >= 0 else -1
	if spare >= 0 and cables > spare:
		_err("solution", "plugs in %d cable(s) but spare_cables is %d" % [cables, spare])


## Returns how many cables the step plugs in.
func _check_solution_step(entry: Variant, path: String, used: Dictionary) -> int:
	if not _expect_dict(entry, path):
		return 0
	var step: Dictionary = entry
	if step.has("link") == step.has("device"):
		_err(path, 'a step has either "device" and "commands", or "link"')
		return 0
	if step.has("link"):
		_check_keys(step, path, ["link"])
		return _check_solution_link(step["link"], _key(path, "link"), used)
	_check_keys(step, path, ["device", "commands"])
	_device_ref(step, "device", path, true)
	if _need(step, "commands", path):
		_check_commands(step["commands"], _key(path, "commands"))
	return 0


func _check_commands(value: Variant, path: String) -> void:
	if not _expect_array(value, path):
		return
	var list: Array = value
	if list.is_empty():
		_err(path, "needs at least one command")
	for i in list.size():
		if not list[i] is String or (list[i] as String).strip_edges().is_empty():
			_err("%s[%d]" % [path, i], "must be a non-empty command")


func _check_solution_link(value: Variant, path: String, used: Dictionary) -> int:
	if not _expect_dict(value, path):
		return 0
	var link: Dictionary = value
	_check_keys(link, path, ["a", "b"])
	var ends: Array[String] = []
	for end in ["a", "b"]:
		var port: String = ""
		if _need(link, end, path):
			port = _check_port(link[end], _key(path, end))
		ends.append(port)
	for i in ends.size():
		var port: String = ends[i]
		if port.is_empty():
			continue
		var p: String = _key(path, "a" if i == 0 else "b")
		if _reserved.has(port):
			_err(p, "%s is reserved; the player cannot cable it" % port)
		elif used.has(port):
			_err(p, "%s is already cabled" % port)
		used[port] = true
	return 1
