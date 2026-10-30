class_name ObjectiveState
extends RefCounted
## One objective's live status, as returned by NetworkSim.objective_states()
## (SPEC §3.3). Every call builds fresh instances from the current sim state, so
## changing one has no effect on the sim or on later calls. It carries no
## `equals` value or any other answer.

enum Type { PING, CONFIG }

var id: String
var type: Type = Type.PING
var description: String
## 0 when the objective has no `order`.
var order: int = 0
## An ordered objective waits for every objective with a lower `order` to pass.
## A locked objective is never passed, and shows no reason or hint.
var locked: bool = false
var passed: bool = false
## Can no longer pass. Nothing in M1 can fail for good (report attempts arrive
## in M2), so this stays false for now.
var failed: bool = false
## `ping` objectives only: why the ping failed, else NONE.
var fail_reason: PingResult.FailReason = PingResult.FailReason.NONE
## The scenario's hint for `fail_reason`, or "".
var hint: String = ""
## Short status, such as "reached, but not through R1". "" when there is none.
var detail: String = ""
