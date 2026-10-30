class_name LoadResult
extends RefCounted
## Outcome of NetworkSim.load_scenario. `errors` are the validator's
## "<json path>: <problem>" strings; it is empty when `ok`.

var ok: bool = false
var errors: Array[String] = []


static func success() -> LoadResult:
	var r := LoadResult.new()
	r.ok = true
	return r


static func failure(p_errors: Array[String]) -> LoadResult:
	var r := LoadResult.new()
	r.errors = p_errors.duplicate()
	return r
