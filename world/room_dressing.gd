class_name RoomDressing
extends Node3D
## Light art pass for the room (task 1.32): Kenney desks, chairs and props plus
## Quaternius sci-fi columns, shelves and crates, all CC0 (see assets/CREDITS.md).
##
## Purely visual. The models carry no collision, and every anchor and collision
## shape stays in `room.tscn`, so nothing here can change where a device sits or
## what blocks the player.
##
## Each placement says where a model's bottom-centre stands, which makes the
## numbers independent of where a pack's artist put the model origin. Desk props
## are listed in desk-local space (+Z out of the front of the desk, as for the
## desk markers) and are parented to each desk, so moving a desk moves them.

const KENNEY: String = "res://assets/models/kenney_furniture/"
const QUATERNIUS: String = "res://assets/models/quaternius_scifi/"

## Desk nodes under the room that get `DESK_PROPS`.
const DESKS: Array[String] = ["Desks/desk_1", "Desks/desk_2"]

## Desk-local. Kenney's pieces are about half real-world size, so the scales
## bring them to the desk the greybox collision already describes (0.75 m high).
const DESK_PROPS: Array[Dictionary] = [
	{"model": KENNEY + "desk.glb", "pos": Vector3(0, 0, 0), "yaw": 0.0, "scale": 1.97},
	{"model": KENNEY + "chairDesk.glb", "pos": Vector3(0, 0, 0.7), "yaw": 180.0, "scale": 1.7},
	{"model": KENNEY + "computerKeyboard.glb", "pos": Vector3(-0.4, 0.75, 0.3), "yaw": 0.0, "scale": 1.5},
	{"model": KENNEY + "lampSquareTable.glb", "pos": Vector3(0.55, 0.75, -0.2), "yaw": 0.0, "scale": 1.6},
]

## World space, kept clear of the racks (z = -2.5) and the desks (z = 2.4).
const ROOM_PROPS: Array[Dictionary] = [
	# Corner columns, trimmed to fit under the 3 m ceiling.
	{"model": QUATERNIUS + "Column_Slim.fbx", "pos": Vector3(-3.8, 0, -2.8), "yaw": 0.0, "scale": 0.62},
	{"model": QUATERNIUS + "Column_Slim.fbx", "pos": Vector3(3.8, 0, -2.8), "yaw": 0.0, "scale": 0.62},
	{"model": QUATERNIUS + "Column_Slim.fbx", "pos": Vector3(-3.8, 0, 2.8), "yaw": 0.0, "scale": 0.62},
	{"model": QUATERNIUS + "Column_Slim.fbx", "pos": Vector3(3.8, 0, 2.8), "yaw": 0.0, "scale": 0.62},
	# Storage along the side walls, fronts facing into the room.
	{"model": QUATERNIUS + "Props_Shelf.fbx", "pos": Vector3(-3.78, 0, 0), "yaw": 90.0, "scale": 0.5},
	{"model": QUATERNIUS + "Props_Shelf.fbx", "pos": Vector3(3.78, 0, 0), "yaw": -90.0, "scale": 0.5},
	{"model": QUATERNIUS + "Props_Crate.fbx", "pos": Vector3(-3.3, 0, -2.7), "yaw": 15.0, "scale": 0.5},
	{"model": QUATERNIUS + "Props_CrateLong.fbx", "pos": Vector3(3.3, 0, -2.65), "yaw": 90.0, "scale": 0.5},
	# Office corner by the desks.
	{"model": KENNEY + "pottedPlant.glb", "pos": Vector3(-3.5, 0, 2.4), "yaw": 0.0, "scale": 2.0},
	{"model": KENNEY + "pottedPlant.glb", "pos": Vector3(3.5, 0, 2.4), "yaw": 0.0, "scale": 2.0},
	{"model": KENNEY + "trashcan.glb", "pos": Vector3(-0.2, 0, 2.7), "yaw": 0.0, "scale": 1.2},
]


func _ready() -> void:
	for placement: Dictionary in placements():
		_place(placement)


## Every placement with the node it hangs under (path from the room, or "" for
## this node). Static so tests can check the data without a scene.
static func placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for desk: String in DESKS:
		for prop: Dictionary in DESK_PROPS:
			var entry: Dictionary = prop.duplicate()
			entry["under"] = desk
			result.append(entry)
	for prop: Dictionary in ROOM_PROPS:
		var entry: Dictionary = prop.duplicate()
		entry["under"] = ""
		result.append(entry)
	return result


## Transform that stands a model with local `bounds` on `position` by its
## bottom-centre, turned by `yaw_deg` about the vertical and scaled uniformly.
static func bottom_centre_transform(
	bounds: AABB, position: Vector3, yaw_deg: float, scale: float
) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale)
	var foot := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	return Transform3D(basis, position - basis * foot)


## Bounds of every mesh under `root`, in `root`'s own space, ignoring its
## transform. An empty AABB if the model has no meshes.
static func local_bounds(root: Node3D) -> AABB:
	var found: Array[AABB] = []
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		found.append((root as MeshInstance3D).mesh.get_aabb())
	_collect_bounds(root, Transform3D.IDENTITY, found)
	if found.is_empty():
		return AABB()
	var total: AABB = found[0]
	for bounds: AABB in found:
		total = total.merge(bounds)
	return total


static func _collect_bounds(node: Node, to_root: Transform3D, out: Array[AABB]) -> void:
	for child: Node in node.get_children():
		var xf: Transform3D = to_root
		if child is Node3D:
			xf = to_root * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append(xf * (child as MeshInstance3D).mesh.get_aabb())
		_collect_bounds(child, xf, out)


func _place(placement: Dictionary) -> void:
	var path: String = placement["model"]
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("Room dressing: cannot load '%s'." % path)
		return
	var parent: Node = self
	var under: String = placement["under"]
	if not under.is_empty():
		var room: Node = get_parent()
		parent = room.get_node_or_null(under) if room != null else null
		if parent == null:
			push_error("Room dressing: no node '%s' for '%s'." % [under, path])
			return
	var model: Node3D = scene.instantiate() as Node3D
	model.transform = bottom_centre_transform(
		local_bounds(model), placement["pos"], placement["yaw"], placement["scale"]
	)
	parent.add_child(model)
