class_name CliTokenizer
extends RefCounted
## Splits a command line into words. The IOS CLI uses plain whitespace
## splitting; the host/server shells pass `allow_quotes` so a double-quoted
## argument can hold spaces and single quotes. A quote only opens a quoted
## token at the start of a word, and an unterminated one runs to end of line.


static func _is_space(c: String) -> bool:
	return c == " " or c == "\t"


static func tokenize(line: String, allow_quotes: bool = false) -> Array[CliToken]:
	var tokens: Array[CliToken] = []
	var n: int = line.length()
	var i: int = 0
	while i < n:
		if _is_space(line[i]):
			i += 1
			continue
		var start: int = i
		if allow_quotes and line[i] == '"':
			var close: int = line.find('"', i + 1)
			if close == -1:
				tokens.append(CliToken.make(line.substr(i + 1), start, n, true))
				break
			tokens.append(CliToken.make(line.substr(i + 1, close - i - 1), start, close + 1, true))
			i = close + 1
			continue
		while i < n and not _is_space(line[i]):
			i += 1
		tokens.append(CliToken.make(line.substr(start, i - start), start, i))
	return tokens


## True when the line ends in a separator, so `sh` (still typing a word) and
## `sh ` (next word starts) can be told apart for `?` help and Tab.
static func ends_with_whitespace(line: String) -> bool:
	return not line.is_empty() and _is_space(line[line.length() - 1])
