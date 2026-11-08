class_name Cabling
extends CanvasLayer

const REJECTIONS: Dictionary[LinkResult.Reason, String] = {
	LinkResult.Reason.SAME_DEVICE: "Choose a port on another device.",
	LinkResult.Reason.PORT_RESERVED: "That port is reserved.",
	LinkResult.Reason.PORT_IN_USE: "That port is already in use.",
	LinkResult.Reason.NO_SPARE_CABLE: "No spare cables left.",
	LinkResult.Reason.LOCKED: "That cable is locked.",
}

@onready var _status: Label = $Status
@onready var _toast: Label = $Toast
@onready var _toast_timer: Timer = $ToastTimer

var _held_port: String = ""
var _held_label: String = ""


func _ready() -> void:
	_toast_timer.timeout.connect(_toast.hide)
	Sim.link_changed.connect(_on_link_changed)
	Sim.scenario_loaded.connect(_on_scenario_loaded)
	_refresh_status()


func interact(target: CollisionObject3D) -> void:
	if target.has_meta("cable_port"):
		if _held_port.is_empty():
			_show_result(Sim.disconnect_link(str(target.get_meta("cable_port"))))
		else:
			_clear_held()
			_show_toast(REJECTIONS[LinkResult.Reason.PORT_IN_USE])
		return

	var socket: PortSocket = target.get_parent() as PortSocket
	if socket == null:
		return
	var port_id: String = socket.port_id()
	if not _held_port.is_empty():
		var from: String = _held_port
		_clear_held()
		_show_result(Sim.connect_link(from, port_id))
		return

	var view: DeviceView = Sim.device_view(socket.device_id)
	if view.interface(socket.interface_name)["peer"] != null:
		_show_result(Sim.disconnect_link(port_id))
	elif socket.reserved:
		_show_toast(REJECTIONS[LinkResult.Reason.PORT_RESERVED])
	elif Sim.spare_cables() == 0:
		_show_toast(REJECTIONS[LinkResult.Reason.NO_SPARE_CABLE])
	else:
		_held_port = port_id
		_held_label = str(target.get_meta("interact_label"))
		_toast.hide()
		_refresh_status()


## True if Escape dropped a cable end and gameplay should keep mouse capture.
func cancel() -> bool:
	if _held_port.is_empty():
		return false
	_clear_held()
	return true


func _clear_held() -> void:
	_held_port = ""
	_held_label = ""
	_refresh_status()


func _refresh_status() -> void:
	_status.text = "Spare cables: %d" % Sim.spare_cables()
	if not _held_port.is_empty():
		_status.text += "\nCable from %s · aim at another port and interact · Esc to drop" % _held_label


func _show_result(result: LinkResult) -> void:
	if result.ok:
		_toast.hide()
	else:
		_show_toast(REJECTIONS.get(result.reason, "Cable action failed."))


func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.show()
	_toast_timer.start()


func _on_link_changed(a: String, b: String, connected: bool) -> void:
	if connected and (_held_port == a or _held_port == b):
		_clear_held()
	else:
		_refresh_status()


func _on_scenario_loaded(_scenario_id: String) -> void:
	_clear_held()
	_toast.hide()
