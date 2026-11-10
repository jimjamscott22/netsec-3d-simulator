class_name Terminal
extends CanvasLayer
## The full-screen console (SPEC §8.3). It is bound to one CliSession from
## `Sim.open_session` and only forwards keys to it: history, Tab, `?` help and
## Ctrl+Z all live in the session. The terminal shows the transcript, plays the
## cosmetic ping reveal, and acts on `CliResult.action`.
##
## Keys: Enter runs the line, Up/Down walk history, Tab completes, `?` lists
## help, Ctrl+Z ends config mode, Esc closes.

signal opened(device_id: String)
signal closed

const FONT_NAMES: PackedStringArray = ["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Menlo", "monospace"]
const FONT_SIZE: int = 16
const BACKGROUND: Color = Color(0.03, 0.04, 0.05, 0.97)
const TEXT_COLOR: Color = Color(0.80, 0.92, 0.82)
const DIM_COLOR: Color = Color(0.55, 0.62, 0.58)
const FOOTER: String = "Enter run · ? help · Tab complete · ↑/↓ history · Ctrl+Z end config · Esc close"

## Tests turn this off to get the whole output at once.
var reveal_enabled: bool = true

var _session: CliSession
var _device_id: String = ""
var _transcript: String = ""
var _queue: Array[TerminalReveal.Step] = []
var _wait: float = 0.0
var _busy: bool = false
var _pending: CliResult

var _title: Label
var _output: RichTextLabel
var _input_row: HBoxContainer
var _prompt: Label
var _input: LineEdit


func _ready() -> void:
	layer = 10
	_build()
	hide()
	Sim.scenario_loaded.connect(_on_scenario_loaded)


func _process(delta: float) -> void:
	if not visible:
		return
	if _busy:
		_advance(delta)
	elif not _input.has_focus():
		_input.grab_focus()


# --- public ---------------------------------------------------------------------


## Opens a console on `device_id`. Returns false (and stays closed) when the
## device has no shell, for example a server before M2.
func open(device_id: String) -> bool:
	var session: CliSession = Sim.open_session(device_id)
	if session == null:
		return false
	_reset()
	_session = session
	_device_id = device_id
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_input.grab_focus()
	opened.emit(device_id)
	return true


func close() -> void:
	if _session == null:
		return
	_reset()
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func is_open() -> bool:
	return _session != null


func device_id() -> String:
	return _device_id


## Everything shown so far, as plain text.
func transcript() -> String:
	return _transcript


## True while a ping reveal is still playing; input waits until it ends.
func is_revealing() -> bool:
	return _busy


## Runs one line as if typed and Enter pressed.
func submit_line(line: String) -> void:
	if _session == null or _busy:
		return
	var echo: String = _session.prompt()
	if not _session.is_password_prompt():
		echo += line
	_append(echo + "\n")
	_input.clear()
	_play(_session.submit(line))


## Handles one key press. Returns true when the terminal used it.
func handle_key(key: InputEventKey) -> bool:
	if not key.pressed or _session == null:
		return false
	if key.keycode == KEY_ESCAPE:
		close()
		return true
	if _busy:
		return true
	var password: bool = _session.is_password_prompt()
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		submit_line(_input.text)
	elif key.keycode == KEY_Z and key.ctrl_pressed:
		_append(_session.prompt() + ("" if password else _input.text) + "^Z\n")
		_input.clear()
		_play(_session.ctrl_z())
	elif password:
		return false
	elif key.keycode == KEY_UP:
		_set_line(_session.history_prev())
	elif key.keycode == KEY_DOWN:
		_set_line(_session.history_next())
	elif key.keycode == KEY_TAB:
		_set_line(_session.complete(_input.text))
	elif key.unicode == "?".unicode_at(0):
		_show_help()
	else:
		return false
	return true


## The text in the input box, for tests.
func input_text() -> String:
	return _input.text


