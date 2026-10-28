class_name IosCommands
extends RefCounted
## The M1 IOS config commands (SPEC §5, references/ios-cli.md). Routers and
## switches get separate command tables, so a command that only exists on the
## other kind is rejected by the parser with the `^` marker, as on IOS. Context
## rules the parser can't see (a subinterface-only command on a physical port)
## are checked in the handlers. Handlers change state only through NetworkSim.

const PRIV: CliMode.Id = CliMode.Id.PRIV_EXEC
const G: CliMode.Id = CliMode.Id.GLOBAL_CONFIG
const IFACE: CliMode.Id = CliMode.Id.INTERFACE_CONFIG
const VLAN: CliMode.Id = CliMode.Id.VLAN_CONFIG

static var _router_registry: CommandRegistry = null
static var _switch_registry: CommandRegistry = null


## The shared command table for this device's CLI, or null for a device that has
## no IOS CLI (hosts and servers use their own shells).
static func registry_for(device: Device) -> CommandRegistry:
	if device is Router:
		if _router_registry == null:
			_router_registry = build_router_registry()
		return _router_registry
	if device is Switch:
		if _switch_registry == null:
			_switch_registry = build_switch_registry()
		return _switch_registry
	return null


static func build_router_registry() -> CommandRegistry:
	var reg := CommandRegistry.new()
	CliSession.register_core(reg)
	_register_common(reg)
	_add(reg, IFACE, "ip address <ipv4> <mask>", _h_ip_address, "Set the IP address of an interface", true)
	_add(reg, IFACE, "encapsulation dot1q <vlan-id>", _h_encapsulation, "IEEE 802.1Q Virtual LAN", false)
	reg.describe(IFACE, "ip", "Interface Internet Protocol config commands")
	reg.describe(IFACE, "ip address", "Set the IP address of an interface")
	reg.describe(IFACE, "encapsulation", "Set encapsulation type for an interface")
	reg.describe(IFACE, "encapsulation dot1q", "IEEE 802.1Q Virtual LAN")
	return reg


static func build_switch_registry() -> CommandRegistry:
	var reg := CommandRegistry.new()
	CliSession.register_core(reg)
	_register_common(reg)
	_add(reg, G, "vlan <vlan-id>", _h_vlan, "ISL VLAN IDs 1-4094", false)
	reg.describe(G, "vlan", "VLAN commands")
	_add(reg, VLAN, "name <word>", _h_vlan_name, "The ASCII name for the VLAN", false)
	_add(reg, IFACE, "switchport mode access", _h_mode_access, "Set trunking mode to ACCESS unconditionally", false)
	_add(reg, IFACE, "switchport mode trunk", _h_mode_trunk, "Set trunking mode to TRUNK unconditionally", false)
	_add(reg, IFACE, "switchport access vlan <vlan-id>", _h_access_vlan, "VLAN ID of the VLAN when this port is in access mode", false)
	reg.describe(IFACE, "switchport", "Set switching mode characteristics")
	reg.describe(IFACE, "switchport mode", "Set trunking mode of the interface")
	reg.describe(IFACE, "switchport access", "Set access mode characteristics of the interface")
	reg.describe(IFACE, "switchport access vlan", "Set VLAN when interface is in access mode")
	_add(reg, PRIV, "show vlan brief", _h_show_vlan_brief, "VTP all VLAN status in brief", false)
	reg.describe(PRIV, "show vlan", "VTP VLAN status")
	return reg


static func _register_common(reg: CommandRegistry) -> void:
	_add(reg, G, "hostname <word>", _h_hostname, "Set system's network name", false)
	_add(reg, G, "interface <interface>", _h_interface, "Select an interface to configure", false)
	_add(reg, IFACE, "shutdown", _h_shutdown, "Shutdown the selected interface", true)
	_add(reg, PRIV, "show running-config", _h_show_running_config, "Current operating configuration", false)
	_add(reg, PRIV, "show ip interface brief", _h_show_ip_interface_brief, "Brief summary of IP status and configuration", false)
	reg.describe(PRIV, "show", "Show running system information")
	reg.describe(PRIV, "show ip", "IP information")
	reg.describe(PRIV, "show ip interface", "IP interface status and configuration")


## Command tables are built from code, so a rejected pattern is a programming
## error. Failing loudly beats a command that silently doesn't exist.
static func _add(reg: CommandRegistry, mode: CliMode.Id, pattern: String, handler: Callable, help: String, negatable: bool) -> void:
	var registered: bool = reg.register(mode, pattern, handler, help, negatable)
	assert(registered, "IosCommands: could not register '%s'" % pattern)


# --- handlers -------------------------------------------------------------------


## Index of the first command word: after `no` on a negated command.
static func _first_word(negated: bool) -> int:
	return 1 if negated else 0


static func _port(ctx: CliSession) -> String:
	return "%s:%s" % [ctx.device_id(), ctx.context_interface()]


## A sim rejection the parser should have caught: shown as invalid input on the
## command's first word.
static func _rejected(r: ConfigResult, word: int) -> CliResult:
	if r.ok:
		return CliResult.ok_output("")
	return CliResult.invalid_input(word)


static func _h_hostname(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_hostname(ctx.device_id(), args[0]), 0)


static func _h_interface(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var name: String = args[0]
	var device: Device = ctx.sim().get_device(ctx.device_id())
	if device == null or not device.interfaces.has(name):
		# Only a router can create one, and only a subinterface of a real port.
		var created: ConfigResult = ctx.sim().create_subinterface(ctx.device_id(), name)
		if not created.ok:
			return CliResult.invalid_input(1)
	ctx.enter_interface(name)
	return CliResult.ok_output("")


static func _h_shutdown(ctx: CliSession, _args: Array, negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_admin_up(_port(ctx), negated), _first_word(negated))


static func _h_ip_address(ctx: CliSession, args: Array, negated: bool) -> CliResult:
	var word: int = _first_word(negated)
	if negated:
		return _rejected(ctx.sim().clear_ip_address(_port(ctx)), word)
	return _rejected(ctx.sim().set_ip_address(_port(ctx), IPv4.format(args[0]), IPv4.format(args[1])), word)


static func _h_encapsulation(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_dot1q_vlan(_port(ctx), args[0]), 0)


static func _h_vlan(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var vlan_id: int = args[0]
	var r: ConfigResult = ctx.sim().create_vlan(ctx.device_id(), vlan_id)
	if not r.ok:
		return CliResult.invalid_input(0)
	ctx.enter_vlan(vlan_id)
	return CliResult.ok_output("")


static func _h_vlan_name(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_vlan_name(ctx.device_id(), ctx.context_vlan(), args[0]), 0)


static func _h_mode_access(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_switchport_mode(_port(ctx), Interface.Mode.ACCESS), 0)


static func _h_mode_trunk(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_switchport_mode(_port(ctx), Interface.Mode.TRUNK), 0)


static func _h_access_vlan(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _rejected(ctx.sim().set_access_vlan(_port(ctx), args[0]), 0)


static func _h_show_running_config(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(CliFormatters.running_config(ctx.sim().get_device(ctx.device_id())))


static func _h_show_ip_interface_brief(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(CliFormatters.ip_interface_brief(ctx.sim(), ctx.device_id()))


static func _h_show_vlan_brief(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(CliFormatters.vlan_brief(ctx.sim().get_device(ctx.device_id())))
