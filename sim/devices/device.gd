class_name Device
extends RefCounted
## Base device. State is plain data; mutation goes through NetworkSim.

enum Kind { ROUTER, SWITCH, HOST, SERVER }

var id: String
var hostname: String
## Insertion order is socket order.
var interfaces: Dictionary[String, Interface] = {}
var enable_secret: String = ""
var users: Dictionary = {}
var vty_lines: Array = []
var domain_name: String = ""
var has_rsa_key: bool = false


func _init(p_id: String) -> void:
	id = p_id
	hostname = p_id


## Overridden by every subclass.
func kind() -> Kind:
	return Kind.HOST


func add_interface(i: Interface) -> void:
	interfaces[i.full_name] = i


func interface(name: String) -> Interface:
	return interfaces.get(IfName.normalize(name))
