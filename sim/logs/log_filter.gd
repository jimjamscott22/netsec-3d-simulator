class_name LogFilter
extends RefCounted
## Picks lines out of a log. One criterion per filter, built with a factory:
## everything, a substring (exact or ignoring case), a regular expression, or a
## `src_ip`. Substring and regex filters test `LogLine.full_text()`, what the
## player sees. A filter that cannot be satisfied (a regex that does not
## compile, an empty `src_ip`) reports `is_valid() == false` and matches
## nothing, so a typo in the filter box shows no lines rather than all of them.

enum Kind { ALL, SUBSTRING, SUBSTRING_IGNORE_CASE, REGEX, SRC_IP }

var _kind: Kind = Kind.ALL
var _needle: String = ""
var _regex: RegEx = null
var _valid: bool = true


static func all() -> LogFilter:
	return LogFilter.new()


## Lines containing `text` as written. An empty `text` matches every line.
static func contains(text: String) -> LogFilter:
	var f := LogFilter.new()
	f._kind = Kind.SUBSTRING
	f._needle = text
	return f


## Like `contains`, ignoring letter case.
static func contains_ignore_case(text: String) -> LogFilter:
	var f := LogFilter.new()
	f._kind = Kind.SUBSTRING_IGNORE_CASE
	f._needle = text
	return f


## Lines where `pattern` matches anywhere. Case-sensitive; start the pattern
## with `(?i)` to ignore case.
static func regex(pattern: String) -> LogFilter:
	var f := LogFilter.new()
	f._kind = Kind.REGEX
	f._needle = pattern
	f._regex = RegEx.new()
	f._valid = f._regex.compile(pattern, false) == OK
	return f


## Lines whose `src_ip` field is exactly `ip`. An address that merely appears in
## the text does not count.
static func src_ip(ip: String) -> LogFilter:
	var f := LogFilter.new()
	f._kind = Kind.SRC_IP
	f._needle = ip
	f._valid = not ip.is_empty()
	return f


func is_valid() -> bool:
	return _valid


func matches(line: LogLine) -> bool:
	if not _valid:
		return false
	match _kind:
		# Godot's String.contains("") is false; a grep for nothing matches every line.
		Kind.SUBSTRING:
			return _needle.is_empty() or line.full_text().contains(_needle)
		Kind.SUBSTRING_IGNORE_CASE:
			return _needle.is_empty() or line.full_text().containsn(_needle)
		Kind.REGEX:
			return _regex.search(line.full_text()) != null
		Kind.SRC_IP:
			return line.src_ip() == _needle
	return true
