class_name TestRoom
extends GdUnitTestSuite
## The greybox room (task 1.22): the anchors the room builder will look up, and
## the SPEC §2 render budget.

const ROOM_SCENE: PackedScene = preload("res://world/room.tscn")
const SCENARIO: String = "res://scenarios/m1_vlan_ping.json"

## Far below the SPEC §2 limit of 300 draw calls, which also has to cover
## device models, cables and UI.
const MAX_MESHES: int = 60


## In the tree, so `global_position` reflects the rack and desk transforms.
func _room() -> Room:
	var room: Room = ROOM_SCENE.instantiate() as Room
	add_child(room)
	auto_free(room)
	return room


func _all_nodes(node: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(node)
	for child: Node in node.get_children():
		_all_nodes(child, out)
	return out


func test_has_two_racks_with_twelve_slot_markers_each() -> void:
	var room: Room = _room()
	for rack_id: String in ["rack_a", "rack_b"]:
		for slot: int in range(1, 13):
			assert_object(room.slot_marker(rack_id, slot)).is_not_null()
		assert_object(room.slot_marker(rack_id, 13)).is_null()
		assert_object(room.slot_marker(rack_id, 0)).is_null()


func test_has_two_desk_markers() -> void:
	var room: Room = _room()
	assert_object(room.desk_marker("desk_1")).is_not_null()
	assert_object(room.desk_marker("desk_2")).is_not_null()


func test_unknown_ids_give_null() -> void:
	var room: Room = _room()
	assert_object(room.slot_marker("rack_z", 1)).is_null()
	assert_object(room.desk_marker("desk_9")).is_null()


func test_slots_rise_with_the_slot_number() -> void:
	var room: Room = _room()
	var low: Vector3 = room.slot_marker("rack_a", 1).position
	var high: Vector3 = room.slot_marker("rack_a", 12).position
	assert_float(high.y).is_greater(low.y)
	assert_float(high.x).is_equal(low.x)


func test_every_scenario_placement_has_a_marker() -> void:
	var room: Room = _room()
	var text: String = FileAccess.get_file_as_string(SCENARIO)
	var data: Dictionary = JSON.parse_string(text)
	for d: Dictionary in data["devices"]:
		if d.has("rack"):
			assert_object(room.slot_marker(d["rack"], int(d["slot"]))).is_not_null()
		else:
			assert_object(room.desk_marker(d["desk"])).is_not_null()


func test_markers_are_inside_the_room_and_separate() -> void:
	var room: Room = _room()
	var seen: Dictionary = {}
	for node: Node in _all_nodes(room):
		if node is Marker3D:
			var p: Vector3 = (node as Marker3D).global_position
			assert_float(absf(p.x)).is_less(4.0)
			assert_float(absf(p.z)).is_less(3.0)
			assert_float(p.y).is_between(0.0, 3.0)
			assert_bool(seen.has(p)).is_false()
			seen[p] = true


func test_rack_front_faces_the_room() -> void:
	# +Z is out of the rack front, and the racks stand against the back wall.
	var room: Room = _room()
	var m: Marker3D = room.slot_marker("rack_a", 1)
	assert_float(m.global_transform.basis.z.z).is_greater(0.9)


func test_shell_blocks_the_player() -> void:
	var room: Room = _room()
	var shapes: int = 0
	for node: Node in _all_nodes(room):
		if node is CollisionShape3D:
			shapes += 1
	# Floor, ceiling, 4 walls, 2 racks, 2 desks of 3 pieces.
	assert_int(shapes).is_equal(6 + 2 + 6)


func test_lighting_stays_within_budget() -> void:
	var room: Room = _room()
	var directional: int = 0
	for node: Node in _all_nodes(room):
		if node is Light3D:
			assert_bool((node as Light3D).shadow_enabled).is_false()
		if node is DirectionalLight3D:
			directional += 1
	assert_int(directional).is_less_equal(1)


func test_mesh_count_is_small() -> void:
	var room: Room = _room()
	var meshes: int = 0
	for node: Node in _all_nodes(room):
		if node is MeshInstance3D:
			meshes += 1
	assert_int(meshes).is_less_equal(MAX_MESHES)