func set_input_text(text: String) -> void:
	_set_line(text)


func title_text() -> String:
	return _title.text


func prompt_text() -> String:
	return _prompt.text


# --- internals ------------------------------------------------------------------


func _show_help() -> void:
	var line: String = _input.text
	_append(_session.prompt() + line + "?\n")
	var help: String = _session.help(line)
	if not help.is_empty():
		_append(help + "\n")


## Shows a result's output (through the reveal), then acts on its action.
func _play(result: CliResult) -> void:
	_pending = result
	_queue.clear()
	if not result.output.is_empty():
		_queue = TerminalReveal.steps(result.output)
		_queue.append(TerminalReveal.Step.new(0.0, "\n"))
		_wait = _queue[0].delay
	_busy = true
	_input_row.visible = false
	_advance(0.0)


func _advance(delta: float) -> void:
	_wait -= delta
	while not _queue.is_empty():
		if reveal_enabled and _wait > 0.0:
			return
		_append(_queue.pop_front().text)
		if not _queue.is_empty():
			_wait += _queue[0].delay
	_finish()


func _finish() -> void:
	_busy = false
	var result: CliResult = _pending
	_pending = null
	if result != null:
		match result.action:
			CliResult.ShellAction.CLOSE_SESSION:
				close()
				return
			CliResult.ShellAction.OPEN_EDITOR:
				pass  # The code editor arrives in M3.
	_refresh()


func _refresh() -> void:
	if _session == null:
		return
	var view: DeviceView = Sim.device_view(_device_id)
	var hostname: String = view.hostname() if view != null else _device_id
	_title.text = "%s  ·  %s" % [hostname, _device_id] if hostname != _device_id else hostname
	_prompt.text = _session.prompt()
	_input.secret = _session.is_password_prompt()
	_input_row.visible = true


func _set_line(text: String) -> void:
	_input.text = text
	_input.caret_column = text.length()


func _append(text: String) -> void:
	_transcript += text
	_output.add_text(text)


func _reset() -> void:
	_session = null
	_device_id = ""
	_transcript = ""
	_queue.clear()
	_wait = 0.0
	_busy = false
	_pending = null
	_output.clear()
	_input.clear()
	_input.secret = false


func _on_scenario_loaded(_scenario_id: String) -> void:
	close()


func _on_input_gui_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and handle_key(key):
		_input.accept_event()


func _build() -> void:
	var font := SystemFont.new()
	font.font_names = FONT_NAMES
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = FONT_SIZE
	theme.set_color("font_color", "Label", TEXT_COLOR)
	theme.set_color("default_color", "RichTextLabel", TEXT_COLOR)
	theme.set_color("font_color", "LineEdit", TEXT_COLOR)
	theme.set_color("caret_color", "LineEdit", TEXT_COLOR)
	theme.set_stylebox("normal", "LineEdit", StyleBoxEmpty.new())
	theme.set_stylebox("focus", "LineEdit", StyleBoxEmpty.new())

	var root := Panel.new()
	root.name = "Root"
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = BACKGROUND
	root.add_theme_stylebox_override("panel", bg)
	add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	root.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	_title = Label.new()
	_title.name = "Title"
	_title.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(_title)
	column.add_child(HSeparator.new())

	_output = RichTextLabel.new()
	_output.name = "Output"
	_output.bbcode_enabled = false
	_output.scroll_following = true
	_output.focus_mode = Control.FOCUS_NONE
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_output)

	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 0)
	column.add_child(_input_row)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_input_row.add_child(_prompt)
	_input = LineEdit.new()
	_input.name = "Input"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.context_menu_enabled = false
	_input.caret_blink = true
	_input.gui_input.connect(_on_input_gui_input)
	_input_row.add_child(_input)

	column.add_child(HSeparator.new())
	var footer := Label.new()
	footer.text = FOOTER
	footer.add_theme_color_override("font_color", DIM_COLOR)
	column.add_child(footer)
