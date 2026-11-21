class_name ServerCommands
extends RefCounted
## The server's Linux-style command set (SPEC §5.1): `ls`, `cat`, `grep`, `tail`,
## `service <name> status`, `help` and `exit`. Commands run by their full name,
## as in the PC shell, and may carry a double-quoted argument
## (`grep "Failed password" /var/log/auth.log`). The shell only reads: nothing
## here changes sim state. File contents come from ServerFiles; the other text
## from ServerFormatters.

const USER: CliMode.Id = CliMode.Id.USER_EXEC
const DEFAULT_TAIL_LINES: int = 10

static var _registry: CommandRegistry = null


## The shared command table for a server, or null for any other device.
static func registry_for(device: Device) -> CommandRegistry:
	if device == null or device.kind() != Device.Kind.SERVER:
		return null
	if _registry == null:
		_registry = build_registry()
	return _registry


static func build_registry() -> CommandRegistry:
	var reg := CommandRegistry.new()
	reg.allow_quotes = true
	reg.allow_abbreviations = false
	_add(reg, "ls", _h_ls, "List the root directory")
	_add(reg, "ls <word>", _h_ls, "File or directory")
	_add(reg, "cat <word>", _h_cat, "File to print")
	_add(reg, "grep <word> <word>", _h_grep, "Pattern to look for")
	_add(reg, "grep -i <word> <word>", _h_grep_i, "Pattern to look for, ignoring case")
	_add(reg, "tail <word>", _h_tail, "File to read")
	_add(reg, "tail -n <word> <word>", _h_tail_n, "Number of lines to print")
	_add(reg, "service <word> status", _h_service_status, "Service name")
	_add(reg, "help", _h_help, "List the commands")
	_add(reg, "help <word>", _h_help_topic, "Command to explain")
	_add(reg, "exit", _h_exit, "Close the terminal")
	reg.describe(USER, "ls", "List files and directories")
	reg.describe(USER, "cat", "Print a file")
	reg.describe(USER, "grep", "Print the lines of a file that match a pattern")
	reg.describe(USER, "grep -i", "Ignore case when matching")
	reg.describe(USER, "tail", "Print the last lines of a file")
	reg.describe(USER, "tail -n", "Print this many lines instead of 10")
	reg.describe(USER, "service", "Show the status of a service")
	reg.describe(USER, "help", "Show help for commands")
	reg.describe(USER, "exit", "Close the terminal")
	return reg


static func _add(reg: CommandRegistry, pattern: String, handler: Callable, help: String) -> void:
	var registered: bool = reg.register(USER, pattern, handler, help)
	assert(registered, "ServerCommands: could not register '%s'" % pattern)


# --- files -----------------------------------------------------------------------


## `ls` and `ls <path>`. A directory lists its entries (subdirectories end in
## `/`); a file prints the path as typed.
static func _h_ls(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var typed: String = "/" if args.is_empty() else args[0]
	if _is_option(typed):
		return _usage("ls")
	var sim: NetworkSim = ctx.sim()
	if ServerFiles.is_file(sim, ctx.device_id(), typed):
		return CliResult.ok_output(typed)
	if ServerFiles.is_dir(sim, ctx.device_id(), typed):
		return CliResult.ok_output("\n".join(PackedStringArray(ServerFiles.children(sim, ctx.device_id(), typed))))
	return CliResult.failure("ls: cannot access '%s': No such file or directory" % typed)


static func _h_cat(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var lines: Variant = _read(ctx, "cat", args[0])
	if lines is CliResult:
		return lines
	return CliResult.ok_output(_join(lines))


static func _h_grep(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _grep(ctx, args[0], args[1], false)


static func _h_grep_i(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _grep(ctx, args[0], args[1], true)


## The pattern is a regular expression, as in grep. A leading `-` in the pattern
## slot is an option we don't have (`grep -v x file`), not a pattern.
static func _grep(ctx: CliSession, pattern: String, file: String, ignore_case: bool) -> CliResult:
	if _is_option(pattern):
		return _usage("grep")
	var lines: Variant = _read(ctx, "grep", file)
	if lines is CliResult:
		return lines
	var filter: LogFilter = LogFilter.regex(("(?i)" if ignore_case else "") + pattern)
	if not filter.is_valid():
		return CliResult.failure("grep: invalid regular expression '%s'" % pattern)
	var hits: Array[LogLine] = []
	for line: LogLine in lines:
		if filter.matches(line):
			hits.append(line)
	return CliResult.ok_output(_join(hits))


static func _h_tail(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return _tail(ctx, DEFAULT_TAIL_LINES, args[0])


static func _h_tail_n(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var count: String = args[0]
	if not _is_count(count):
		return CliResult.failure("tail: invalid number of lines: '%s'" % count)
	return _tail(ctx, count.to_int(), args[1])


static func _tail(ctx: CliSession, count: int, file: String) -> CliResult:
	var lines: Variant = _read(ctx, "tail", file)
	if lines is CliResult:
		return lines
	var all: Array[LogLine] = lines
	return CliResult.ok_output(_join(all.slice(maxi(0, all.size() - count))))


# --- services and the rest -------------------------------------------------------


static func _h_service_status(ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	var server: Server = ctx.sim().get_device(ctx.device_id()) as Server
	var name: String = args[0]
	for service: Variant in server.services:
		if service is Dictionary and service.get("id", "") == name:
			return CliResult.ok_output(ServerFormatters.service_status(service))
	return CliResult.failure("%s: unrecognized service" % name)


static func _h_help(_ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(ServerFormatters.help())


static func _h_help_topic(_ctx: CliSession, args: Array, _negated: bool) -> CliResult:
	return CliResult.ok_output(ServerFormatters.help_for(str(args[0]).to_lower()))


static func _h_exit(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.exit_mode()


# --- helpers ---------------------------------------------------------------------


## The file's lines as `Array[LogLine]`, or the CliResult to return instead: the
## command's usage for an option-like path, or the error for a missing file or a
## directory.
static func _read(ctx: CliSession, command: String, typed: String) -> Variant:
	if _is_option(typed):
		return _usage(command)
	if ServerFiles.is_file(ctx.sim(), ctx.device_id(), typed):
		return ServerFiles.lines(ctx.sim(), ctx.device_id(), typed)
	if ServerFiles.is_dir(ctx.sim(), ctx.device_id(), typed):
		return CliResult.failure("%s: %s: Is a directory" % [command, typed])
	return CliResult.failure("%s: %s: No such file or directory" % [command, typed])


static func _join(lines: Array) -> String:
	var out: PackedStringArray = []
	for line: LogLine in lines:
		out.append(line.full_text())
	return "\n".join(out)


static func _usage(command: String) -> CliResult:
	return CliResult.failure(ServerFormatters.usage(command))


static func _is_option(word: String) -> bool:
	return word.begins_with("-")


## Digits only (no sign), as `tail -n` takes.
static func _is_count(word: String) -> bool:
	return word.is_valid_int() and not word.begins_with("-") and not word.begins_with("+")
