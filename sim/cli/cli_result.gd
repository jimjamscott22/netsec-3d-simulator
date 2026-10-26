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


static func ok_output(text: String) -> CliResult:
	var r := CliResult.new()
	r.output = text
	return r


static func failure(text: String) -> CliResult:
	var r := CliResult.new()
	r.output = text
	r.ok = false
	return r
