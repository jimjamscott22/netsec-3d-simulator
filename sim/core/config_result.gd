class_name ConfigResult
extends RefCounted
## Outcome of a NetworkSim configuration call. `changed` is false for a valid
## request that left the state as it was (and so emitted no signals).

enum Reason {
	NONE,
	UNKNOWN_DEVICE,
	UNKNOWN_INTERFACE,
	WRONG_DEVICE_TYPE,
	NOT_SUBINTERFACE,
	INVALID_VALUE,
	## The scenario locked this host's addressing.
	LOCKED,
}

var ok: bool = false
var changed: bool = false
var reason: Reason = Reason.NONE


static func success(p_changed: bool) -> ConfigResult:
	var r := ConfigResult.new()
	r.ok = true
	r.changed = p_changed
	return r


static func failure(p_reason: Reason) -> ConfigResult:
	var r := ConfigResult.new()
	r.reason = p_reason
	return r
