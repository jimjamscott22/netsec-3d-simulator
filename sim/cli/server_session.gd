class_name ServerSession
extends ShellSession
## A terminal on a server: a Linux-style prompt and bash-style errors. The
## prompt follows the live hostname. There is no working directory: the shell
## always stands at `/`, so relative paths mean the same as absolute ones.

const USER: String = "analyst"
const ERR_NOT_FOUND: String = "bash: %s: command not found"


## `analyst@web1:/$`
func prompt() -> String:
	var d: Device = _sim.get_device(_device_id)
	return "%s@%s:/$" % [USER, d.hostname if d != null else _device_id]


## An unknown first word is "command not found"; a known command given the wrong
## arguments gets its usage line.
func _error(line: String, m: CliMatch) -> CliResult:
	var tokens: Array[CliToken] = CliTokenizer.tokenize(line, _registry.allow_quotes)
	var first: String = tokens[0].text
	var usage: String = ServerFormatters.usage(first)
	var first_is_bad: bool = m.status == CliMatch.Status.INVALID and m.error_col == tokens[0].start
	if usage.is_empty() or first_is_bad:
		return CliResult.failure(ERR_NOT_FOUND % first)
	return CliResult.failure(usage)
