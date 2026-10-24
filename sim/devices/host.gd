class_name Host
extends Device

var gateway: String = ""
var locked: bool = false


func kind() -> Kind:
	return Kind.HOST


## The first interface, or null if none has been added.
func nic() -> Interface:
	if interfaces.is_empty():
		return null
	return interfaces.values()[0]
