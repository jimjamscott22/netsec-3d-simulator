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


func ping(src_id: String, dst_ip: String) -> PingResult:
	return Resolver.ping(self, src_id, dst_ip)


# --- configuration (the CLI's only way to change a device) ---------------------
# Each call validates, changes state, then emits `config_changed` once; a valid
# request that changes nothing emits nothing and returns `changed = false`.


func set_hostname(device_id: String, hostname: String) -> ConfigResult:
	var d: Device = get_device(device_id)
	if d == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_DEVICE)
	if hostname.is_empty() or hostname.contains(" "):
		return ConfigResult.failure(ConfigResult.Reason.INVALID_VALUE)
	if d is Host:
		return ConfigResult.failure(ConfigResult.Reason.WRONG_DEVICE_TYPE)
	if d.hostname == hostname:
		return ConfigResult.success(false)
	d.hostname = hostname
	events.config_changed.emit(d.id)
	return ConfigResult.success(true)


## `shutdown` / `no shutdown`. Also emits `interface_state_changed` for every
## interface (and subinterface) whose oper state flips.
func set_admin_up(port: String, up: bool) -> ConfigResult:
	var i: Interface = interface_at(port)
	if i == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_INTERFACE)
	if get_device(i.device_id) is Host:
		return ConfigResult.failure(ConfigResult.Reason.WRONG_DEVICE_TYPE)
	if i.admin_up == up:
		return ConfigResult.success(false)
	var affected: Array[Interface] = _with_subinterfaces(i)
	var peer: Interface = interface_at(i.peer_port) if i.peer_port != "" else null
	if peer != null:
		affected += _with_subinterfaces(peer)
	var before: Array[bool] = _oper_states(affected)
	i.admin_up = up
	_emit_state_changes(affected, before)
	events.config_changed.emit(i.device_id)
	return ConfigResult.success(true)


## Router `ip address`. Hosts have their own address call (the PC shell).
func set_ip_address(port: String, ip: String, mask: String) -> ConfigResult:
	var i: Interface = _router_interface(port)
	if i == null:
		return _router_interface_failure(port)
	if not IPv4.is_valid(ip) or IPv4.parse_mask(mask) == IPv4.INVALID:
		return ConfigResult.failure(ConfigResult.Reason.INVALID_VALUE)
	if i.ip == ip and i.mask == mask:
		return ConfigResult.success(false)
	i.ip = ip
	i.mask = mask
	events.config_changed.emit(i.device_id)
	return ConfigResult.success(true)


## Router `no ip address`.
func clear_ip_address(port: String) -> ConfigResult:
	var i: Interface = _router_interface(port)
	if i == null:
		return _router_interface_failure(port)
	if i.ip.is_empty() and i.mask.is_empty():
		return ConfigResult.success(false)
	i.ip = ""
	i.mask = ""
	events.config_changed.emit(i.device_id)
	return ConfigResult.success(true)


## Router `interface <name>.<sub>`: creates the subinterface (admin up, as on
## IOS) unless it exists. The parent must be an existing physical interface.
func create_subinterface(device_id: String, name: String) -> ConfigResult:
	var d: Device = get_device(device_id)
	if d == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_DEVICE)
	if not d is Router:
		return ConfigResult.failure(ConfigResult.Reason.WRONG_DEVICE_TYPE)
	var full: String = IfName.normalize(name)
	if not IfName.is_subinterface(full):
		return ConfigResult.failure(ConfigResult.Reason.NOT_SUBINTERFACE)
	if d.interfaces.has(full):
		return ConfigResult.success(false)
	if (d as Router).add_subinterface(full) == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_INTERFACE)
	events.config_changed.emit(d.id)
	return ConfigResult.success(true)


