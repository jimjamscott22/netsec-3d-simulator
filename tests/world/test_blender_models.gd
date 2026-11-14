class_name TestBlenderModels
extends GdUnitTestSuite
## The Blender rack, switch and router (task 1.32, tools/blender/build_models.py).
## The models replace box chassis, so they must keep the envelope the collision
## shapes, slot markers and port sockets were laid out against.

const ROOM_SCENE: PackedScene = preload("res://world/room.tscn")
const RACK: PackedScene = preload("res://assets/models/blender/rack_frame.glb")
const DEVICES: Dictionary[String, PackedScene] = {
	"switch_24": preload("res://world/devices/switch_24.tscn"),
	"router_2port": preload("res://world/devices/router_2port.tscn"),
}

## Metres. Details such as LEDs and screws may stand a couple of millimetres
## proud of a face plate, and a modelled size may differ from its box by this much.
const TOLERANCE: float = 0.005


func _bounds(scene: PackedScene) -> AABB:
	var model: Node3D = auto_free(scene.instantiate()) as Node3D
	return RoomDressing.local_bounds(model)


func _device(model_id: String) -> DeviceModel:
	return auto_free(DEVICES[model_id].instantiate()) as DeviceModel


func test_rack_matches_the_collision_box_and_stands_on_the_floor() -> void:
	var bounds: AABB = _bounds(RACK)
	assert_float(bounds.position.y).is_between(-0.001, 0.001)
	assert_float(bounds.size.x).is_between(0.6 - TOLERANCE, 0.6 + TOLERANCE)
	assert_float(bounds.size.y).is_between(2.0 - TOLERANCE, 2.0 + TOLERANCE)
	assert_float(bounds.size.z).is_between(0.8 - TOLERANCE, 0.8 + TOLERANCE)
	assert_float(bounds.get_center().x).is_between(-0.001, 0.001)
	assert_float(bounds.get_center().z).is_between(-0.001, 0.001)


func test_rack_front_is_the_plane_the_slot_markers_sit_on() -> void:
	var room: Room = ROOM_SCENE.instantiate() as Room
	add_child(room)
	auto_free(room)
	var front: float = _bounds(RACK).end.z
	for rack_id: String in ["rack_a", "rack_b"]:
		assert_object(room.get_node_or_null("Racks/%s/Model" % rack_id)).is_not_null()
		for slot: int in [1, 6, 12]:
			assert_float(room.slot_marker(rack_id, slot).position.z).is_between(front - 0.001, front + 0.001)


func test_devices_fit_between_the_rack_sides() -> void:
	var rack_width: float = _bounds(RACK).size.x
	for model_id: String in DEVICES:
		assert_float(_bounds(DEVICES[model_id]).size.x).is_less(rack_width)


func test_device_models_match_their_collision_chassis() -> void:
	for model_id: String in DEVICES:
		var device: DeviceModel = _device(model_id)
		var box: BoxShape3D = (device.get_node("Chassis/Collision") as CollisionShape3D).shape as BoxShape3D
		var bounds: AABB = RoomDressing.local_bounds(device.get_node("Model") as Node3D)
		# Origin is the back-bottom-centre, like the box chassis it replaced.
		assert_float(bounds.get_center().x).is_between(-0.001, 0.001)
		assert_float(bounds.position.y).is_between(-0.001, 0.001)
		assert_float(bounds.position.z).is_between(-0.001, 0.001)
		assert_float(bounds.size.x).is_between(box.size.x - TOLERANCE, box.size.x + TOLERANCE)
		assert_float(bounds.size.y).is_between(box.size.y - TOLERANCE, box.size.y + TOLERANCE)
		assert_float(bounds.size.z).is_between(box.size.z - TOLERANCE, box.size.z + TOLERANCE)


func test_sockets_and_console_stand_in_front_of_the_face_plate() -> void:
	for model_id: String in DEVICES:
		var device: DeviceModel = _device(model_id)
		var bounds: AABB = RoomDressing.local_bounds(device.get_node("Model") as Node3D)
		var targets: Array[Node3D] = [device.console_target()]
		for socket: PortSocket in device.socket_markers():
			targets.append(socket)
		for target: Node3D in targets:
			assert_float(target.position.z).override_failure_message(
				"%s: %s is buried in the face plate" % [model_id, target.name]
			).is_greater_equal(bounds.end.z)
			assert_float(absf(target.position.x)).is_less(bounds.size.x / 2.0)
			assert_float(target.position.y).is_between(bounds.position.y, bounds.end.y)


func test_device_models_use_few_surfaces() -> void:
	# One mesh each, a handful of materials: cheap enough for a full rack.
	for model_id: String in DEVICES:
		var device: DeviceModel = _device(model_id)
		var meshes: int = 0
		var surfaces: int = 0
		for node: Node in device.get_node("Model").find_children("*", "MeshInstance3D", true, false):
			meshes += 1
			surfaces += (node as MeshInstance3D).mesh.get_surface_count()
		assert_int(meshes).is_equal(1)
		assert_int(surfaces).is_less_equal(8)
