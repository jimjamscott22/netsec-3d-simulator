class_name L2
extends RefCounted
## Stateless L2 reachability over a NetworkSim. Frames flood through switches;
## a visited set per (switch, VLAN) makes rings terminate (there is no STP).

## CABLES: any cable, ignoring admin state and VLANs. OPER: only links whose
## two ends are admin up, ignoring VLANs. VLAN: OPER plus the switch VLAN rules.
enum Mode { CABLES, OPER, VLAN }


## Non-switch ports reached from `start_port`'s link (the start port itself is
## excluded), deduplicated by port+tag, in deterministic order.
static func reach(net: NetworkSim, start_port: String, start_tag: int, mode: Mode) -> Array[L2Endpoint]:
	var found: Array[L2Endpoint] = []
	var start: Interface = net.interface_at(start_port)
	if start == null:
		return found
	var start_key: String = start.port()
	var seen: Dictionary[String, bool] = {}
	var visited: Dictionary[String, bool] = {}
	var queue: Array[Array] = []
	_cross(net, start, start_tag, mode, start_key, found, seen, queue)
	var head: int = 0
	while head < queue.size():
		var ingress: Interface = queue[head][0]
		var tag: int = queue[head][1]
		head += 1
		var sw: Switch = net.get_device(ingress.device_id)
		var vlan: int = 0
		if mode == Mode.VLAN:
			vlan = _ingress_vlan(sw, ingress, tag)
			if vlan == 0:
				continue
		var key: String = "%s|%d" % [sw.id, vlan]
		if visited.has(key):
			continue
		visited[key] = true
		for egress: Interface in sw.interfaces.values():
			if egress == ingress:
				continue
			var out_tag: int = 0
			if mode == Mode.VLAN:
				out_tag = _egress_tag(egress, vlan)
				if out_tag < 0:
					continue
			_cross(net, egress, out_tag, mode, start_key, found, seen, queue)
	return found


## The interface's own port, or its parent's port for a subinterface.
static func attachment_port(_net: NetworkSim, iface: Interface) -> String:
	if iface.is_sub():
		return "%s:%s" % [iface.device_id, iface.parent]
	return iface.port()


## True if the flood from `start_port` reaches `target`. In VLAN mode the tag
## must also match: 0 for a physical target, `dot1q_vlan` for a subinterface
## (and a subinterface with `dot1q_vlan <= 0` is never reachable).
static func reaches(net: NetworkSim, start_port: String, start_tag: int, mode: Mode, target: Interface) -> bool:
	var want_tag: int = 0
	if mode == Mode.VLAN and target.is_sub():
		if target.dot1q_vlan <= 0:
			return false
		want_tag = target.dot1q_vlan
	var attach: String = attachment_port(net, target)
	for e: L2Endpoint in reach(net, start_port, start_tag, mode):
		if e.port == attach and (mode != Mode.VLAN or e.tag == want_tag):
			return true
	return false


## Sends a frame out of `from` across its cable. A switch on the far side is
## queued; any other device is recorded as an endpoint.
static func _cross(
	net: NetworkSim,
	from: Interface,
	tag: int,
	mode: Mode,
	start_key: String,
	found: Array[L2Endpoint],
	seen: Dictionary[String, bool],
	queue: Array[Array]
) -> void:
	if from.peer_port == "":
		return
	var peer: Interface = net.interface_at(from.peer_port)
	if peer == null:
		return
	if mode != Mode.CABLES and not (from.admin_up and peer.admin_up):
		return
	if net.get_device(peer.device_id) is Switch:
		queue.append([peer, tag])
		return
	var key: String = "%s|%d" % [peer.port(), tag]
	if peer.port() == start_key or seen.has(key):
		return
	seen[key] = true
	found.append(L2Endpoint.new(peer.port(), tag))


## The VLAN a frame joins on entering `port`, or 0 if the switch drops it.
static func _ingress_vlan(sw: Switch, port: Interface, tag: int) -> int:
	var vlan: int
	if port.mode == Interface.Mode.ACCESS:
		if tag != 0:
			return 0
		vlan = port.access_vlan
	else:
		vlan = 1 if tag == 0 else tag
		if not port.trunk_allows(vlan):
			return 0
	return vlan if sw.vlans.has(vlan) else 0


## The tag a frame in `vlan` leaves `port` with (0 = untagged), or -1 if the
## port does not carry that VLAN.
static func _egress_tag(port: Interface, vlan: int) -> int:
	if port.mode == Interface.Mode.ACCESS:
		return 0 if port.access_vlan == vlan else -1
	if not port.trunk_allows(vlan):
		return -1
	return 0 if vlan == 1 else vlan
