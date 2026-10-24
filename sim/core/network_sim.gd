class_name NetworkSim
extends RefCounted
## The only entry point for state changes. Owns the device registry, the
## cables and the spare-cable count, and emits SimEvents signals.

var events: SimEvents = SimEvents.new()

var _devices: Dictionary[String, Device] = {}
var _spare_cables: int
var _reserved: Dictionary[String, bool] = {}
var _locked: Dictionary[String, bool] = {}


func _init(spare_cables: int = 0) -> void:
	_spare_cables = spare_cables


func add_device(d: Device) -> bool:
	if _devices.has(d.id):
		return false
	_devices[d.id] = d
	return true


func get_device(id: String) -> Device:
	return _devices.get(id)


func device_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_devices.keys())
	ids.sort()
	return ids


## Accepts un-normalized interface names; null if the port does not exist.
func interface_at(port: String) -> Interface:
	var device: Device = get_device(IfName.port_device(port))
	if device == null:
		return null
	return device.interface(IfName.port_iface(port))


func spare_cables() -> int:
	return _spare_cables


func reserve_port(port: String) -> void:
	var i: Interface = interface_at(port)
	if i != null:
		_reserved[i.port()] = true


## Pre-existing scenario cabling: uses no spare cable, ignores reservations and
## emits no signals. Locked links cannot be unplugged by the player.
func add_fixed_link(a: String, b: String, locked: bool = true) -> LinkResult:
	var check: LinkResult = _check_endpoints(a, b)
	if not check.ok:
		return check
	var ia: Interface = interface_at(a)
	var ib: Interface = interface_at(b)
	if ia.peer_port != "" or ib.peer_port != "":
		return LinkResult.failure(LinkResult.Reason.PORT_IN_USE)
	_join(ia, ib)
	if locked:
		_locked[ia.port()] = true
		_locked[ib.port()] = true
	return LinkResult.success()


func connect_link(a: String, b: String) -> LinkResult:
	var check: LinkResult = _check_endpoints(a, b)
	if not check.ok:
		return check
	var ia: Interface = interface_at(a)
	var ib: Interface = interface_at(b)
	if _reserved.has(ia.port()) or _reserved.has(ib.port()):
		return LinkResult.failure(LinkResult.Reason.PORT_RESERVED)
	if ia.peer_port != "" or ib.peer_port != "":
		return LinkResult.failure(LinkResult.Reason.PORT_IN_USE)
	if _spare_cables <= 0:
		return LinkResult.failure(LinkResult.Reason.NO_SPARE_CABLE)
	var affected: Array[Interface] = _with_subinterfaces(ia) + _with_subinterfaces(ib)
	var before: Array[bool] = _oper_states(affected)
	_spare_cables -= 1
	_join(ia, ib)
	events.link_changed.emit(ia.port(), ib.port(), true)
	_emit_state_changes(affected, before)
	return LinkResult.success()


func disconnect_link(port: String) -> LinkResult:
	var ia: Interface = interface_at(port)
	if ia == null:
		return LinkResult.failure(LinkResult.Reason.UNKNOWN_PORT)
	if ia.peer_port == "":
		return LinkResult.failure(LinkResult.Reason.NOT_CONNECTED)
	if _locked.has(ia.port()):
		return LinkResult.failure(LinkResult.Reason.LOCKED)
	var ib: Interface = interface_at(ia.peer_port)
	var affected: Array[Interface] = _with_subinterfaces(ia) + _with_subinterfaces(ib)
	var before: Array[bool] = _oper_states(affected)
	var a_port: String = ia.port()
	var b_port: String = ib.port()
	ia.peer_port = ""
	ib.peer_port = ""
	_spare_cables += 1
	events.link_changed.emit(a_port, b_port, false)
	_emit_state_changes(affected, before)
	return LinkResult.success()


## The only place the oper-up rule lives. Physical: a cable and both ends
## admin up. Subinterface: parent oper-up and itself admin up.
func is_oper_up(port: String) -> bool:
	var i: Interface = interface_at(port)
	if i == null or not i.admin_up:
		return false
	if i.is_sub():
		return is_oper_up("%s:%s" % [i.device_id, i.parent])
	if i.peer_port == "":
		return false
	var peer: Interface = interface_at(i.peer_port)
	return peer != null and peer.admin_up


func device_view(id: String) -> DeviceView:
	var d: Device = get_device(id)
	if d == null:
		return null
	var oper: Dictionary[String, bool] = {}
	for name: String in d.interfaces:
		oper[name] = is_oper_up(d.interfaces[name].port())
	return DeviceView.new(d, oper)


func _check_endpoints(a: String, b: String) -> LinkResult:
	var ia: Interface = interface_at(a)
	var ib: Interface = interface_at(b)
	if ia == null or ib == null:
		return LinkResult.failure(LinkResult.Reason.UNKNOWN_PORT)
	if ia.is_sub() or ib.is_sub():
		return LinkResult.failure(LinkResult.Reason.NOT_PHYSICAL)
	if ia.device_id == ib.device_id:
		return LinkResult.failure(LinkResult.Reason.SAME_DEVICE)
	return LinkResult.success()


func _join(ia: Interface, ib: Interface) -> void:
	ia.peer_port = ib.port()
	ib.peer_port = ia.port()


## The interface followed by its subinterfaces, in insertion order.
func _with_subinterfaces(i: Interface) -> Array[Interface]:
	var out: Array[Interface] = [i]
	var device: Device = get_device(i.device_id)
	for other: Interface in device.interfaces.values():
		if other.parent == i.full_name:
			out.append(other)
	return out


func _oper_states(list: Array[Interface]) -> Array[bool]:
	var out: Array[bool] = []
	for i in list:
		out.append(is_oper_up(i.port()))
	return out


func _emit_state_changes(list: Array[Interface], before: Array[bool]) -> void:
	for n in list.size():
		var now: bool = is_oper_up(list[n].port())
		if now != before[n]:
			events.interface_state_changed.emit(list[n].port(), now)
