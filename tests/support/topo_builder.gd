class_name TopoBuilder
extends RefCounted
## Test support: builds topologies by poking Device fields directly, because
## the mutating NetworkSim API (config commands) arrives in M1b.

var sim: NetworkSim


func _init(spare_cables: int = 0) -> void:
	sim = NetworkSim.new(spare_cables)


func add(model: String, id: String) -> Device:
	var d: Device = DeviceModels.build(model, id)
	GdUnitTestSuite.assert_bool(d != null).override_failure_message("unknown model '%s'" % model).is_true()
	GdUnitTestSuite.assert_bool(sim.add_device(d)).override_failure_message("duplicate device '%s'" % id).is_true()
	return d


func cable(a_port: String, b_port: String) -> void:
	var r: LinkResult = sim.add_fixed_link(a_port, b_port, false)
	GdUnitTestSuite.assert_bool(r.ok).override_failure_message(
		"cable %s <-> %s rejected: %s" % [a_port, b_port, LinkResult.Reason.keys()[r.reason]]
	).is_true()


func set_host(id: String, ip: String, mask: String, gateway: String = "") -> void:
	var h: Host = sim.get_device(id)
	h.nic().ip = ip
	h.nic().mask = mask
	h.gateway = gateway


func up(port: String) -> void:
	sim.interface_at(port).admin_up = true


func access(port: String, vlan: int) -> void:
	var i: Interface = sim.interface_at(port)
	i.mode = Interface.Mode.ACCESS
	i.access_vlan = vlan


## An empty `allowed` list means all VLANs.
func trunk(port: String, allowed: Array[int] = []) -> void:
	var i: Interface = sim.interface_at(port)
	i.mode = Interface.Mode.TRUNK
	i.trunk_allowed_all = allowed.is_empty()
	i.trunk_allowed = allowed.duplicate()


func set_ip(port: String, ip: String, mask: String) -> void:
	var i: Interface = sim.interface_at(port)
	i.ip = ip
	i.mask = mask


func subif(router_id: String, name: String, vlan: int, ip: String, mask: String) -> void:
	var r: Router = sim.get_device(router_id)
	var sub: Interface = r.add_subinterface(name)
	GdUnitTestSuite.assert_bool(sub != null).override_failure_message("subif %s:%s rejected" % [router_id, name]).is_true()
	sub.dot1q_vlan = vlan
	sub.ip = ip
	sub.mask = mask


## PC-A and PC-B in 192.168.10.0/24 on one switch, everything default (VLAN 1).
static func flat() -> TopoBuilder:
	var t := TopoBuilder.new()
	t.add("switch_24", "S1")
	t.add("pc", "PC-A")
	t.add("pc", "PC-B")
	t.cable("PC-A:Ethernet0", "S1:FastEthernet0/1")
	t.cable("PC-B:Ethernet0", "S1:FastEthernet0/2")
	t.set_host("PC-A", "192.168.10.10", "255.255.255.0")
	t.set_host("PC-B", "192.168.10.20", "255.255.255.0")
	return t


## Router-on-a-stick: VLAN 10 and 20 hosts, one trunk to R1's subinterfaces.
static func stick() -> TopoBuilder:
	var t := TopoBuilder.new()
	t.add("switch_24", "S1")
	t.add("router_2port", "R1")
	t.add("pc", "PC-A")
	t.add("pc", "PC-B")
	(t.sim.get_device("S1") as Switch).add_vlan(10, "V10")
	(t.sim.get_device("S1") as Switch).add_vlan(20, "V20")
	t.cable("PC-A:Ethernet0", "S1:FastEthernet0/1")
	t.cable("PC-B:Ethernet0", "S1:FastEthernet0/2")
	t.cable("S1:GigabitEthernet0/1", "R1:GigabitEthernet0/0")
	t.access("S1:FastEthernet0/1", 10)
	t.access("S1:FastEthernet0/2", 20)
	t.trunk("S1:GigabitEthernet0/1")
	t.up("R1:GigabitEthernet0/0")
	t.subif("R1", "GigabitEthernet0/0.10", 10, "192.168.10.1", "255.255.255.0")
	t.subif("R1", "GigabitEthernet0/0.20", 20, "192.168.20.1", "255.255.255.0")
	t.set_host("PC-A", "192.168.10.10", "255.255.255.0", "192.168.10.1")
	t.set_host("PC-B", "192.168.20.10", "255.255.255.0", "192.168.20.1")
	return t
