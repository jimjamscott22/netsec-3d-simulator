class_name HostSession
extends CliSession
## A terminal on a PC. It is a CliSession (so the UI binds to one session type
## and gets history, `?` help and Tab for free) with a fixed Windows-style
## prompt and Windows-style errors instead of the IOS `^` marker.

const PROMPT: String = "C:\\>"
const ERR_NOT_RECOGNIZED: String = "'%s' is not recognized as an internal or external command,\noperable program or batch file."


func prompt() -> String:
	return PROMPT


func submit(line: String) -> CliResult:
	_record(line)
	var m: CliMatch = _registry.lookup(mode(), line)
	if m.status == CliMatch.Status.EMPTY:
		return CliResult.ok_output("")
	if m.status != CliMatch.Status.OK:
		return _error(line, m)
	var res: Variant = m.handler.call(self, m.args, m.negated)
	if res is CliResult:
		return res
	return CliResult.ok_output("")


## An unknown first word is "not recognized"; a known command given the wrong
## arguments gets its usage line.
func _error(line: String, m: CliMatch) -> CliResult:
	var tokens: Array[CliToken] = CliTokenizer.tokenize(line, _registry.allow_quotes)
	var first: String = tokens[0].text
	var usage: String = CliFormatters.host_usage(first)
	var first_is_bad: bool = m.status == CliMatch.Status.INVALID and m.error_col == tokens[0].start
	if usage.is_empty() or first_is_bad:
		return CliResult.failure(ERR_NOT_RECOGNIZED % first)
	return CliResult.failure(usage)
