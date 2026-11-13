class_name SettingsPanel
extends VBoxContainer
## Mouse sensitivity, fullscreen and volume controls (task 1.31). Each change
## goes straight to the `Progress` autoload, which applies and saves it; the
## controls follow `Progress.settings_changed`, so they always show what is
## saved. Built in code, like the other UI screens.

const LABEL_WIDTH: float = 180.0
const CONTROL_WIDTH: float = 260.0
const TEXT: Color = Color(0.85, 0.88, 0.90)

var _look: HSlider
var _look_value: Label
var _fullscreen: CheckButton
var _volume: HSlider
var _volume_value: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_build()
	_sync()
	Progress.settings_changed.connect(_sync)


func look_slider() -> HSlider:
	return _look


func fullscreen_toggle() -> CheckButton:
	return _fullscreen


func volume_slider() -> HSlider:
	return _volume


## The value text beside each slider, e.g. "1.00x" and "80%".
func look_value_text() -> String:
	return _look_value.text


func volume_value_text() -> String:
	return _volume_value.text


# --- internals ------------------------------------------------------------------


func _sync() -> void:
	_look.set_value_no_signal(Progress.look_sensitivity())
	_fullscreen.set_pressed_no_signal(Progress.fullscreen())
	_volume.set_value_no_signal(Progress.volume())
	_look_value.text = "%.2fx" % Progress.look_sensitivity()
	_volume_value.text = "%d%%" % roundi(Progress.volume() * 100.0)


func _build() -> void:
	_look = _slider(
		Progress.LOOK_SENSITIVITY_MIN, Progress.LOOK_SENSITIVITY_MAX, 0.05, Progress.set_look_sensitivity
	)
	_look_value = _value_label()
	_row("Mouse sensitivity", [_look, _look_value])

	_fullscreen = CheckButton.new()
	_fullscreen.toggled.connect(Progress.set_fullscreen)
	_row("Fullscreen", [_fullscreen])

	_volume = _slider(0.0, 1.0, 0.05, Progress.set_volume)
	_volume_value = _value_label()
	_row("Volume", [_volume, _volume_value])


func _slider(min_value: float, max_value: float, step: float, on_change: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(CONTROL_WIDTH, 24.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(on_change)
	return slider


func _value_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = 56.0
	label.add_theme_color_override("font_color", TEXT)
	return label


func _row(title: String, controls: Array[Control]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = LABEL_WIDTH
	label.add_theme_color_override("font_color", TEXT)
	row.add_child(label)
	for control in controls:
		row.add_child(control)
	add_child(row)
