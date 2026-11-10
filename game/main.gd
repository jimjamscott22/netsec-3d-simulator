extends Node

@onready var _cabling: Cabling = $CablingHUD
@onready var _terminal: Terminal = $Terminal


func _ready() -> void:
	var player: Player = $Player
	player.interacted.connect(_on_interacted)
	player.cancel_action = _cabling.cancel

	# Temporary startup mission until the mission flow owns scenario selection.
	if Sim.scenario_view() != null:
		return
	var result: LoadResult = Sim.load_scenario_id("m1_vlan_ping")
	if not result.ok:
		push_error("Could not start M1: %s" % "\n".join(result.errors))


## A console port or PC screen opens the terminal; everything else is cabling.
func _on_interacted(target: CollisionObject3D) -> void:
	if target.has_meta("console_device"):
		_terminal.open(str(target.get_meta("console_device")))
	else:
		_cabling.interact(target)
