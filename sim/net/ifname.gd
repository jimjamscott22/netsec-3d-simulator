class_name IfName
extends RefCounted
## Interface name normalizer. Every function returns ""/-1/false for invalid
## input. Ports are addressed as "<device_id>:<CanonicalName>".

const TYPES: Array[Dictionary] = [
	{"full": "GigabitEthernet", "short": "Gi"},
	{"full": "FastEthernet", "short": "Fa"},
	{"full": "Ethernet", "short": "Eth"},
]

static var _pattern: RegEx = _build_pattern()


static func _build_pattern() -> RegEx:
	var re := RegEx.new()
	re.compile("^([A-Za-z]+)\\s*(\\d+(?:/\\d+)*)(?:\\.(\\d+))?$")
	return re


## Splits a raw name into {type, slots, sub}; {} if invalid. `type` is an
## index into TYPES, `sub` is 0 for a physical interface.
static func _parse(raw: String) -> Dictionary:
	var m: RegExMatch = _pattern.search(raw)
	if m == null:
		return {}
	var letters: String = m.get_string(1).to_lower()
	var type_idx: int = -1
	for i in TYPES.size():
		var full: String = TYPES[i]["full"]
		if full.to_lower().begins_with(letters):
			type_idx = i
			break
	if type_idx == -1:
		return {}
	var sub: int = 0
	if m.get_string(3) != "":
		sub = m.get_string(3).to_int()
		if sub < 1:
			return {}
	return {"type": type_idx, "slots": m.get_string(2), "sub": sub}


static func _render(parsed: Dictionary, key: String) -> String:
	var type_idx: int = parsed["type"]
	var name: String = str(TYPES[type_idx][key]) + str(parsed["slots"])
	var sub: int = parsed["sub"]
	if sub > 0:
		name += ".%d" % sub
	return name


static func normalize(raw: String) -> String:
	var parsed: Dictionary = _parse(raw)
	if parsed.is_empty():
		return ""
	return _render(parsed, "full")


static func short_name(full: String) -> String:
	var parsed: Dictionary = _parse(full)
	if parsed.is_empty():
		return ""
	return _render(parsed, "short")


static func is_subinterface(full: String) -> bool:
	return sub_id(full) > 0


static func parent_of(full: String) -> String:
	var parsed: Dictionary = _parse(full)
	if parsed.is_empty() or int(parsed["sub"]) == 0:
		return ""
	parsed["sub"] = 0
	return _render(parsed, "full")


static func sub_id(full: String) -> int:
	var parsed: Dictionary = _parse(full)
	if parsed.is_empty() or int(parsed["sub"]) == 0:
		return -1
	return parsed["sub"]


static func canonical_port(port: String) -> String:
	var idx: int = port.find(":")
	if idx <= 0:
		return ""
	var iface: String = normalize(port.substr(idx + 1))
	if iface.is_empty():
		return ""
	return port.substr(0, idx) + ":" + iface


static func port_device(port: String) -> String:
	var idx: int = port.find(":")
	if idx <= 0:
		return ""
	return port.substr(0, idx)


static func port_iface(port: String) -> String:
	var idx: int = port.find(":")
	if idx <= 0:
		return ""
	return port.substr(idx + 1)
