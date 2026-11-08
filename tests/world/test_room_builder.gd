class_name TestRoomBuilder
extends GdUnitTestSuite

const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const MISSION: String = "m1_vlan_ping"


func before_test() -> void:
	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()


func after_test() -> void:
	Sim.load_scenario_id(MISSION)


func _build_room() -> RoomBuilder:
	var main: Node = auto_free(MAIN_SCENE.instantiate())
	add_child(main)
	return main.get_node("Room/RoomBuilder") as RoomBuilder


func _led(socket: PortSocket) -> StandardMaterial3D:
	var led: MeshInstance3D = socket.get_node("LED") as MeshInstance3D
	return led.material_override as StandardMaterial3D


func test_mounts_all_devices_and_binds_canonical_ids_in_scenario_order() -> void:
	var builder: RoomBuilder = _build_room()
	var room: Room = builder.get_parent() as Room
	var devices: Node = builder.get_node("Devices")
	assert_int(devices.get_child_count()).is_equal(4)
	for placement: Dictionary in Sim.scenario_view().devices():
		var id: String = placement["id"]
		var desk: String = placement["desk"]
		var model: DeviceModel = devices.get_node(id) as DeviceModel
		var marker: Marker3D = room.desk_marker(desk) if not desk.is_empty() else room.slot_marker(
			placement["rack"], placement["slot"]
		)
		assert_bool(model.global_transform.is_equal_approx(marker.global_transform)).is_true()
		var ordered_names: Array[String] = placement["interfaces"]
		var sockets: Array[PortSocket] = model.socket_markers()
		for index: int in ordered_names.size():
			var canonical_port: String = "%s:%s" % [id, ordered_names[index]]
			assert_str(sockets[index].port_id()).is_equal(canonical_port)
			assert_object(builder.socket_for(canonical_port)).is_same(sockets[index])


func test_start_links_and_reserved_cap_reflect_the_loaded_mission() -> void:
	var builder: RoomBuilder = _build_room()
	var cables: Node3D = builder.get_node("Cables") as Node3D
	assert_int(cables.get_child_count()).is_equal(2)
	for link: Dictionary in Sim.scenario_view().links():
		var from: PortSocket = builder.socket_for(link["a"])
		var to: PortSocket = builder.socket_for(link["b"])
		var found: bool = false
		for cable: MeshInstance3D in cables.get_children():
			var vertices: PackedVector3Array = cable.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var start: Vector3 = cable.to_global(vertices[0])
			var end: Vector3 = cable.to_global(vertices[vertices.size() - 1])
			var forward: bool = start.distance_to(from.global_position) < 0.007 				and end.distance_to(to.global_position) < 0.007
			var reverse: bool = end.distance_to(from.global_position) < 0.007 				and start.distance_to(to.global_position) < 0.007
			found = found or forward or reverse
		assert_bool(found).is_true()

	var router_port: PortSocket = builder.socket_for("R1:GigabitEthernet0/0")
	var uplink: PortSocket = builder.socket_for("S1:GigabitEthernet0/1")
	var pc_port: PortSocket = builder.socket_for("PC-A:Ethernet0")
	var access_port: PortSocket = builder.socket_for("S1:FastEthernet0/1")
	for socket: PortSocket in [router_port, uplink]:
		assert_bool(_led(socket).emission.is_equal_approx(PortSocket.LED_AMBER)).is_true()
	for socket: PortSocket in [pc_port, access_port]:
		assert_bool(_led(socket).emission.is_equal_approx(PortSocket.LED_GREEN)).is_true()

	var reserved: PortSocket = builder.socket_for("R1:GigabitEthernet0/1")
	assert_object(reserved.get_node_or_null("DustCap")).is_not_null()
	assert_bool(_led(reserved).emission_enabled).is_false()
	assert_object(router_port.get_node_or_null("DustCap")).is_null()


func test_build_reads_live_snapshots_and_replaces_visuals_on_scenario_reload() -> void:
	var session: CliSession = Sim.open_session("R1")
	for command: String in ["enable", "configure terminal", "interface gi0/0", "no shutdown"]:
		assert_bool(session.submit(command).ok).is_true()
	assert_bool(Sim.connect_link("S1:Fa0/2", "PC-B:Eth0").ok).is_true()

	var builder: RoomBuilder = _build_room()
	var cables: Node = builder.get_node("Cables")
	var devices: Node = builder.get_node("Devices")
	assert_int(cables.get_child_count()).is_equal(3)
	assert_bool(_led(builder.socket_for("R1:GigabitEthernet0/0")).emission.is_equal_approx(
		PortSocket.LED_GREEN
	)).is_true()
	assert_bool(_led(builder.socket_for("PC-B:Ethernet0")).emission.is_equal_approx(
		PortSocket.LED_GREEN
	)).is_true()

	assert_bool(Sim.load_scenario_id(MISSION).ok).is_true()
	assert_int(devices.get_child_count()).is_equal(4)
	assert_int(cables.get_child_count()).is_equal(2)
	assert_bool(_led(builder.socket_for("R1:GigabitEthernet0/0")).emission.is_equal_approx(
		PortSocket.LED_AMBER
	)).is_true()
	assert_bool(_led(builder.socket_for("PC-B:Ethernet0")).emission_enabled).is_false()
