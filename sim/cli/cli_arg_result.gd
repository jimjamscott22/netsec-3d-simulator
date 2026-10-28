class_name CliArgResult
extends RefCounted
## Outcome of parsing one typed argument. `value` is the parsed form: a
## canonical String (INTERFACE, WORD), an int (IPV4, MASK, VLAN_ID) or a
## Vector2i (LINE_RANGE).

var ok: bool = false
var value: Variant = null


static func success(p_value: Variant) -> CliArgResult:
	var r := CliArgResult.new()
	r.ok = true
	r.value = p_value
	return r


static func failure() -> CliArgResult:
	return CliArgResult.new()
