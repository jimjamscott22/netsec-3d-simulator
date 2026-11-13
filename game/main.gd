extends Node

## The player closed the debrief and wants the main menu. When this is the
## running scene it then switches to the menu itself.
signal menu_requested

const MENU_SCENE: String = "res://ui/main_menu.tscn"

@onready var _cabling: Cabling = $CablingHUD
@onready var _terminal: Terminal = $Terminal
@onready var _hud: MissionHud = $MissionHUD
@onready var _card: MissionCard = $MissionCard
@onready var _player: Player = $Player

## The mission ended while the terminal was open; the debrief waits for it to close.
var _debrief_pending: bool = false


func _ready() -> void:
	_player.interacted.connect(_on_interacted)
	_player.cancel_action = _cabling.cancel
	_apply_settings()
	Progress.settings_changed.connect(_apply_settings)
	_card.closed.connect(_on_card_closed)
	# The terminal covers the screen and owns Tab, so the HUD steps aside.
	_terminal.opened.connect(_hud.hide.unbind(1))
	_terminal.closed.connect(_on_terminal_closed)
	Sim.scenario_loaded.connect(_on_scenario_loaded)
	Sim.mission_completed.connect(_on_mission_completed)

	# The main menu loads the mission before switching here. Running this scene
	# on its own (from the editor, or in tests) falls back to M1.
	if Sim.scenario_view() != null:
		_card.show_briefing()
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


func _on_scenario_loaded(_scenario_id: String) -> void:
	_debrief_pending = false
	_card.show_briefing()


## The last fix is usually typed in the terminal, so the debrief lets the player
## see that command's output first and appears once the terminal closes.
func _on_mission_completed(_scenario_id: String) -> void:
	if _terminal.is_open():
		_debrief_pending = true
	else:
		_card.show_debrief()


func _on_terminal_closed() -> void:
	_hud.show()
	if _debrief_pending:
		_debrief_pending = false
		_card.show_debrief()


func _on_card_closed(kind: MissionCard.Kind) -> void:
	if kind != MissionCard.Kind.DEBRIEF:
		return
	menu_requested.emit()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(MENU_SCENE)


func _apply_settings() -> void:
	_player.look_sensitivity = Player.BASE_LOOK_SENSITIVITY * Progress.look_sensitivity()
