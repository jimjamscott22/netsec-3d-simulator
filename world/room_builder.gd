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

var _sockets: Dictionary[String, PortSocket] = {}


func _ready() -> void:
	Sim.scenario_loaded.connect(_on_scenario_loaded)
	var scenario: ScenarioView = Sim.scenario_view()
	if scenario != null:
		_build(scenario)


func socket_for(port_id: String) -> PortSocket:
	return _sockets.get(port_id)


func _on_scenario_loaded(_scenario_id: String) -> void:
	_build(Sim.scenario_view())


func _build(scenario: ScenarioView) -> void:
	_sockets.clear()
	for child: Node in _cables.get_children() + _devices.get_children():
		child.free()

	var peers: Dictionary[String, String] = {}
	for placement: Dictionary in scenario.devices():
		_place_device(placement, peers)

	for port_id: String in scenario.reserved_ports():
		var socket: PortSocket = socket_for(port_id)
		if socket != null:
			socket.add_child(DUST_CAP.instantiate())

	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Color(0.16, 0.55, 0.92)
	for port_id: String in peers:
		var peer_id: String = peers[port_id]
		# The same link appears in the snapshots for both endpoints.
		if port_id < peer_id and _sockets.has(peer_id):
			var cable := MeshInstance3D.new()
			var from: Transform3D = _cables.global_transform.affine_inverse() * _sockets[port_id].global_transform
			var to: Transform3D = _cables.global_transform.affine_inverse() * _sockets[peer_id].global_transform
			cable.mesh = CableMesh.between(from, to)
			cable.material_override = jacket
			_cables.add_child(cable)


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
		var port_id: String = socket.port_id()
		_sockets[port_id] = socket

		var state: Dictionary = device.interface(interface_name)
		var connected: bool = state["peer"] != null
		socket.set_link_state(connected, state["oper_up"])
		if connected:
			peers[port_id] = state["peer"]
