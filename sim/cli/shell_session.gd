@abstract
class_name ShellSession
extends CliSession
## Base of the PC and server terminals. They are CliSessions (so the UI binds to
## one session type and gets history, `?` help and Tab for free) with a fixed
## prompt and their own error style instead of the IOS `^` marker. Commands run
## by full name; how a bad line is reported is each shell's `_error`.


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


## The failure for a line that did not parse (`m.status` is not OK or EMPTY).
@abstract func _error(line: String, m: CliMatch) -> CliResult
