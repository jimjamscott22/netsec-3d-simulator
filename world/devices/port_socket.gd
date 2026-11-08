class_name PortSocket
extends Marker3D

const LED_OFF: Color = Color(0.09, 0.10, 0.11)
const LED_AMBER: Color = Color(1.0, 0.56, 0.08)
const LED_GREEN: Color = Color(0.18, 1.0, 0.34)

## Assigned by the room builder from the scenario view's socket order.
var device_id: String
var interface_name: String
var reserved: bool = false


func port_id() -> String:
	return "%s:%s" % [device_id, interface_name]


func set_interact_label(short_name: String) -> void:
	$Target.set_meta("interact_label", "%s — %s" % [short_name, device_id])


## The caller supplies the current link state from Sim; the model only renders it.
func set_link_state(connected: bool, oper_up: bool) -> void:
	var material: StandardMaterial3D = $LED.material_override as StandardMaterial3D
	var color: Color = LED_GREEN if oper_up else LED_AMBER
	material.albedo_color = color if connected else LED_OFF
	material.emission = color if connected else Color.BLACK
	material.emission_enabled = connected
