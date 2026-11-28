class_name DeviceView
extends RefCounted
## Read-only snapshot of a device, deep-copied at creation. Accessors return
## fresh copies, so callers can never reach sim state through a view.

var _hostname: String
var _kind: Device.Kind
var _names: Array[String] = []
var _interfaces: Dictionary = {}
var _gateway: String = ""
var _locked: bool = false
var _vlans: Dictionary = {}
var _static_routes: Array = []
var _services: Array[Dictionary] = []


func _init(d: Device, oper: Dictionary[String, bool]) -> void:
	_hostname = d.hostname
	_kind = d.kind()
	for name: String in d.interfaces:
		var i: Interface = d.interfaces[name]
		_names.append(name)
		_interfaces[name] = {
			"name": i.full_name,
			"short_name": i.short_name,
			"admin_up": i.admin_up,
			"oper_up": oper.get(name, false),
			"ip": i.ip,
			"mask": i.mask,
			"peer": null if i.peer_port == "" else i.peer_port,
			"mode": i.mode,
			"access_vlan": i.access_vlan,
			"trunk_allowed_all": i.trunk_allowed_all,
			"trunk_allowed": i.trunk_allowed.duplicate(),
			"parent": i.parent,
			"dot1q_vlan": i.dot1q_vlan,
		}
	if d is Host:
		_gateway = (d as Host).gateway
		_locked = (d as Host).locked
	if d is Server:
		# Only the listed keys, so nothing hidden can ride along in a service entry.
		for service: Variant in (d as Server).services:
			if service is Dictionary:
				_services.append({
					"id": str(service.get("id", "")),
					"port": ScenarioFields.to_int(service.get("port", 0)),
					"root": str(service.get("root", "")),
				})
	if d is Switch:
		_vlans = (d as Switch).vlans.duplicate()
	if d is Router:
		_static_routes = (d as Router).static_routes.duplicate(true)


func hostname() -> String:
	return _hostname


func kind() -> Device.Kind:
	return _kind


func interface_names() -> Array[String]:
	return _names.duplicate()


## A fresh copy per call; {} if the interface does not exist.
func interface(name: String) -> Dictionary:
	var key: String = IfName.normalize(name)
	if not _interfaces.has(key):
		return {}
	return (_interfaces[key] as Dictionary).duplicate(true)


func gateway() -> String:
	return _gateway


func locked() -> bool:
	return _locked


func vlans() -> Dictionary:
	return _vlans.duplicate()


func static_routes() -> Array:
	return _static_routes.duplicate(true)


## A server's services, each `{id: String, port: int, root: String}`, in
## declaration order; empty for any other device. Source files, vulns, accepted
## fixes, fixtures and exploits are never in a view.
func services() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for service in _services:
		out.append(service.duplicate())
	return out
