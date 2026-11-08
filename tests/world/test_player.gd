class_name TestPlayer
extends GdUnitTestSuite

const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")


func _spawn_player() -> Player:
	var main: Node = MAIN_SCENE.instantiate()
	add_child(main)
	auto_free(main)
	return main.get_node("Player") as Player


func _settle_physics() -> void:
	# Let Godot register moved or newly added colliders before querying them.
	await get_tree().physics_frame
	await get_tree().physics_frame


func _add_obstacle(at: Vector3, size: Vector3) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	obstacle.add_child(collision)
	obstacle.position = at
	add_child(obstacle)
	auto_free(obstacle)
	return obstacle


func test_aim_shows_the_rack_and_clears_when_blocked() -> void:
	var player: Player = _spawn_player()
	var prompt: Label = player.get_node("HUD/TargetPrompt") as Label
	await _settle_physics()

	assert_object(player._refresh_target()).is_same(player.get_node("../Room/Racks/rack_a"))
	assert_str(prompt.text).is_equal("Rack A")

	_add_obstacle(Vector3(-1.5, 1.65, -1.0), Vector3(0.5, 0.5, 0.2))
	await _settle_physics()

	assert_object(player._refresh_target()).is_null()
	assert_str(prompt.text).is_empty()


func test_crouch_lowers_camera_and_requires_clearance_to_stand() -> void:
	var player: Player = _spawn_player()
	var camera: Camera3D = player.get_node("Camera3D") as Camera3D
	var collision: CollisionShape3D = player.get_node("CollisionShape3D") as CollisionShape3D
	# Keep this test independent of the headless driver's mouse mode.
	player.set_physics_process(false)
	await _settle_physics()

	player._update_crouch(true)
	assert_float(camera.position.y).is_equal_approx(0.95, 0.001)
	assert_float(collision.position.y).is_equal_approx(0.55, 0.001)

	var overhead: StaticBody3D = _add_obstacle(
		Vector3(-1.5, 1.5, 0.0), Vector3(1.0, 0.2, 1.0)
	)
	await _settle_physics()
	player._update_crouch(false)
	assert_float(camera.position.y).is_equal_approx(0.95, 0.001)

	overhead.position.x += 2.0
	await _settle_physics()
	player._update_crouch(false)
	assert_float(camera.position.y).is_equal_approx(1.65, 0.001)
