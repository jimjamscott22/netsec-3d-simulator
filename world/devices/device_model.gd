class_name DeviceModel
extends Node3D

## The room builder pairs these with the physical interfaces in the scenario view.
func socket_markers() -> Array[PortSocket]:
	var sockets: Array[PortSocket] = []
	for child: Node in $Sockets.get_children():
		sockets.append(child as PortSocket)
	return sockets
