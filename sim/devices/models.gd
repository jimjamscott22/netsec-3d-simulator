class_name DeviceModels
extends RefCounted
## Catalog of buildable device models and their ordered interface lists.

const _MODELS: Dictionary = {
	"router_2port": {
		"kind": Device.Kind.ROUTER,
		"names": ["GigabitEthernet0/0", "GigabitEthernet0/1"],
		"admin_up": false,
	},
	"switch_24": {
		"kind": Device.Kind.SWITCH,
		"names": [],  # generated in interface_names()
		"admin_up": true,
	},
	"pc": {
		"kind": Device.Kind.HOST,
		"names": ["Ethernet0"],
		"admin_up": true,
	},
	"server": {
		"kind": Device.Kind.SERVER,
		"names": ["Ethernet0"],
		"admin_up": true,
	},
}


static func has_model(model: String) -> bool:
	return _MODELS.has(model)


## The Device.Kind a model builds, or -1 for an unknown model.
static func kind_of(model: String) -> int:
	if not _MODELS.has(model):
		return -1
	return _MODELS[model]["kind"]


static func interface_names(model: String) -> Array[String]:
	var names: Array[String] = []
	if not _MODELS.has(model):
		return names
	if model == "switch_24":
		for n in range(1, 25):
			names.append("FastEthernet0/%d" % n)
		names.append("GigabitEthernet0/1")
		names.append("GigabitEthernet0/2")
		return names
	for n: String in _MODELS[model]["names"]:
		names.append(n)
	return names


static func build(model: String, id: String) -> Device:
	if not _MODELS.has(model):
		return null
	var spec: Dictionary = _MODELS[model]
	var device: Device
	match spec["kind"]:
		Device.Kind.ROUTER:
			device = Router.new(id)
		Device.Kind.SWITCH:
			device = Switch.new(id)
		Device.Kind.SERVER:
			device = Server.new(id)
		_:
			device = Host.new(id)
	var admin_up: bool = spec["admin_up"]
	for n in interface_names(model):
		device.add_interface(Interface.new(id, n, admin_up))
	return device
