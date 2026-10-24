class_name PingResult
extends RefCounted
## Outcome of NetworkSim.ping. Mission hints are keyed on `fail_reason`, so it
## must be precise (SPEC §6.1).

enum FailReason {
	NONE,
	NO_IP,
	NO_LINK,
	ADMIN_DOWN,
	VLAN_MISMATCH,
	WRONG_SUBNET,
	NO_GATEWAY,
	NO_ROUTE,
	HOST_UNREACHABLE,
	ACL_DENIED,
}

var success: bool = false
## L3 devices only: source, routers traversed, destination last.
var hops: Array[String] = []
var fail_reason: FailReason = FailReason.NONE
## Id of the device holding the packet when it failed, "" if none.
var fail_at: String = ""


static func ok(p_hops: Array[String]) -> PingResult:
	var r := PingResult.new()
	r.success = true
	r.hops = p_hops.duplicate()
	return r


static func fail(reason: FailReason, at: String, p_hops: Array[String] = []) -> PingResult:
	var r := PingResult.new()
	r.fail_reason = reason
	r.fail_at = at
	r.hops = p_hops.duplicate()
	return r


static func reason_name(r: FailReason) -> String:
	return FailReason.keys()[r]
