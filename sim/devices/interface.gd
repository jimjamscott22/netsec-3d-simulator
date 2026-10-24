class_name Interface
extends RefCounted
## One interface (or subinterface). Plain data: oper state is derived by
## NetworkSim, which owns the cable graph; this only stores `peer_port`.

enum Mode { ACCESS, TRUNK }

var device_id: String
var full_name: String
var short_name: String
var admin_up: bool
var ip: String = ""
var mask: String = ""
var peer_port: String = ""
var mode: Mode = Mode.ACCESS
var access_vlan: int = 1
var trunk_allowed_all: bool = true
var trunk_allowed: Array[int] = []
var parent: String = ""
var dot1q_vlan: int = 0


func _init(p_device_id: String, p_name: String, p_admin_up: bool) -> void:
	device_id = p_device_id
	full_name = IfName.normalize(p_name)
	short_name = IfName.short_name(full_name)
	admin_up = p_admin_up


func port() -> String:
	return "%s:%s" % [device_id, full_name]


func is_sub() -> bool:
	return IfName.is_subinterface(full_name)


func has_address() -> bool:
	return IPv4.is_valid(ip) and IPv4.parse_mask(mask) != IPv4.INVALID


func trunk_allows(vlan: int) -> bool:
	return trunk_allowed_all or trunk_allowed.has(vlan)
