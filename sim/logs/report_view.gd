class_name ReportView
extends RefCounted
## Live, read-only report progress from NetworkSim.report_view() (SPEC §3.3):
## per field, the attempts left, the last value filed and whether it is solved.
## It never holds the expected answers; those only reach the debrief once the
## mission has ended. Static field data (label, kind, options) is in
## ScenarioView. Accessors return copies.

var _fields: Array[Dictionary] = []


## Takes `{id, attempts_left, last_value, solved}` entries in file order.
func _init(p_fields: Array[Dictionary] = []) -> void:
	for f in p_fields:
		_fields.append(f.duplicate())


## Every field in file order, each `{id: String, attempts_left: int,
## last_value: String, solved: bool}`. `last_value` is "" until one is filed.
func fields() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in _fields:
		out.append(f.duplicate())
	return out


## One field's entry, or an empty dictionary for an unknown id.
func field(id: String) -> Dictionary:
	for f in _fields:
		if f["id"] == id:
			return f.duplicate()
	return {}


func has_field(id: String) -> bool:
	return not field(id).is_empty()


## False for an unknown field.
func solved(id: String) -> bool:
	return field(id).get("solved", false)


## 0 for an unknown field.
func attempts_left(id: String) -> int:
	return field(id).get("attempts_left", 0)
