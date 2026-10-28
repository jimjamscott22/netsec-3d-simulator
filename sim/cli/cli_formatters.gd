class_name CliFormatters
extends RefCounted
## All `show` output. Pure functions from sim state to text, golden-tested;
## command handlers never build IOS output themselves. Text has no trailing
## newline.

const IFACE_COL_MIN: int = 27
const IP_COL: int = 16
const METHOD_COL: int = 7
const STATUS_COL: int = 22

const VLAN_ID_COL: int = 5
const VLAN_NAME_COL: int = 33
const VLAN_STATUS_COL: int = 10
const VLAN_NAME_MAX: int = 32
const VLAN_PORTS_WIDTH: int = 31

## VLANs a real switch always lists; shown unless the switch defines the id.
const LEGACY_VLANS: Dictionary = {
	1002: "fddi-default",
	1003: "token-ring-default",
	1004: "fddinet-default",
	1005: "trnet-default",
}

const STATUS_ADMIN_DOWN: String = "administratively down"


## Physical interfaces in socket order, each followed by its subinterfaces
## (lowest tag first). This is the "canonical order" for show output.
static func ordered_interfaces(device: Device) -> Array[Interface]:
	var out: Array[Interface] = []
	for i: Interface in device.interfaces.values():
		if i.is_sub():
			continue
		out.append(i)
		var subs: Array[Interface] = []
		for other: Interface in device.interfaces.values():
			if other.parent == i.full_name:
				subs.append(other)
		subs.sort_custom(func(a: Interface, b: Interface) -> bool: return IfName.sub_id(a.full_name) < IfName.sub_id(b.full_name))
		out.append_array(subs)
	return out


# --- show ip interface brief ------------------------------------------------------


static func ip_interface_brief(sim: NetworkSim, device_id: String) -> String:
	var device: Device = sim.get_device(device_id)
	if device == null:
		return ""
	var list: Array[Interface] = ordered_interfaces(device)
	var name_col: int = IFACE_COL_MIN
	for i in list:
		name_col = maxi(name_col, i.full_name.length() + 1)
	var lines: PackedStringArray = [
		"Interface".rpad(name_col) + "IP-Address".rpad(IP_COL) + "OK? " + "Method".rpad(METHOD_COL) + "Status".rpad(STATUS_COL) + "Protocol"
	]
	for i in list:
		var state: Array[String] = _line_state(sim, i)
		var address: String = i.ip if i.has_address() else "unassigned"
		var method: String = "manual" if i.has_address() else "unset"
		lines.append(i.full_name.rpad(name_col) + address.rpad(IP_COL) + "YES " + method.rpad(METHOD_COL) + state[0].rpad(STATUS_COL) + state[1])
	return "\n".join(lines)


## [status, protocol]. A subinterface whose parent is shut down reads
## "administratively down" too, as on IOS.
static func _line_state(sim: NetworkSim, i: Interface) -> Array[String]:
	var admin_down: bool = not i.admin_up
	if i.is_sub():
		var parent: Interface = sim.interface_at("%s:%s" % [i.device_id, i.parent])
		admin_down = admin_down or parent == null or not parent.admin_up
	if admin_down:
		return [STATUS_ADMIN_DOWN, "down"]
	if sim.is_oper_up(i.port()):
		return ["up", "up"]
	return ["down", "down"]


# --- show vlan brief --------------------------------------------------------------


## Access ports sit under their VLAN; trunk ports and ports assigned to a VLAN
## the switch doesn't have are listed nowhere, as on IOS.
static func vlan_brief(sw: Switch) -> String:
	var rows: Dictionary = {}  # id -> {name, status, ports}
	for id: int in sw.vlans:
		rows[id] = {"name": sw.vlans[id], "status": "active", "ports": [] as Array[String]}
	for id: int in LEGACY_VLANS:
		if not rows.has(id):
			rows[id] = {"name": LEGACY_VLANS[id], "status": "act/unsup", "ports": [] as Array[String]}
	for i in ordered_interfaces(sw):
		if i.mode == Interface.Mode.ACCESS and rows.has(i.access_vlan) and sw.vlans.has(i.access_vlan):
			(rows[i.access_vlan]["ports"] as Array[String]).append(i.short_name)
	var lines: PackedStringArray = [
		"VLAN".rpad(VLAN_ID_COL) + "Name".rpad(VLAN_NAME_COL) + "Status".rpad(VLAN_STATUS_COL) + "Ports",
		"-".repeat(VLAN_ID_COL - 1) + " " + "-".repeat(VLAN_NAME_COL - 1) + " " + "-".repeat(VLAN_STATUS_COL - 1) + " " + "-".repeat(VLAN_PORTS_WIDTH),
	]
	var ids: Array = rows.keys()
	ids.sort()
	for id: int in ids:
		var row: Dictionary = rows[id]
		var port_lines: Array[String] = _wrap_ports(row["ports"])
		var head: String = str(id).rpad(VLAN_ID_COL) + str(row["name"]).substr(0, VLAN_NAME_MAX).rpad(VLAN_NAME_COL)
		if port_lines.is_empty():
			lines.append((head + str(row["status"])).strip_edges(false, true))
			continue
		lines.append(head + str(row["status"]).rpad(VLAN_STATUS_COL) + port_lines[0])
		for n in range(1, port_lines.size()):
			lines.append(" ".repeat(VLAN_ID_COL + VLAN_NAME_COL + VLAN_STATUS_COL) + port_lines[n])
	return "\n".join(lines)


