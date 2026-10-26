class_name CliSession
extends RefCounted
## One open terminal on one device: the mode stack, the current
## interface/VLAN/line context, the `enable` password prompt and command
## history. The UI feeds it lines and shows `prompt()`; commands live in a
## CommandRegistry that is shared between sessions and receives this session
## as its `ctx`.

const HISTORY_MAX: int = 100
const MAX_PASSWORD_TRIES: int = 3
const CONFIG_BANNER: String = "Enter configuration commands, one per line.  End with CNTL/Z."
const PASSWORD_PROMPT: String = "Password:"
const ERR_BAD_SECRETS: String = "% Bad secrets"


## One level of the mode stack. Only the context field for its mode is set.
class _Frame:
	extends RefCounted
	var mode: CliMode.Id = CliMode.Id.USER_EXEC
	var iface: String = ""
	var vlan: int = 0
	var line: String = ""

	static func make(p_mode: CliMode.Id) -> _Frame:
		var f := _Frame.new()
		f.mode = p_mode
		return f


var _sim: NetworkSim
var _device_id: String
var _registry: CommandRegistry
## [exec mode] while at the exec level; config modes stack on top of PRIV_EXEC.
var _stack: Array[_Frame] = [_Frame.make(CliMode.Id.USER_EXEC)]
var _history: Array[String] = []
var _history_pos: int = 0
var _awaiting_password: bool = false
var _password_tries: int = 0


func _init(sim: NetworkSim, device_id: String, registry: CommandRegistry) -> void:
	_sim = sim
	_device_id = device_id
	_registry = registry


## Adds the mode-navigation commands (`enable`, `disable`, `configure
## terminal`, `exit`, `end`) and makes the config sub-modes fall back to
## GLOBAL_CONFIG commands. Commands that enter a sub-mode register themselves
## and call enter_interface / enter_vlan / enter_line.
static func register_core(reg: CommandRegistry) -> void:
	reg.register(CliMode.Id.USER_EXEC, "enable", _h_enable, "Turn on privileged commands")
	reg.register(CliMode.Id.USER_EXEC, "exit", _h_exit, "Exit from the EXEC")
	reg.register(CliMode.Id.PRIV_EXEC, "enable", _h_enable, "Turn on privileged commands")
	reg.register(CliMode.Id.PRIV_EXEC, "disable", _h_disable, "Turn off privileged commands")
	reg.register(CliMode.Id.PRIV_EXEC, "configure terminal", _h_configure_terminal, "Configure from the terminal")
	reg.describe(CliMode.Id.PRIV_EXEC, "configure", "Enter configuration mode")
	reg.register(CliMode.Id.PRIV_EXEC, "exit", _h_exit, "Exit from the EXEC")
	reg.register(CliMode.Id.GLOBAL_CONFIG, "exit", _h_exit, "Exit from configure mode")
	reg.register(CliMode.Id.GLOBAL_CONFIG, "end", _h_end, "Exit from configure mode")
	reg.set_fallback(CliMode.Id.INTERFACE_CONFIG, CliMode.Id.GLOBAL_CONFIG)
	reg.set_fallback(CliMode.Id.VLAN_CONFIG, CliMode.Id.GLOBAL_CONFIG)
	reg.set_fallback(CliMode.Id.LINE_CONFIG, CliMode.Id.GLOBAL_CONFIG)


