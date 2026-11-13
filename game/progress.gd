extends Node
## The `Progress` autoload (SPEC §8.5): completed mission ids and player
## settings, saved to `user://progress.json`. It does file IO, so it lives in
## `game/`, never in `sim/`.
##
## It starts in memory only and touches no file until `open()` is called. The
## main menu opens the real save on startup, so a test or a scene run on its own
## never overwrites the player's save. Tests open a temp path instead and
## `close()` it afterwards.
##
## No `class_name`: the global name `Progress` comes from the autoload entry, as
## with `Sim`. Tests instantiate it through `preload("res://game/progress.gd")`.

## Any setting changed, whether by the player or by `open()` reading a save.
signal settings_changed

const DEFAULT_PATH: String = "user://progress.json"
const FORMAT_VERSION: int = 1

## Look sensitivity is a multiplier on the player's base mouse speed.
const LOOK_SENSITIVITY_DEFAULT: float = 1.0
const LOOK_SENSITIVITY_MIN: float = 0.25
const LOOK_SENSITIVITY_MAX: float = 3.0
## Master volume, linear 0 (muted) to 1 (full).
const VOLUME_DEFAULT: float = 0.8

var _path: String = ""
var _completed: Array[String] = []
var _look_sensitivity: float = LOOK_SENSITIVITY_DEFAULT
var _fullscreen: bool = false
var _volume: float = VOLUME_DEFAULT


func _ready() -> void:
	Sim.mission_completed.connect(mark_completed)


## Reads the save at `path` (a missing or unreadable file means a fresh start),
## applies its settings, and saves every later change there.
func open(path: String = DEFAULT_PATH) -> void:
	_path = path
	_reset()
	_read()
	apply_settings()
	settings_changed.emit()


## Back to memory only, with defaults. Nothing is written.
func close() -> void:
	_path = ""
	_reset()
	settings_changed.emit()


func is_open() -> bool:
	return not _path.is_empty()


func path() -> String:
	return _path


# --- missions -------------------------------------------------------------------


func is_completed(scenario_id: String) -> bool:
	return scenario_id in _completed


func completed_ids() -> Array[String]:
	return _completed.duplicate()


func mark_completed(scenario_id: String) -> void:
	if scenario_id.is_empty() or is_completed(scenario_id):
		return
	_completed.append(scenario_id)
	_save()


# --- settings -------------------------------------------------------------------


func look_sensitivity() -> float:
	return _look_sensitivity


func set_look_sensitivity(value: float) -> void:
	value = clampf(value, LOOK_SENSITIVITY_MIN, LOOK_SENSITIVITY_MAX)
	if is_equal_approx(value, _look_sensitivity):
		return
	_look_sensitivity = value
	_changed()


func fullscreen() -> bool:
	return _fullscreen


func set_fullscreen(value: bool) -> void:
	if value == _fullscreen:
		return
	_fullscreen = value
	_changed()


func volume() -> float:
	return _volume


func set_volume(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if is_equal_approx(value, _volume):
		return
	_volume = value
	_changed()


## Pushes the window and audio settings to the engine. Look sensitivity is read
## by `game/main.gd`, which hands it to the player.
func apply_settings() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, _volume <= 0.0)
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(_volume, 0.0001)))
	# The headless test driver has no window to resize.
	if DisplayServer.get_name() == "headless":
		return
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	var is_full: bool = mode in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if is_full != _fullscreen:
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if _fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)


# --- internals ------------------------------------------------------------------


func _changed() -> void:
	apply_settings()
	_save()
	settings_changed.emit()


func _reset() -> void:
	_completed = []
	_look_sensitivity = LOOK_SENSITIVITY_DEFAULT
	_fullscreen = false
	_volume = VOLUME_DEFAULT


## Takes each value that is present and well-typed, and ignores the rest, so a
## hand-edited or older save never stops the game from starting.
func _read() -> void:
	if not FileAccess.file_exists(_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if not data is Dictionary:
		push_warning("%s: not a progress file, starting fresh" % _path)
		return
	var completed: Variant = data.get("completed")
	if completed is Array:
		for id: Variant in completed:
			if id is String and not id.is_empty() and not id in _completed:
				_completed.append(id)
	var settings: Variant = data.get("settings")
	if not settings is Dictionary:
		return
	var look: Variant = settings.get("look_sensitivity")
	if look is float or look is int:
		_look_sensitivity = clampf(float(look), LOOK_SENSITIVITY_MIN, LOOK_SENSITIVITY_MAX)
	var full: Variant = settings.get("fullscreen")
	if full is bool:
		_fullscreen = full
	var vol: Variant = settings.get("volume")
	if vol is float or vol is int:
		_volume = clampf(float(vol), 0.0, 1.0)


func _save() -> void:
	if not is_open():
		return
	var data: Dictionary = {
		"version": FORMAT_VERSION,
		"completed": _completed,
		"settings": {
			"look_sensitivity": _look_sensitivity,
			"fullscreen": _fullscreen,
			"volume": _volume,
		},
	}
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("%s: could not save progress (%s)" % [_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")