## Router `encapsulation dot1Q <id>`; subinterfaces only.
func set_dot1q_vlan(port: String, vlan_id: int) -> ConfigResult:
	var i: Interface = _router_interface(port)
	if i == null:
		return _router_interface_failure(port)
	if not i.is_sub():
		return ConfigResult.failure(ConfigResult.Reason.NOT_SUBINTERFACE)
	if not _valid_vlan(vlan_id):
		return ConfigResult.failure(ConfigResult.Reason.INVALID_VALUE)
	if i.dot1q_vlan == vlan_id:
		return ConfigResult.success(false)
	i.dot1q_vlan = vlan_id
	events.config_changed.emit(i.device_id)
	return ConfigResult.success(true)


## Switch `vlan <id>`: creates the VLAN with IOS's default name (`VLAN0010`)
## unless it exists.
func create_vlan(device_id: String, vlan_id: int) -> ConfigResult:
	var s: Switch = _switch(device_id)
	if s == null:
		return _switch_failure(device_id)
	if not _valid_vlan(vlan_id):
		return ConfigResult.failure(ConfigResult.Reason.INVALID_VALUE)
	if s.vlans.has(vlan_id):
		return ConfigResult.success(false)
	s.add_vlan(vlan_id, "VLAN%04d" % vlan_id)
	events.config_changed.emit(s.id)
	return ConfigResult.success(true)


## Switch VLAN `name <word>`. The VLAN must exist.
func set_vlan_name(device_id: String, vlan_id: int, vlan_name: String) -> ConfigResult:
	var s: Switch = _switch(device_id)
	if s == null:
		return _switch_failure(device_id)
	if not s.vlans.has(vlan_id) or vlan_name.is_empty() or vlan_name.contains(" "):
		return ConfigResult.failure(ConfigResult.Reason.INVALID_VALUE)
	if s.vlans[vlan_id] == vlan_name:
		return ConfigResult.success(false)
	s.vlans[vlan_id] = vlan_name
	events.config_changed.emit(s.id)
	return ConfigResult.success(true)


func set_switchport_mode(port: String, mode: Interface.Mode) -> ConfigResult:
	var i: Interface = _switch_interface(port)
	if i == null:
		return _switch_interface_failure(port)
	if i.mode == mode:
		return ConfigResult.success(false)
	i.mode = mode
	events.config_changed.emit(i.device_id)
	return ConfigResult.success(true)


## Switch `switchport access vlan <id>`. The VLAN need not exist yet; the port
## carries nothing until it does.
func set_access_vlan(port: String, vlan_id: int) -> ConfigResult:
	var i: Interface = _switch_interface(port)
	if i == null:
		return _switch_interface_failure(port)
	if not _valid_vlan(vlan_id):
		return ConfigResult.failure(ConfigResult.Reason.INVALID_VALUE)
	if i.access_vlan == vlan_id:
		return ConfigResult.success(false)
	i.access_vlan = vlan_id
	events.config_changed.emit(i.device_id)
	return ConfigResult.success(true)


func _valid_vlan(vlan_id: int) -> bool:
	return vlan_id >= 1 and vlan_id <= 4094


func _switch(device_id: String) -> Switch:
	return get_device(device_id) as Switch


func _switch_failure(device_id: String) -> ConfigResult:
	if get_device(device_id) == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_DEVICE)
	return ConfigResult.failure(ConfigResult.Reason.WRONG_DEVICE_TYPE)


func _switch_interface(port: String) -> Interface:
	var i: Interface = interface_at(port)
	if i != null and get_device(i.device_id) is Switch:
		return i
	return null


func _switch_interface_failure(port: String) -> ConfigResult:
	if interface_at(port) == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_INTERFACE)
	return ConfigResult.failure(ConfigResult.Reason.WRONG_DEVICE_TYPE)


func _router_interface(port: String) -> Interface:
	var i: Interface = interface_at(port)
	if i != null and get_device(i.device_id) is Router:
		return i
	return null


func _router_interface_failure(port: String) -> ConfigResult:
	if interface_at(port) == null:
		return ConfigResult.failure(ConfigResult.Reason.UNKNOWN_INTERFACE)
	return ConfigResult.failure(ConfigResult.Reason.WRONG_DEVICE_TYPE)
