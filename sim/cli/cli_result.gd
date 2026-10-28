class_name CliResult
extends RefCounted
## What a command handler returns. `action` asks the UI to do something (the
## core never references UI classes); `action_arg` carries its payload, for
## example the device id and file path for OPEN_EDITOR.

enum ShellAction { NONE, CLOSE_SESSION, OPEN_EDITOR }

var output: String = ""
var ok: bool = true
var action: ShellAction = ShellAction.NONE
var action_arg: String = ""
## Set by `invalid_input`: index of the typed word to put the `^` marker under.
## CommandRegistry.execute turns it into the "% Invalid input" text.
var error_word: int = -1


static func ok_output(text: String) -> CliResult:
	var r := CliResult.new()
	r.output = text
	return r


static func failure(text: String) -> CliResult:
	var r := CliResult.new()
	r.output = text
	r.ok = false
	return r


## For input that parsed but makes no sense in this context (for example
## `encapsulation` on a physical port). `word` indexes the typed words, `no`
## included.
static func invalid_input(word: int) -> CliResult:
	var r := CliResult.new()
	r.ok = false
	r.error_word = word
	return r
