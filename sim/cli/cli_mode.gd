class_name CliMode
extends RefCounted
## IOS CLI modes (see references/ios-cli.md for prompts and transitions).

enum Id { USER_EXEC, PRIV_EXEC, GLOBAL_CONFIG, INTERFACE_CONFIG, VLAN_CONFIG, LINE_CONFIG }


static func is_exec(mode: Id) -> bool:
	return mode == Id.USER_EXEC or mode == Id.PRIV_EXEC


static func is_config(mode: Id) -> bool:
	return not is_exec(mode)
