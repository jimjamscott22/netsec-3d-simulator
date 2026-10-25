class_name CliArg
extends RefCounted
## Typed command arguments. A type consumes `arity` words; `parse` validates
## them at parse time and returns the parsed value.

enum Type { INTERFACE, IPV4, MASK, VLAN_ID, WORD, LINE_RANGE }

const VLAN_MIN: int = 1
const VLAN_MAX: int = 4094
const LINE_MIN: int = 0
const LINE_MAX: int = 15


static func arity(type: Type) -> int:
	return 2 if type == Type.LINE_RANGE else 1


## Placeholder shown by `?` help for this argument.
static func placeholder(type: Type) -> String:
	match type:
		Type.INTERFACE:
			return "<interface>"
		Type.IPV4, Type.MASK:
			return "A.B.C.D"
		Type.VLAN_ID:
			return "<%d-%d>" % [VLAN_MIN, VLAN_MAX]
		Type.LINE_RANGE:
			return "<%d-%d> <%d-%d>" % [LINE_MIN, LINE_MAX, LINE_MIN, LINE_MAX]
		_:
			return "WORD"


static func parse(type: Type, words: PackedStringArray) -> CliArgResult:
	if words.size() != arity(type):
		return CliArgResult.failure()
	match type:
		Type.INTERFACE:
			var name: String = IfName.normalize(words[0])
			return CliArgResult.success(name) if not name.is_empty() else CliArgResult.failure()
		Type.IPV4:
			var addr: int = IPv4.parse(words[0])
			return CliArgResult.success(addr) if addr != IPv4.INVALID else CliArgResult.failure()
		Type.MASK:
			var mask: int = IPv4.parse_mask(words[0])
			return CliArgResult.success(mask) if mask != IPv4.INVALID else CliArgResult.failure()
		Type.VLAN_ID:
			var vlan: int = _parse_number(words[0], VLAN_MIN, VLAN_MAX)
			return CliArgResult.success(vlan) if vlan != -1 else CliArgResult.failure()
		Type.WORD:
			return CliArgResult.success(words[0]) if not words[0].is_empty() else CliArgResult.failure()
		Type.LINE_RANGE:
			var first: int = _parse_number(words[0], LINE_MIN, LINE_MAX)
			var last: int = _parse_number(words[1], LINE_MIN, LINE_MAX)
			if first == -1 or last == -1 or last < first:
				return CliArgResult.failure()
			return CliArgResult.success(Vector2i(first, last))
	return CliArgResult.failure()


## Digits only, no sign and no leading zero; -1 if invalid or out of range.
static func _parse_number(s: String, lo: int, hi: int) -> int:
	if s.is_empty() or (s.length() > 1 and s[0] == "0"):
		return -1
	for i in s.length():
		if s[i] < "0" or s[i] > "9":
			return -1
	var n: int = s.to_int()
	if n < lo or n > hi:
		return -1
	return n
