class_name ReportResult
extends RefCounted
## Outcome of NetworkSim.submit_report. `ok` means the value was accepted as an
## attempt (so `correct` says whether it was right, and a wrong one cost an
## attempt). A refused submission costs nothing and says why in `reason`.

enum Reason {
	NONE,
	## No such report field (or the scenario has no report).
	UNKNOWN_FIELD,
	## Not a possible answer for the field's kind: an empty text, a malformed
	## IPv4 address, or a choice that is not one of the options.
	INVALID_VALUE,
	ALREADY_SOLVED,
	## ReportState's own refusal. Through NetworkSim a spent field has already
	## failed the mission, so callers see MISSION_OVER instead.
	OUT_OF_ATTEMPTS,
	## The mission has already been completed or failed; play has stopped.
	MISSION_OVER,
}

var ok: bool = false
var correct: bool = false
var reason: Reason = Reason.NONE
## Wrong submissions the field still allows, after this one. 0 for an unknown field.
var attempts_left: int = 0


static func accepted(p_correct: bool, p_attempts_left: int) -> ReportResult:
	var r := ReportResult.new()
	r.ok = true
	r.correct = p_correct
	r.attempts_left = p_attempts_left
	return r


static func refused(p_reason: Reason, p_attempts_left: int = 0) -> ReportResult:
	var r := ReportResult.new()
	r.reason = p_reason
	r.attempts_left = p_attempts_left
	return r
