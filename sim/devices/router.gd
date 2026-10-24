class_name Router
extends Device

## Each entry is {network: String, mask: String, next_hop: String}.
var static_routes: Array[Dictionary] = []
var nat_rules: Array = []
var acls: Dictionary = {}
var ip_routing: bool = true


func kind() -> Kind:
	return Kind.ROUTER


## Returns null if the name is not a subinterface, the parent is missing, or
## the subinterface already exists.
func add_subinterface(name: String) -> Interface:
	var full: String = IfName.normalize(name)
	if not IfName.is_subinterface(full) or interfaces.has(full):
		return null
	var parent_name: String = IfName.parent_of(full)
	if not interfaces.has(parent_name):
		return null
	var sub := Interface.new(id, full, true)
	sub.parent = parent_name
	add_interface(sub)
	return sub
