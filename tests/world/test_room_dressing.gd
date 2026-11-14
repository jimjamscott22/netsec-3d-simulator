class_name TestRoomDressing
extends GdUnitTestSuite
## The art pass (task 1.32): third-party models stand where the data says, stay
## inside the room, and never add collision.

const ROOM_SCENE: PackedScene = preload("res://world/room.tscn")

## Interior of the greybox shell (room.tscn): 8 x 6 m floor, 3 m ceiling.
const HALF_WIDTH: float = 4.0
const HALF_DEPTH: float = 3.0
const CEILING: float = 3.0

## Desk top in room.tscn: the collision box is centred at 0.725 and 0.05 thick.
const DESK_TOP: float = 0.75


func _model(placement: Dictionary) -> Node3D:
	var scene: PackedScene = load(placement["model"]) as PackedScene
	assert_object(scene).is_not_null()
	var model: Node3D = scene.instantiate() as Node3D
	auto_free(model)
	return model


func _all_nodes(node: Node, out: Array[Node] = []) -> Array[Node]:
	out.append(node)
	for child: Node in node.get_children():
		_all_nodes(child, out)
	return out


func test_bottom_centre_lands_on_the_requested_position() -> void:
	# Deliberately off-centre bounds, like a pack whose origin is on one edge.
	var bounds := AABB(Vector3(1, 0.5, 2), Vector3(2, 1, 2))
	var foot := Vector3(2, 0.5, 3)
	var position := Vector3(5, 0, -4)
	for yaw: float in [0.0, 90.0, 180.0, -90.0, 33.0]:
		var xf: Transform3D = RoomDressing.bottom_centre_transform(bounds, position, yaw, 2.0)
		assert_bool((xf * foot).is_equal_approx(position)).is_true()


func test_scale_is_uniform_and_yaw_keeps_the_model_upright() -> void:
	var xf: Transform3D = RoomDressing.bottom_centre_transform(AABB(Vector3.ZERO, Vector3.ONE), Vector3.ZERO, 90.0, 1.5)
	assert_float(xf.basis.get_scale().x).is_equal(1.5)
	assert_float(xf.basis.get_scale().y).is_equal(1.5)
	assert_float(xf.basis.get_scale().z).is_equal(1.5)
	assert_bool((xf.basis * Vector3.UP).normalized().is_equal_approx(Vector3.UP)).is_true()


func test_local_bounds_ignore_the_root_transform_and_merge_children() -> void:
	var root := Node3D.new()
	auto_free(root)
	root.position = Vector3(10, 10, 10)
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	root.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.position = Vector3(0, 2, 0)
	root.add_child(b)
	var bounds: AABB = RoomDressing.local_bounds(root)
	assert_float(bounds.position.y).is_equal(-0.5)
	assert_float(bounds.size.y).is_equal(3.0)


func test_a_model_without_meshes_has_empty_bounds() -> void:
	var root := Node3D.new()
	auto_free(root)
	assert_bool(RoomDressing.local_bounds(root).has_surface()).is_false()


func test_every_placement_loads_a_model_with_geometry() -> void:
	for placement: Dictionary in RoomDressing.placements():
		var bounds: AABB = RoomDressing.local_bounds(_model(placement))
		assert_bool(bounds.has_surface()).override_failure_message(
			"%s has no meshes" % placement["model"]
		).is_true()


func test_every_placement_has_the_fields_the_dresser_reads() -> void:
	for placement: Dictionary in RoomDressing.placements():
		for key: String in ["model", "under", "pos", "yaw", "scale"]:
			assert_bool(placement.has(key)).is_true()
		assert_float(placement["scale"]).is_greater(0.0)


func test_room_props_stay_inside_the_room_and_under_the_ceiling() -> void:
	for placement: Dictionary in RoomDressing.placements():
		if not (placement["under"] as String).is_empty():
			continue
		var pos: Vector3 = placement["pos"]
		assert_float(absf(pos.x)).is_less(HALF_WIDTH)
		assert_float(absf(pos.z)).is_less(HALF_DEPTH)
		var height: float = RoomDressing.local_bounds(_model(placement)).size.y * placement["scale"]
		assert_float(pos.y + height).override_failure_message(
			"%s is taller than the room" % placement["model"]
		).is_less_equal(CEILING)


func test_desk_art_matches_the_desk_collision_height() -> void:
	for placement: Dictionary in RoomDressing.placements():
		if not (placement["model"] as String).ends_with("/desk.glb"):
			continue
		var height: float = RoomDressing.local_bounds(_model(placement)).size.y * placement["scale"]
		assert_float(height).is_between(DESK_TOP - 0.02, DESK_TOP + 0.02)


func test_room_dresses_both_desks_and_the_room() -> void:
	var room: Room = ROOM_SCENE.instantiate() as Room
	add_child(room)
	auto_free(room)
	for desk: String in RoomDressing.DESKS:
		var meshes: int = 0
		for node: Node in _all_nodes(room.get_node(desk)):
			if node is MeshInstance3D:
				meshes += 1
		assert_int(meshes).override_failure_message("%s has no art" % desk).is_greater(0)
	var props: int = 0
	for node: Node in _all_nodes(room.get_node("Dressing")):
		if node is MeshInstance3D:
			props += 1
	assert_int(props).is_greater(0)


func test_dressing_adds_no_collision() -> void:
	var room: Room = ROOM_SCENE.instantiate() as Room
	add_child(room)
	auto_free(room)
	for node: Node in _all_nodes(room.get_node("Dressing")):
		assert_bool(node is CollisionObject3D or node is CollisionShape3D).is_false()
	for desk: String in RoomDressing.DESKS:
		var shapes: int = 0
		for node: Node in _all_nodes(room.get_node(desk)):
			if node is CollisionShape3D:
				shapes += 1
		# Still the greybox top and two side panels, nothing from the models.
		assert_int(shapes).is_equal(3)
