class_name ScenarioLoader
extends RefCounted
## Turns a scenario that ScenarioValidator has already passed into devices, links
## and a ScenarioView. It does no checking of its own: NetworkSim.load_scenario
## validates first and calls this only for a valid file, so a half-built network
## never exists. Pure data in, objects out; NetworkSim installs the result.


## Devices in file order, with their starting config applied. No cables yet.
static func build_devices(data: Dictionary) -> Array[Device]:
	var out: Array[Device] = []
	for entry: Dictionary in data["devices"]:
		var d: Device = DeviceModels.build(entry["model"], entry["id"])
		if entry.has("hostname"):
			d.hostname = entry["hostname"]
		_apply_config(d, entry.get("config", {}))
		out.append(d)
	return out


## Start cables as `{a, b, locked}` with canonical ports; `locked` defaults to false.
static func start_links(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link: Dictionary in data["links"]:
		out.append({
			"a": _canonical_port(link["a"]),
			"b": _canonical_port(link["b"]),
			"locked": link.get("locked", false),
		})
	return out


static func reserved_ports(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for port: String in data.get("reserved_ports", []):
		out.append(_canonical_port(port))
	return out


static func spare_cables(data: Dictionary) -> int:
	return ScenarioFields.to_int(data.get("spare_cables", 0))


static func build_view(data: Dictionary) -> ScenarioView:
	var devices: Array = []
	for entry: Dictionary in data["devices"]:
		var model: String = entry["model"]
		devices.append({
			"id": entry["id"],
			"kind": DeviceModels.kind_of(model),
			"model": model,
			"hostname": entry.get("hostname", entry["id"]),
			"rack": entry.get("rack", ""),
			"slot": ScenarioFields.to_int(entry.get("slot", 0)),
			"desk": entry.get("desk", ""),
			"interfaces": DeviceModels.interface_names(model),
		})
	var hints: Array = []
	for hint: Dictionary in data.get("hints", []):
		hints.append({"reason": PingResult.FailReason[hint["reason"]], "text": hint["text"]})
	return ScenarioView.new(
		data["id"],
		data["title"],
		data["briefing"],
		spare_cables(data),
		hints,
		devices,
		start_links(data),
		reserved_ports(data),
	)


static func _canonical_port(port: String) -> String:
	return "%s:%s" % [IfName.port_device(port), IfName.normalize(IfName.port_iface(port))]


static func _apply_config(d: Device, cfg: Dictionary) -> void:
	if cfg.has("enable_secret"):
		d.enable_secret = cfg["enable_secret"]
	if d is Host:  # includes Server
		_apply_host(d as Host, cfg)
	elif d is Switch:
		_apply_switch(d as Switch, cfg)
	elif d is Router:
		_apply_router(d as Router, cfg)


static func _apply_host(host: Host, cfg: Dictionary) -> void:
	var nic: Interface = host.nic()
	if cfg.has("ip"):
		nic.ip = cfg["ip"]
		nic.mask = cfg["mask"]
	host.gateway = cfg.get("gateway", "")
	host.locked = cfg.get("locked", false)


static func _apply_switch(s: Switch, cfg: Dictionary) -> void:
	var vlans: Dictionary = cfg.get("vlans", {})
	for key: String in vlans:
		s.add_vlan(ScenarioFields.parse_vlan_key(key), vlans[key])
	var interfaces: Dictionary = cfg.get("interfaces", {})
	for written: String in interfaces:
		_apply_interface(s.interface(written), interfaces[written])


## Physical interfaces first, then subinterfaces, which need their parent to exist.
static func _apply_router(r: Router, cfg: Dictionary) -> void:
	var routes: Array = cfg.get("routes", [])
	for route: Dictionary in routes:
		r.static_routes.append({
			"network": route["network"],
			"mask": route["mask"],
			"next_hop": route["next_hop"],
		})
	var interfaces: Dictionary = cfg.get("interfaces", {})
	for written: String in interfaces:
		if not IfName.is_subinterface(IfName.normalize(written)):
			_apply_interface(r.interface(written), interfaces[written])
	for written: String in interfaces:
		if IfName.is_subinterface(IfName.normalize(written)):
			_apply_interface(r.add_subinterface(written), interfaces[written])


## `fields` holds only keys the validator allows for this device type.
static func _apply_interface(i: Interface, fields: Dictionary) -> void:
	if fields.has("admin_up"):
		i.admin_up = fields["admin_up"]
	if fields.has("ip"):
		i.ip = fields["ip"]
		i.mask = fields["mask"]
	if fields.has("dot1q_vlan"):
		i.dot1q_vlan = ScenarioFields.to_int(fields["dot1q_vlan"])
	if fields.has("mode"):
		i.mode = Interface.Mode.TRUNK if fields["mode"] == "trunk" else Interface.Mode.ACCESS
	if fields.has("access_vlan"):
		i.access_vlan = ScenarioFields.to_int(fields["access_vlan"])
	if fields.has("trunk_allowed"):
		i.trunk_allowed_all = false
		i.trunk_allowed.clear()
		for vlan: Variant in fields["trunk_allowed"]:
			i.trunk_allowed.append(ScenarioFields.to_int(vlan))
