class_name ScenarioFields
extends RefCounted
## Value rules shared by everything that reads scenario config: the validator
## (starting config and `config` objectives), and later the loader and the
## objective evaluator. JSON has no integer type, so a whole-number float counts
## as an int.

enum Kind { BOOL, STRING, NAME, IPV4, MASK, VLAN_ID, VLAN_LIST, SWITCHPORT_MODE }

const VLAN_MIN: int = 1
const VLAN_MAX: int = 4094
const SWITCHPORT_MODES: Array[String] = ["access", "trunk"]

## Fields a starting `interfaces.<name>` object (or a `config` objective on one)
## can set, by device type.
const ROUTER_INTERFACE_FIELDS: Dictionary = {
	"admin_up": Kind.BOOL,
	"ip": Kind.IPV4,
	"mask": Kind.MASK,
	"dot1q_vlan": Kind.VLAN_ID,
}
const SWITCH_INTERFACE_FIELDS: Dictionary = {
	"admin_up": Kind.BOOL,
	"mode": Kind.SWITCHPORT_MODE,
	"access_vlan": Kind.VLAN_ID,
	"trunk_allowed": Kind.VLAN_LIST,
}
const HOST_FIELDS: Dictionary = {
	"ip": Kind.IPV4,
	"mask": Kind.MASK,
	"gateway": Kind.IPV4,
	"locked": Kind.BOOL,
}


static func is_int(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floorf(value)


static func to_int(value: Variant) -> int:
	return int(value)


## "10" -> 10; -1 if the key is not a VLAN id (digits only, 1 to 4094).
static func parse_vlan_key(key: String) -> int:
	if key.is_empty() or not key.is_valid_int() or key.begins_with("+") or key.begins_with("-") or (key.length() > 1 and key.begins_with("0")):
		return -1
	var n: int = key.to_int()
	return n if n >= VLAN_MIN and n <= VLAN_MAX else -1


## "" when `value` fits `kind`, otherwise the reason, ready to follow "must".
static func check_value(kind: Kind, value: Variant) -> String:
	match kind:
		Kind.BOOL:
			return "" if value is bool else "be true or false"
		Kind.STRING:
			return "" if value is String and not (value as String).is_empty() else "be a non-empty string"
		Kind.NAME:
			return "" if value is String and not (value as String).is_empty() and not _has_space(value) else "be a single word with no spaces"
		Kind.IPV4:
			return "" if value is String and IPv4.is_valid(value) else "be an IPv4 address such as 192.168.10.1"
		Kind.MASK:
			return "" if value is String and IPv4.parse_mask(value) != IPv4.INVALID else "be a subnet mask such as 255.255.255.0"
		Kind.VLAN_ID:
			return "" if is_int(value) and to_int(value) >= VLAN_MIN and to_int(value) <= VLAN_MAX else "be a VLAN id from 1 to 4094"
		Kind.VLAN_LIST:
			return _check_vlan_list(value)
		Kind.SWITCHPORT_MODE:
			return "" if value is String and SWITCHPORT_MODES.has(value) else 'be "access" or "trunk"'
	return "be valid"


static func _has_space(text: String) -> bool:
	return text.contains(" ") or text.contains("\t") or text.contains("\n")


static func _check_vlan_list(value: Variant) -> String:
	if not value is Array:
		return "be a list of VLAN ids"
	var list: Array = value
	if list.is_empty():
		return "not be empty (leave it out to allow every VLAN)"
	var seen: Dictionary = {}
	for v: Variant in list:
		if not is_int(v) or to_int(v) < VLAN_MIN or to_int(v) > VLAN_MAX:
			return "be a list of VLAN ids from 1 to 4094"
		if seen.has(to_int(v)):
			return "list each VLAN once"
		seen[to_int(v)] = true
	return ""
