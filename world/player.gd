class_name Player
extends CharacterBody3D

## Emitted for the labeled collider under the crosshair when interact is pressed.
signal interacted(target: CollisionObject3D)

const WALK_SPEED: float = 4.0
const CROUCH_SPEED: float = 2.0
const STANDING_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.1
const EYE_OFFSET: float = 0.15
const LOOK_SENSITIVITY: float = 0.002
const PITCH_LIMIT: float = deg_to_rad(89.0)

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _capsule: CapsuleShape3D = _collision.shape as CapsuleShape3D
@onready var _camera: Camera3D = $Camera3D
@onready var _ray: RayCast3D = $Camera3D/InteractRay
@onready var _prompt: Label = $HUD/TargetPrompt

var cancel_action: Callable

var _crouched: bool = false
var _interact_requested: bool = false


func _ready() -> void:
	_ray.add_exception(self)
	_set_height(STANDING_HEIGHT)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.screen_relative.x * LOOK_SENSITIVITY)
		_camera.rotation.x = clampf(
			_camera.rotation.x - event.screen_relative.y * LOOK_SENSITIVITY,
			-PITCH_LIMIT, PITCH_LIMIT
		)
	elif event.is_action_pressed("cancel"):
		if not cancel_action.is_valid() or not cancel_action.call():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_interact_requested = false
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_interact_requested = true
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var move_input: Vector2 = Vector2.ZERO
	if captured:
		_update_crouch(Input.is_action_pressed("crouch"))
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var speed: float = CROUCH_SPEED if _crouched else WALK_SPEED
	var direction: Vector3 = transform.basis * Vector3(move_input.x, 0.0, move_input.y)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	velocity += get_gravity() * delta
	move_and_slide()

	var target: CollisionObject3D = _refresh_target() if captured else null
	if not captured:
		_prompt.text = ""
	if _interact_requested and target != null:
		interacted.emit(target)
	_interact_requested = false


func _update_crouch(crouch_pressed: bool) -> void:
	if crouch_pressed == _crouched:
		return
	# Sweeping the crouched capsule up checks the space it would expand into.
	if not crouch_pressed and test_move(global_transform, Vector3.UP * (STANDING_HEIGHT - CROUCH_HEIGHT)):
		return
	_crouched = crouch_pressed
	_set_height(CROUCH_HEIGHT if _crouched else STANDING_HEIGHT)


func _set_height(height: float) -> void:
	_capsule.height = height
	_collision.position.y = height * 0.5
	_camera.position.y = height - EYE_OFFSET


func _refresh_target() -> CollisionObject3D:
	_ray.force_raycast_update()
	var collider: CollisionObject3D = _ray.get_collider() as CollisionObject3D
	# A collider opts in with an interact_label. Unlabeled geometry still blocks the ray.
	var label: String = ""
	if collider != null and collider.has_meta("interact_label"):
		label = str(collider.get_meta("interact_label"))
	_prompt.text = label
	return collider if not label.is_empty() else null