## Fills each line with as many "Fa0/1, Fa0/2" entries as fit the Ports column.
static func _wrap_ports(names: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var cur: String = ""
	for n in names:
		var joined: String = n if cur.is_empty() else cur + ", " + n
		if not cur.is_empty() and joined.length() > VLAN_PORTS_WIDTH:
			out.append(cur)
			cur = n
		else:
			cur = joined
	if not cur.is_empty():
		out.append(cur)
	return out


# --- show running-config ----------------------------------------------------------


## Sections in a fixed order: hostname, enable secret (hashed), VLANs,
## interfaces, static routes. Users, domain name, vty lines, NAT and ACLs are
## added with their commands in M4/M5.
static func running_config(device: Device) -> String:
	var body: PackedStringArray = ["!", "hostname " + device.hostname, "!"]
	if not device.enable_secret.is_empty():
		body.append_array(["enable secret 5 " + secret_hash(device.enable_secret), "!"])
	if device is Switch:
		body.append_array(_vlan_section(device as Switch))
	for i in ordered_interfaces(device):
		body.append("interface " + i.full_name)
		body.append_array(_interface_lines(device, i))
		body.append("!")
	if device is Router:
		body.append_array(_route_section(device as Router))
	body.append("end")
	var text: String = "\n".join(body)
	return "Building configuration...\n\nCurrent configuration : %d bytes\n%s" % [text.to_utf8_buffer().size(), text]


## A stand-in for IOS's type 5 hash: stable for a given secret, never the
## secret itself.
static func secret_hash(secret: String) -> String:
	var digest: String = secret.md5_text()
	return "$1$%s$%s" % [digest.substr(0, 4), digest.substr(4, 22)]


static func _vlan_section(sw: Switch) -> PackedStringArray:
	var out := PackedStringArray()
	var ids: Array = sw.vlans.keys()
	ids.sort()
	for id: int in ids:
		if id == 1:
			continue
		out.append("vlan %d" % id)
		if sw.vlans[id] != "VLAN%04d" % id:
			out.append(" name " + str(sw.vlans[id]))
		out.append("!")
	return out


static func _interface_lines(device: Device, i: Interface) -> PackedStringArray:
	var out := PackedStringArray()
	if device is Router:
		if i.is_sub() and i.dot1q_vlan > 0:
			out.append(" encapsulation dot1Q %d" % i.dot1q_vlan)
		out.append(" ip address %s %s" % [i.ip, i.mask] if i.has_address() else " no ip address")
	elif i.mode == Interface.Mode.TRUNK:
		if not i.trunk_allowed_all:
			var allowed: Array[int] = i.trunk_allowed.duplicate()
			allowed.sort()
			out.append(" switchport trunk allowed vlan " + ",".join(PackedStringArray(allowed.map(func(v: int) -> String: return str(v)))))
		out.append(" switchport mode trunk")
	elif i.access_vlan != 1:
		# A default port prints nothing, as on IOS, so "mode access" is only
		# shown on a port that has been given a VLAN.
		out.append(" switchport access vlan %d" % i.access_vlan)
		out.append(" switchport mode access")
	if not i.admin_up:
		out.append(" shutdown")
	return out


static func _route_section(router: Router) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Dictionary in router.static_routes:
		out.append("ip route %s %s %s" % [entry.get("network", ""), entry.get("mask", ""), entry.get("next_hop", "")])
	if not out.is_empty():
		out.append("!")
	return out
