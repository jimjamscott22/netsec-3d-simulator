class_name Resolver
extends RefCounted
## Stateless L3 path search over a NetworkSim (SPEC §6). `ping` walks the
## forward path hop by hop, then walks the reply path back to the source.

const MAX_HOPS: int = 32

const _NONE := PingResult.FailReason.NONE


## Outcome of one walk toward a destination address.
class Walk extends RefCounted:
	var ok: bool = false
	var reason: PingResult.FailReason = PingResult.FailReason.NONE
	var at: String = ""
	## L3 devices only: the start, each router traversed, the owner last.
	var hops: Array[String] = []
	var arrived: Device = null
	## Source address of the first hop (the egress IP for a router).
	var src_ip: int = -1

	func failed(p_reason: PingResult.FailReason, p_at: String) -> Walk:
		ok = false
		reason = p_reason
		at = p_at
		return self


static func ping(net: NetworkSim, src_id: String, dst_ip: String) -> PingResult:
	var src: Device = net.get_device(src_id)
	if src == null or src is Switch:
		return PingResult.fail(PingResult.FailReason.NO_IP, "")
	if not _has_any_address(src):
		return PingResult.fail(PingResult.FailReason.NO_IP, src_id, [src_id])
	var dst: int = IPv4.parse(dst_ip)
	if dst == IPv4.INVALID or dst == 0:
		return PingResult.fail(PingResult.FailReason.HOST_UNREACHABLE, src_id, [src_id])
	var forward: Walk = _walk(net, src, dst)
	if not forward.ok:
		return PingResult.fail(forward.reason, forward.at, forward.hops)
	var reply: Walk = _walk(net, forward.arrived, forward.src_ip)
	if not reply.ok:
		return PingResult.fail(reply.reason, reply.at, forward.hops)
	return PingResult.ok(forward.hops)


static func _walk(net: NetworkSim, start: Device, dst: int) -> Walk:
	var w := Walk.new()
	w.hops.append(start.id)
	var cur: Device = start
	var first: bool = true
	while true:
		if _owns(cur, dst):
			if first:
				w.src_ip = dst
			w.ok = true
			w.arrived = cur
			return w
		# Hosts do not forward: a packet that reaches one and is not for it dies.
		if not first and not cur is Router:
			return w.failed(PingResult.FailReason.HOST_UNREACHABLE, cur.id)
		if w.hops.size() - 1 > MAX_HOPS:
			return w.failed(PingResult.FailReason.NO_ROUTE, cur.id)
		var egress: Interface
		var next_hop: int
		if cur is Host:
			var host: Host = cur
			egress = host.nic()
			if egress == null or not egress.has_address():
				return w.failed(PingResult.FailReason.NO_IP, cur.id)
			w.src_ip = IPv4.parse(egress.ip)
			var l1: PingResult.FailReason = _egress_l1(net, egress)
			if l1 != _NONE:
				return w.failed(l1, cur.id)
			var decision: Dictionary = _host_next_hop(host, egress, dst)
			if decision["reason"] != _NONE:
				return w.failed(decision["reason"], cur.id)
			next_hop = decision["next_hop"]
		else:
			var route: Dictionary = _route(cur as Router, dst)
			if route.is_empty():
				return w.failed(PingResult.FailReason.NO_ROUTE, cur.id)
			egress = route["egress"]
			next_hop = route["next_hop"]
			if first:
				w.src_ip = IPv4.parse(egress.ip)
			var l1: PingResult.FailReason = _egress_l1(net, egress)
			if l1 != _NONE:
				return w.failed(l1, cur.id)
		var delivery: Dictionary = _deliver(net, cur, egress, next_hop)
		if delivery["reason"] != _NONE:
			return w.failed(delivery["reason"], cur.id)
		cur = net.get_device((delivery["owner"] as Interface).device_id)
		w.hops.append(cur.id)
		first = false
	return w


## The sender's own egress link: NO_LINK without a cable, ADMIN_DOWN if cabled
## but not oper-up.
static func _egress_l1(net: NetworkSim, egress: Interface) -> PingResult.FailReason:
	var attach: Interface = net.interface_at(L2.attachment_port(net, egress))
	if attach == null or attach.peer_port == "":
		return PingResult.FailReason.NO_LINK
	if not net.is_oper_up(egress.port()):
		return PingResult.FailReason.ADMIN_DOWN
	return _NONE


static func _host_next_hop(host: Host, nic: Interface, dst: int) -> Dictionary:
	var ip: int = IPv4.parse(nic.ip)
	var mask: int = IPv4.parse_mask(nic.mask)
	if IPv4.same_subnet(ip, dst, mask):
		return {"reason": _NONE, "next_hop": dst}
	var gateway: int = IPv4.parse(host.gateway)
	if gateway == IPv4.INVALID:
		return {"reason": PingResult.FailReason.NO_GATEWAY, "next_hop": -1}
	if not IPv4.same_subnet(ip, gateway, mask):
		return {"reason": PingResult.FailReason.WRONG_SUBNET, "next_hop": -1}
	return {"reason": _NONE, "next_hop": gateway}


