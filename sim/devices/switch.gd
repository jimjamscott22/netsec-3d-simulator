class_name Switch
extends Device

## VLAN 1 always exists.
var vlans: Dictionary[int, String] = {1: "default"}


func kind() -> Kind:
	return Kind.SWITCH


func add_vlan(vlan_id: int, vlan_name: String) -> bool:
	if vlan_id < 1 or vlan_id > 4094:
		return false
	vlans[vlan_id] = vlan_name
	return true


func remove_vlan(vlan_id: int) -> bool:
	if vlan_id == 1 or not vlans.has(vlan_id):
		return false
	vlans.erase(vlan_id)
	return true
