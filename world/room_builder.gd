class_name RoomBuilder
extends Node3D

const MODELS: Dictionary[String, PackedScene] = {
	"router_2port": preload("res://world/devices/router_2port.tscn"),
	"switch_24": preload("res://world/devices/switch_24.tscn"),
	"pc": preload("res://world/devices/pc.tscn"),
}
const DUST_CAP: PackedScene = preload("res://world/devices/dust_cap.tscn")

@onready var _room: Room = get_parent() as Room
@onready var _devices: Node3D = $Devices
@onready var _cables: Node3D = $Cables

var _links: Dictionary[String, MeshInstance3D] = {}
var _jacket := StandardMaterial3D.new()
var _sockets: Dictionary[String, PortSocket] = {}


func _ready() -> void:
	_jacket.albedo_color = Color(0.16, 0.55, 0.92)
	Sim.scenario_loaded.connect(_on_scenario_loaded)
	Sim.link_changed.connect(_on_link_changed)
	Sim.interface_state_changed.connect(_on_interface_state_changed)
	var scenario: ScenarioView = Sim.scenario_view()
	if scenario != null:
		_build(scenario)


func socket_for(port_id: String) -> PortSocket:
	return _sockets.get(port_id)


func _on_scenario_loaded(_scenario_id: String) -> void:
	_build(Sim.scenario_view())


func _build(scenario: ScenarioView) -> void:
	_sockets.clear()
	_links.clear()
	for child: Node in _cables.get_children() + _devices.get_children():
		child.free()

	var peers: Dictionary[String, String] = {}
	for placement: Dictionary in scenario.devices():
		_place_device(placement, peers)

	for port_id: String in scenario.reserved_ports():
		var socket: PortSocket = socket_for(port_id)
		if socket != null:
			socket.reserved = true
			socket.add_child(DUST_CAP.instantiate())

	for port_id: String in peers:
		var peer_id: String = peers[port_id]
		# The same link appears in the snapshots for both endpoints.
		if port_id < peer_id:
			_draw_link(port_id, peer_id)


func _draw_link(a: String, b: String) -> void:
	var key: String = a if a < b else b
	if _links.has(key) or not _sockets.has(a) or not _sockets.has(b):
		return
	var cable := MeshInstance3D.new()
	var inverse: Transform3D = _cables.global_transform.affine_inverse()
	cable.mesh = CableMesh.between(
		inverse * _sockets[a].global_transform, inverse * _sockets[b].global_transform
	)
	cable.material_override = _jacket
	var target := StaticBody3D.new()
	# The interaction ray can hit the jacket without blocking player movement.
	target.collision_layer = 2
	target.collision_mask = 0
	target.set_meta("interact_label", "Unplug cable")
	target.set_meta("cable_port", key)
	var hit_shape := CollisionShape3D.new()
	hit_shape.shape = cable.mesh.create_trimesh_shape()
	target.add_child(hit_shape)
	cable.add_child(target)
	_cables.add_child(cable)
	_links[key] = cable


func _on_link_changed(a: String, b: String, connected: bool) -> void:
	if connected:
		_draw_link(a, b)
	else:
		var key: String = a if a < b else b
		var cable: MeshInstance3D = _links.get(key)
		if cable != null:
			_links.erase(key)
			cable.free()
	_refresh_led(a)
	_refresh_led(b)


func _on_interface_state_changed(port_id: String, _oper_up: bool) -> void:
	_refresh_led(port_id)


func _refresh_led(port_id: String) -> void:
	var socket: PortSocket = socket_for(port_id)
	if socket == null:
		return
	var device: DeviceView = Sim.device_view(socket.device_id)
	var state: Dictionary = device.interface(socket.interface_name)
	socket.set_link_state(state["peer"] != null, state["oper_up"])


func _place_device(placement: Dictionary, peers: Dictionary[String, String]) -> void:
	var device_id: String = placement["id"]
	var model_id: String = placement["model"]
	var scene: PackedScene = MODELS.get(model_id)
	var desk: String = placement["desk"]
	var anchor: Marker3D = _room.desk_marker(desk) if not desk.is_empty() else _room.slot_marker(
		placement["rack"], placement["slot"]
	)
	if scene == null or anchor == null:
		push_error("Cannot place device '%s': missing model '%s' or room marker." % [device_id, model_id])
		return

	var device: DeviceView = Sim.device_view(device_id)
	if device == null:
		push_error("Cannot place device '%s': no device snapshot." % device_id)
		return

	var model: DeviceModel = scene.instantiate() as DeviceModel
	var sockets: Array[PortSocket] = model.socket_markers()
	var interfaces: Array[String] = placement["interfaces"]
	if sockets.size() != interfaces.size():
		push_error("Cannot place device '%s': %d sockets for %d physical interfaces." % [
			device_id, sockets.size(), interfaces.size()
		])
		model.free()
		return

	model.name = device_id
	_devices.add_child(model)
	model.global_transform = anchor.global_transform
	for index: int in interfaces.size():
		var interface_name: String = interfaces[index]
		var socket: PortSocket = sockets[index]
		socket.device_id = device_id
		socket.interface_name = interface_name
		var state: Dictionary = device.interface(interface_name)
		socket.set_interact_label(state["short_name"])
		var port_id: String = socket.port_id()
		_sockets[port_id] = socket

		var connected: bool = state["peer"] != null
		socket.set_link_state(connected, state["oper_up"])
		if connected:
			peers[port_id] = state["peer"]
