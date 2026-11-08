extends Node

## Temporary startup mission until the mission flow owns scenario selection.
func _ready() -> void:
	if Sim.scenario_view() != null:
		return
	var result: LoadResult = Sim.load_scenario_id("m1_vlan_ping")
	if not result.ok:
		push_error("Could not start M1: %s" % "\n".join(result.errors))
