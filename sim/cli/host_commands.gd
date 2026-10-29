class_name HostCommands
extends RefCounted
## The PC's Windows-style command set (SPEC §5.1): `ipconfig`, `ipconfig /set`,
## `ping`, `help` and `exit`. Commands run by their full name only. Handlers
## change state through NetworkSim; the text comes from CliFormatters.

const USER: CliMode.Id = CliMode.Id.USER_EXEC
const MSG_LOCKED: String = "Access is denied. Network settings are managed by IT."
const MSG_OK: String = "Ok."
const MSG_NO_HOST: String = "Ping request could not find host %s. Please check the name and try again."

static var _registry: CommandRegistry = null


## The shared command table for a PC, or null for any other device. (A server
## gets its own Linux-style shell in M2.)
static func registry_for(device: Device) -> CommandRegistry:
	if device == null or device.kind() != Device.Kind.HOST:
		return null
	if _registry == null:
		_registry = build_registry()
	return _registry


static func build_registry() -> CommandRegistry:
	var reg := CommandRegistry.new()
	reg.allow_quotes = true
	reg.allow_abbreviations = false
	_add(reg, "ipconfig", _h_ipconfig, "Display the IP configuration")
	_add(reg, "ipconfig /set <ipv4> <mask> <ipv4>", _h_ipconfig_set, "Set the address, mask and gateway")
	_add(reg, "ping <word>", _h_ping, "Target IP address")
	_add(reg, "help", _h_help, "List the commands")
	_add(reg, "help <word>", _h_help_topic, "Command to explain")
	_add(reg, "exit", _h_exit, "Close the command prompt")
	reg.describe(USER, "ipconfig", "Display or set the IP configuration")
	reg.describe(USER, "ipconfig /set", "Set the address, mask and default gateway")
	reg.describe(USER, "ping", "Send echo requests")
	reg.describe(USER, "help", "Show help for commands")
	return reg


static func _add(reg: CommandRegistry, pattern: String, handler: Callable, help: String) -> void:
	var registered: bool = reg.register(USER, pattern, handler, help)
	assert(registered, "HostCommands: could not register '%s'" % pattern)


static func _host(ctx: CliSession) -> Host:
	return ctx.sim().get_device(ctx.device_id()) as Host


static func _h_ipconfig(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(CliFormatters.ipconfig(ctx.sim(), _host(ctx)))


static func _h_ipconfig_set(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var r: ConfigResult = ctx.sim().set_host_network(
		ctx.device_id(), IPv4.format(args[0]), IPv4.format(args[1]), IPv4.format(args[2])
	)
	if r.ok:
		return CliResult.ok_output(MSG_OK)
	if r.reason == ConfigResult.Reason.LOCKED:
		return CliResult.failure(MSG_LOCKED)
	return CliResult.failure(CliFormatters.host_usage("ipconfig"))


## A target that isn't a dotted quad is treated as a name, which nothing
## resolves, as on a Windows machine with no DNS.
static func _h_ping(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var target: String = args[0]
	var addr: int = IPv4.parse(target)
	if addr == IPv4.INVALID:
		return CliResult.failure(MSG_NO_HOST % target)
	var dst: String = IPv4.format(addr)
	return CliResult.ok_output(CliFormatters.windows_ping(dst, ctx.sim().ping(ctx.device_id(), dst)))


static func _h_help(_ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(CliFormatters.host_help())


static func _h_help_topic(_ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(CliFormatters.host_help_for(args[0]))


static func _h_exit(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.exit_mode()
