class_name LinkResult
extends RefCounted

enum Reason {
	NONE,
	UNKNOWN_PORT,
	NOT_PHYSICAL,
	SAME_DEVICE,
	PORT_RESERVED,
	PORT_IN_USE,
	NO_SPARE_CABLE,
	NOT_CONNECTED,
	LOCKED,
}

var ok: bool = false
var reason: Reason = Reason.NONE


static func success() -> LinkResult:
	var r := LinkResult.new()
	r.ok = true
	return r


static func failure(p_reason: Reason) -> LinkResult:
	var r := LinkResult.new()
	r.reason = p_reason
	return r
