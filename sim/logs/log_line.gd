class_name LogLine
extends RefCounted
## One line of a log file (SPEC §7.4). Immutable: built once by LogFile, shared
## freely, and safe to hand to the presentation layer. The sim never reads the
## clock, so `t` is display text, not a time.

var _number: int
var _t: String
var _text: String
var _src_ip: String
var _geo: String


func _init(p_number: int, p_t: String, p_text: String, p_src_ip: String, p_geo: String) -> void:
	_number = p_number
	_t = p_t
	_text = p_text
	_src_ip = p_src_ip
	_geo = p_geo


## Position in its file, counting from 1. This is what report evidence cites.
func number() -> int:
	return _number


## The timestamp as written in the file, or "".
func t() -> String:
	return _t


## The line without its timestamp.
func text() -> String:
	return _text


## The source address this line is about (feeds the threat map), or "".
func src_ip() -> String:
	return _src_ip


## ISO 3166 alpha-2 country of `src_ip`, or "".
func geo() -> String:
	return _geo


## The line as the player sees it, and what a LogFilter tests.
func full_text() -> String:
	return _text if _t.is_empty() else "%s %s" % [_t, _text]
