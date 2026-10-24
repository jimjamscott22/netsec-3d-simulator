class_name TestTopoBuilder
extends GdUnitTestSuite


func test_topo_builder_flat() -> void:
	var t := TopoBuilder.flat()
	var sim: NetworkSim = t.sim
	assert_str(sim.interface_at("PC-A:Ethernet0").peer_port).is_equal("S1:FastEthernet0/1")
	assert_str(sim.interface_at("PC-B:Ethernet0").peer_port).is_equal("S1:FastEthernet0/2")
	assert_str(sim.interface_at("S1:Fa0/2").peer_port).is_equal("PC-B:Ethernet0")
	var a: Interface = sim.interface_at("PC-A:Ethernet0")
	assert_str(a.ip).is_equal("192.168.10.10")
	assert_str(a.mask).is_equal("255.255.255.0")
	assert_str((sim.get_device("PC-A") as Host).gateway).is_equal("")
	assert_str(sim.interface_at("PC-B:Ethernet0").ip).is_equal("192.168.10.20")
	assert_int(sim.interface_at("S1:Fa0/1").access_vlan).is_equal(1)
	assert_int(sim.interface_at("S1:Fa0/1").mode).is_equal(Interface.Mode.ACCESS)
	assert_bool(sim.is_oper_up("PC-A:Ethernet0")).is_true()


func test_topo_builder_stick() -> void:
	var t := TopoBuilder.stick()
	var sim: NetworkSim = t.sim
	assert_str(sim.interface_at("PC-A:Ethernet0").peer_port).is_equal("S1:FastEthernet0/1")
	assert_str(sim.interface_at("PC-B:Ethernet0").peer_port).is_equal("S1:FastEthernet0/2")
	assert_str((sim.get_device("PC-A") as Host).gateway).is_equal("192.168.10.1")
	assert_str((sim.get_device("PC-B") as Host).gateway).is_equal("192.168.20.1")
	assert_str(sim.interface_at("PC-B:Ethernet0").ip).is_equal("192.168.20.10")
	assert_int(sim.interface_at("S1:Fa0/1").access_vlan).is_equal(10)
	assert_int(sim.interface_at("S1:Fa0/2").access_vlan).is_equal(20)
	var s1: Switch = sim.get_device("S1")
	assert_bool(s1.vlans.has(10)).is_true()
	assert_bool(s1.vlans.has(20)).is_true()
	var trunk: Interface = sim.interface_at("S1:Gi0/1")
	assert_int(trunk.mode).is_equal(Interface.Mode.TRUNK)
	assert_bool(trunk.trunk_allowed_all).is_true()
	assert_str(trunk.peer_port).is_equal("R1:GigabitEthernet0/0")
	var s10: Interface = sim.interface_at("R1:Gi0/0.10")
	assert_int(s10.dot1q_vlan).is_equal(10)
	assert_str(s10.ip).is_equal("192.168.10.1")
	assert_str(s10.mask).is_equal("255.255.255.0")
	var s20: Interface = sim.interface_at("R1:Gi0/0.20")
	assert_int(s20.dot1q_vlan).is_equal(20)
	assert_str(s20.ip).is_equal("192.168.20.1")
	assert_bool(sim.is_oper_up("PC-A:Ethernet0")).is_true()
	assert_bool(sim.is_oper_up("R1:Gi0/0.10")).is_true()
	assert_bool(sim.is_oper_up("R1:Gi0/0.20")).is_true()
	assert_bool(sim.interface_at("R1:Gi0/1").admin_up).is_false()
	assert_str(sim.interface_at("R1:Gi0/1").peer_port).is_equal("")
