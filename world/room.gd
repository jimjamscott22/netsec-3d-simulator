class_name Room
extends Node3D
## The greybox server room (task 1.22): shell, racks and desks.
##
## The scene owns the geometry and the `Marker3D` anchors. The room builder
## (task 1.25) looks anchors up here by the ids a scenario uses, so no other
## code needs to know the node layout.
##
## Anchor convention: a marker's local +Z axis points out of the front of the
## rack or desk, and its origin is where a device's back-bottom-centre sits.

## Anchor for the device at `slot` (1 is the lowest) of rack `rack_id`, or null
## if the room has no such rack or slot.
func slot_marker(rack_id: String, slot: int) -> Marker3D:
	return get_node_or_null("Racks/%s/Slots/slot_%d" % [rack_id, slot]) as Marker3D


## Anchor on top of desk `desk_id`, or null if the room has no such desk.
func desk_marker(desk_id: String) -> Marker3D:
	return get_node_or_null("Desks/%s/Marker" % desk_id) as Marker3D