static func _h_enable(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.enable()


static func _h_disable(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.disable()


static func _h_configure_terminal(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.configure_terminal()


static func _h_exit(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.exit_mode()


static func _h_end(ctx: CliSession, _args: Array, _negated: bool) -> CliResult:
	return ctx.end_config()


# --- state ----------------------------------------------------------------------


func mode() -> CliMode.Id:
	return _stack[_stack.size() - 1].mode


func mode_stack() -> Array[CliMode.Id]:
	var out: Array[CliMode.Id] = []
	for f in _stack:
		out.append(f.mode)
	return out


## Canonical name of the interface being configured, "" outside INTERFACE_CONFIG.
func context_interface() -> String:
	return _stack[_stack.size() - 1].iface


## VLAN being configured, 0 outside VLAN_CONFIG.
func context_vlan() -> int:
	return _stack[_stack.size() - 1].vlan


func context_line() -> String:
	return _stack[_stack.size() - 1].line


func is_password_prompt() -> bool:
	return _awaiting_password


## The text before the cursor: `R1(config-if)#`, or `Password:` while the
## enable password is being asked for. Uses the device's current hostname.
func prompt() -> String:
	if _awaiting_password:
		return PASSWORD_PROMPT
	return _hostname() + _suffix()


func _hostname() -> String:
	var d: Device = _sim.get_device(_device_id)
	return d.hostname if d != null else _device_id


func _suffix() -> String:
	match mode():
		CliMode.Id.USER_EXEC:
			return ">"
		CliMode.Id.PRIV_EXEC:
			return "#"
		CliMode.Id.GLOBAL_CONFIG:
			return "(config)#"
		CliMode.Id.INTERFACE_CONFIG:
			return "(config-subif)#" if IfName.is_subinterface(context_interface()) else "(config-if)#"
		CliMode.Id.VLAN_CONFIG:
			return "(config-vlan)#"
		_:
			return "(config-line)#"


# --- input ----------------------------------------------------------------------


## Runs one line of input. While the password prompt is up the line is the
## password, not a command, and is kept out of the history.
func submit(line: String) -> CliResult:
	if _awaiting_password:
		return _submit_password(line)
	_record(line)
	return _registry.execute(mode(), line, self, prompt().length())


func ctrl_z() -> CliResult:
	if not _awaiting_password and CliMode.is_config(mode()):
		return end_config()
	return CliResult.ok_output("")


## `?` output for the text typed so far.
func help(line: String) -> String:
	if _awaiting_password:
		return ""
	return _registry.help(mode(), line)


## Tab completion for the text typed so far.
func complete(line: String) -> String:
	if _awaiting_password:
		return line
	return _registry.complete(mode(), line)


func history() -> Array[String]:
	return _history.duplicate()


## Up arrow: the previous command, staying on the oldest one.
func history_prev() -> String:
	if _history.is_empty():
		return ""
	_history_pos = maxi(_history_pos - 1, 0)
	return _history[_history_pos]


## Down arrow: the next command, then "" past the newest.
func history_next() -> String:
	if _history_pos >= _history.size():
		return ""
	_history_pos += 1
	return _history[_history_pos] if _history_pos < _history.size() else ""


func _record(line: String) -> void:
	var text: String = line.strip_edges()
	if not text.is_empty() and (_history.is_empty() or _history[_history.size() - 1] != text):
		_history.append(text)
		if _history.size() > HISTORY_MAX:
			_history.pop_front()
	_history_pos = _history.size()


func _submit_password(line: String) -> CliResult:
	var d: Device = _sim.get_device(_device_id)
	if d != null and line == d.enable_secret:
		_awaiting_password = false
		_stack[0].mode = CliMode.Id.PRIV_EXEC
		return CliResult.ok_output("")
	_password_tries += 1
	if _password_tries >= MAX_PASSWORD_TRIES:
		_awaiting_password = false
		return CliResult.failure(ERR_BAD_SECRETS)
	return CliResult.ok_output("")


# --- mode transitions (called by command handlers) ----------------------------


## `enable`: asks for the password when the device has an enable secret.
func enable() -> CliResult:
	if _stack[0].mode == CliMode.Id.PRIV_EXEC:
		return CliResult.ok_output("")
	var d: Device = _sim.get_device(_device_id)
	if d == null or d.enable_secret.is_empty():
		_stack[0].mode = CliMode.Id.PRIV_EXEC
	else:
		_awaiting_password = true
		_password_tries = 0
	return CliResult.ok_output("")


func disable() -> CliResult:
	if _stack.size() == 1:
		_stack[0].mode = CliMode.Id.USER_EXEC
	return CliResult.ok_output("")


func configure_terminal() -> CliResult:
	if mode() == CliMode.Id.PRIV_EXEC:
		_stack.append(_Frame.make(CliMode.Id.GLOBAL_CONFIG))
	return CliResult.ok_output(CONFIG_BANNER)


## `exit`: up one level; from an exec mode it asks the UI to close the terminal.
func exit_mode() -> CliResult:
	var r := CliResult.ok_output("")
	if _stack.size() == 1:
		r.action = CliResult.ShellAction.CLOSE_SESSION
	else:
		_stack.pop_back()
	return r


## `end` / Ctrl+Z: straight back to PRIV_EXEC.
func end_config() -> CliResult:
	while _stack.size() > 1:
		_stack.pop_back()
	return CliResult.ok_output("")


## Entering a sub-mode is a global command: from another sub-mode it replaces
## that sub-mode instead of nesting inside it.
func enter_interface(full_name: String) -> void:
	var f: _Frame = _push_from_global(CliMode.Id.INTERFACE_CONFIG)
	if f != null:
		f.iface = IfName.normalize(full_name)


func enter_vlan(vlan_id: int) -> void:
	var f: _Frame = _push_from_global(CliMode.Id.VLAN_CONFIG)
	if f != null:
		f.vlan = vlan_id


## `label` is the text after `line`, for example "vty 0 4".
func enter_line(label: String) -> void:
	var f: _Frame = _push_from_global(CliMode.Id.LINE_CONFIG)
	if f != null:
		f.line = label


## Returns the new frame, or null when not in a config mode.
func _push_from_global(sub_mode: CliMode.Id) -> _Frame:
	if _stack.size() < 2:
		return null
	while _stack.size() > 2:
		_stack.pop_back()
	var f: _Frame = _Frame.make(sub_mode)
	_stack.append(f)
	return f
