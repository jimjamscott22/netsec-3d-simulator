class_name ServerFormatters
extends RefCounted
## Text for the server's Linux-style shell: `help`, usage lines, and `service
## status`. Command output other than file contents comes from here, so it can be
## golden-tested.

## Each entry: summary for `help`, then usage lines.
const COMMAND_HELP: Dictionary = {
	"ls": ["List files and directories", ["ls [path]"]],
	"cat": ["Print a file", ["cat <file>"]],
	"grep": ["Print the lines of a file that match a pattern", ["grep [-i] <pattern> <file>"]],
	"tail": ["Print the last lines of a file (10 by default)", ["tail [-n N] <file>"]],
	"service": ["Show the status of a service", ["service <name> status"]],
	"help": ["List the commands, or explain one", ["help", "help <command>"]],
	"exit": ["Close the terminal", ["exit"]],
}
const HELP_NAME_COL: int = 10


## `help` with no topic: the command list.
static func help() -> String:
	var lines: PackedStringArray = ["Commands:"]
	for name: String in COMMAND_HELP:
		lines.append("  " + name.rpad(HELP_NAME_COL) + str(COMMAND_HELP[name][0]))
	return "\n".join(lines)


## `help <command>`, or bash's line for a command it doesn't know.
static func help_for(topic: String) -> String:
	if not COMMAND_HELP.has(topic):
		return "bash: help: no help topics match '%s'." % topic
	var entry: Array = COMMAND_HELP[topic]
	return "%s: %s\n%s" % [topic, entry[0], usage(topic)]


## The `Usage:` lines of a command, or "" for one that doesn't exist.
static func usage(command: String) -> String:
	var key: String = command.to_lower()
	if not COMMAND_HELP.has(key):
		return ""
	var lines: Array = COMMAND_HELP[key][1]
	return "Usage: " + "\n       ".join(PackedStringArray(lines))


## `service <name> status` for a service with `id` and `port`.
static func service_status(service: Dictionary) -> String:
	return "\n".join(PackedStringArray([
		"● %s.service" % service["id"],
		"     Loaded: loaded",
		"     Active: active (running)",
		"     Listen: %d/tcp" % ScenarioFields.to_int(service.get("port", 0)),
	]))
