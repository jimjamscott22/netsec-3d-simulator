class_name DeviceModel
extends Node3D

## Shown before the device id when the player aims at the console target, for
## example "Console — R1" on a router or "Screen — PC-A" on a PC.
@export var console_label: String = "Console"


## The room builder pairs these with the physical interfaces in the scenario view.
func socket_markers() -> Array[PortSocket]:
	var sockets: Array[PortSocket] = []
	for child: Node in $Sockets.get_children():
		sockets.append(child as PortSocket)
	return sockets


## The collider that opens the terminal: a router or switch console port, or
## a PC's screen. Null on a model without one.
func console_target() -> Area3D:
	return get_node_or_null("Console") as Area3D
