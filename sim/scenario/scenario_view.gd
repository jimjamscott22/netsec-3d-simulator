class_name ScenarioView
extends RefCounted
## Read-only, static scenario data for the world and UI (SPEC §3.3): the header,
## every device's placement and ordered interface list, the start links and the
## reserved ports. It never holds objectives, `solution`, `debrief` or any
## device config. Accessors return fresh copies, so a caller can't reach the
## view's data (or sim state) through them.

var _id: String
var _title: String
var _briefing: String
var _spare_cables: int
var _hints: Array
var _devices: Array
var _links: Array
var _reserved_ports: Array[String]


## Takes normalized data from ScenarioLoader (canonical ports and names).
func _init(
	p_id: String,
	p_title: String,
	p_briefing: String,
	p_spare_cables: int,
	p_hints: Array,
	p_devices: Array,
	p_links: Array,
	p_reserved_ports: Array[String],
) -> void:
	_id = p_id
	_title = p_title
	_briefing = p_briefing
	_spare_cables = p_spare_cables
	_hints = p_hints.duplicate(true)
	_devices = p_devices.duplicate(true)
	_links = p_links.duplicate(true)
	_reserved_ports = p_reserved_ports.duplicate()


func scenario_id() -> String:
	return _id


func title() -> String:
	return _title


func briefing() -> String:
	return _briefing


## Spare cables the player starts with.
func spare_cables() -> int:
	return _spare_cables


## Each `{reason: PingResult.FailReason, text: String}`, in file order.
func hints() -> Array:
	return _hints.duplicate(true)


## In file order. Each `{id, kind: Device.Kind, model, hostname, rack, slot,
## desk, interfaces: Array[String]}`. Racked devices have `rack` + `slot`
## (`desk` is ""), hosts have `desk` (`rack` is "" and `slot` is 0).
## `interfaces` is the canonical socket order, physical interfaces only.
func devices() -> Array:
	return _devices.duplicate(true)


## Each `{a, b, locked}` with canonical ports.
func links() -> Array:
	return _links.duplicate(true)


func reserved_ports() -> Array[String]:
	return _reserved_ports.duplicate()
