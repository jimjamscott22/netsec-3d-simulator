class_name SimEvents
extends RefCounted
## Past-tense signals. Only NetworkSim emits them.

@warning_ignore("unused_signal")
signal link_changed(a_port: String, b_port: String, connected: bool)
@warning_ignore("unused_signal")
signal interface_state_changed(port: String, oper_up: bool)
@warning_ignore("unused_signal")
signal config_changed(device_id: String)
@warning_ignore("unused_signal")
signal objective_updated(objective_id: String, passed: bool)
@warning_ignore("unused_signal")
signal mission_completed(scenario_id: String)
