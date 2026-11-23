class_name SocMonitor
extends Node3D
## The SOC desk's wall-of-glass monitor (task 2.6). It is the doorway to the log
## viewer (task 2.7): the player aims at the screen and interacts.
##
## It is inert until a mission has logs to read. The room builder calls
## `set_online()` on every scenario load; offline, the screen is dark and has no
## interact label, so the player's ray ignores it.

const LABEL: String = "SOC monitor"
const SCREEN_ON: Color = Color(0.12, 0.3, 0.45, 1)
const SCREEN_OFF: Color = Color(0.03, 0.035, 0.04, 1)

var _online: bool = false


func _ready() -> void:
	set_online(false)


## The collider the player aims at.
func target() -> Area3D:
	return $Screen/Target as Area3D


func is_online() -> bool:
	return _online


func set_online(online: bool) -> void:
	_online = online
	var material: StandardMaterial3D = ($Screen as MeshInstance3D).material_override as StandardMaterial3D
	material.emission_enabled = online
	material.emission = SCREEN_ON
	material.albedo_color = SCREEN_ON.darkened(0.7) if online else SCREEN_OFF
	var area: Area3D = target()
	if online:
		area.set_meta("interact_label", LABEL)
		area.set_meta("soc_monitor", true)
	else:
		area.remove_meta("interact_label")
		area.remove_meta("soc_monitor")
