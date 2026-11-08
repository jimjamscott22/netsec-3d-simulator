extends Node

func _ready() -> void:
	var player: Player = $Player
	var cabling: Cabling = $CablingHUD
	player.interacted.connect(cabling.interact)
	player.cancel_action = cabling.cancel

	# Temporary startup mission until the mission flow owns scenario selection.
	if Sim.scenario_view() != null:
		return
	var result: LoadResult = Sim.load_scenario_id("m1_vlan_ping")
	if not result.ok:
		push_error("Could not start M1: %s" % "\n".join(result.errors))
