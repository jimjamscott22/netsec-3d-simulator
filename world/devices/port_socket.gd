class_name PortSocket
extends Marker3D

const LED_OFF: Color = Color(0.09, 0.10, 0.11)
const LED_AMBER: Color = Color(1.0, 0.56, 0.08)
const LED_GREEN: Color = Color(0.18, 1.0, 0.34)

## The caller supplies the current link state from Sim; the model only renders it.
func set_link_state(connected: bool, oper_up: bool) -> void:
	var material: StandardMaterial3D = $LED.material_override as StandardMaterial3D
	var color: Color = LED_GREEN if oper_up else LED_AMBER
	material.albedo_color = color if connected else LED_OFF
	material.emission = color if connected else Color.BLACK
	material.emission_enabled = connected