## Longest-prefix match over connected and static routes. Connected wins ties.
## Returns {egress, next_hop} or {} when nothing matches.
static func _route(router: Router, dst: int) -> Dictionary:
	var best: Dictionary = {}
	var best_prefix: int = -1
	for iface: Interface in router.interfaces.values():
		if not iface.has_address():
			continue
		var mask: int = IPv4.parse_mask(iface.mask)
		if IPv4.same_subnet(IPv4.parse(iface.ip), dst, mask):
			var prefix: int = IPv4.mask_to_prefix(mask)
			if prefix > best_prefix:
				best_prefix = prefix
				best = {"egress": iface, "next_hop": dst}
	for entry: Dictionary in router.static_routes:
		var network: int = IPv4.parse(entry.get("network", ""))
		var mask: int = IPv4.parse_mask(entry.get("mask", ""))
		var via: int = IPv4.parse(entry.get("next_hop", ""))
		if network == IPv4.INVALID or mask == IPv4.INVALID or via == IPv4.INVALID:
			continue
		if not IPv4.same_subnet(network, dst, mask):
			continue
		var prefix: int = IPv4.mask_to_prefix(mask)
		if prefix <= best_prefix:
			continue
		var egress: Interface = _connected_interface(router, via)
		if egress == null:
			continue
		best_prefix = prefix
		best = {"egress": egress, "next_hop": via}
	return best


## The interface whose connected subnet contains `addr` (longest prefix).
static func _connected_interface(router: Router, addr: int) -> Interface:
	var found: Interface = null
	var found_prefix: int = -1
	for iface: Interface in router.interfaces.values():
		if not iface.has_address():
			continue
		var mask: int = IPv4.parse_mask(iface.mask)
		if IPv4.same_subnet(IPv4.parse(iface.ip), addr, mask) and IPv4.mask_to_prefix(mask) > found_prefix:
			found = iface
			found_prefix = IPv4.mask_to_prefix(mask)
	return found


## Owner lookup and the three L2 tiers for delivering to `next_hop` over
## `egress`. Returns {reason, owner}.
static func _deliver(net: NetworkSim, sender: Device, egress: Interface, next_hop: int) -> Dictionary:
	var owners: Array[Interface] = _owners(net, next_hop)
	for o in owners:
		if o.device_id == sender.id:
			return {"reason": PingResult.FailReason.HOST_UNREACHABLE, "owner": null}
	if owners.is_empty():
		return {"reason": PingResult.FailReason.HOST_UNREACHABLE, "owner": null}
	for o in owners:
		if _l2_reason(net, egress, o) == _NONE:
			return {"reason": _NONE, "owner": o}
	return {"reason": _l2_reason(net, egress, owners[0]), "owner": null}


## Why a frame from `egress` does not reach `target`, or NONE if it does.
static func _l2_reason(net: NetworkSim, egress: Interface, target: Interface) -> PingResult.FailReason:
	var start: String = L2.attachment_port(net, egress)
	if not L2.reaches(net, start, 0, L2.Mode.CABLES, target):
		return PingResult.FailReason.NO_LINK
	if not L2.reaches(net, start, 0, L2.Mode.OPER, target):
		return PingResult.FailReason.ADMIN_DOWN
	if target.is_sub() and not net.is_oper_up(target.port()):
		return PingResult.FailReason.ADMIN_DOWN
	var tag: int = 0
	if egress.is_sub():
		if egress.dot1q_vlan <= 0:
			return PingResult.FailReason.VLAN_MISMATCH
		tag = egress.dot1q_vlan
	if not L2.reaches(net, start, tag, L2.Mode.VLAN, target):
		return PingResult.FailReason.VLAN_MISMATCH
	return _NONE


## Interfaces owning `addr`, scanning devices in sorted id order.
static func _owners(net: NetworkSim, addr: int) -> Array[Interface]:
	var out: Array[Interface] = []
	for id in net.device_ids():
		for iface: Interface in net.get_device(id).interfaces.values():
			if iface.has_address() and IPv4.parse(iface.ip) == addr:
				out.append(iface)
	return out


static func _owns(d: Device, addr: int) -> bool:
	for iface: Interface in d.interfaces.values():
		if iface.has_address() and IPv4.parse(iface.ip) == addr:
			return true
	return false


static func _has_any_address(d: Device) -> bool:
	for iface: Interface in d.interfaces.values():
		if iface.has_address():
			return true
	return false
