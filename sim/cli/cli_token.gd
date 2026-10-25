class_name CliToken
extends RefCounted
## One word of a command line. `start`/`end` are column offsets into the raw
## line (end exclusive); the registry uses `start` to place the `^` marker.
## For a quoted token the span includes the quote characters.

var text: String = ""
var start: int = 0
var end: int = 0
var quoted: bool = false


static func make(p_text: String, p_start: int, p_end: int, p_quoted: bool = false) -> CliToken:
	var t := CliToken.new()
	t.text = p_text
	t.start = p_start
	t.end = p_end
	t.quoted = p_quoted
	return t
