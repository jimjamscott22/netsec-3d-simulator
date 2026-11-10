class_name TestDeviceModels
extends GdUnitTestSuite

const SIM_SCRIPT: GDScript = preload("res://game/sim.gd")
const MODELS: Dictionary[String, PackedScene] = {
	"router_2port": preload("res://world/devices/router_2port.tscn"),
	"switch_24": preload("res://world/devices/switch_24.tscn"),
	"pc": preload("res://world/devices/pc.tscn"),
}


func _instantiate(model: String) -> DeviceModel:
	return auto_free(MODELS[model].instantiate()) as DeviceModel


func _led(socket: PortSocket) -> StandardMaterial3D:
	var mesh: MeshInstance3D = socket.get_node("LED") as MeshInstance3D
	return mesh.material_override as StandardMaterial3D


func test_each_m1_device_exposes_one_socket_per_physical_interface() -> void:
	var sim: Node = auto_free(SIM_SCRIPT.new())
	var result: LoadResult = sim.load_scenario_id("m1_vlan_ping")
	assert_bool(result.ok).is_true()
	var view: ScenarioView = sim.scenario_view()

	for placement: Dictionary in view.devices():
		var model: DeviceModel = _instantiate(placement["model"])
		var interfaces: Array[String] = placement["interfaces"]
		var sockets: Array[PortSocket] = model.socket_markers()
		assert_int(sockets.size()).is_equal(interfaces.size())
		for socket: PortSocket in sockets:
			assert_object(socket).is_not_null()


func test_switch_orders_access_sockets_left_to_right_by_row_then_uplinks() -> void:
	var sockets: Array[PortSocket] = _instantiate("switch_24").socket_markers()
	var upper_row: float = sockets[0].position.y
	var lower_row: float = sockets[12].position.y
	assert_float(upper_row).is_greater(lower_row)

	for row_start: int in [0, 12]:
		for index: int in range(row_start + 1, row_start + 12):
			assert_float(sockets[index].position.y).is_equal(sockets[row_start].position.y)
			assert_float(sockets[index].position.x).is_greater(sockets[index - 1].position.x)

	assert_float(sockets[24].position.x).is_greater(sockets[11].position.x)
	assert_float(sockets[25].position.x).is_greater(sockets[24].position.x)


func test_led_renders_link_state_without_changing_other_sockets() -> void:
	var sockets: Array[PortSocket] = _instantiate("router_2port").socket_markers()
	var other_model: Array[PortSocket] = _instantiate("router_2port").socket_markers()
	var led: StandardMaterial3D = _led(sockets[0])
	assert_bool(led.emission_enabled).is_false()

	sockets[0].set_link_state(true, false)
	assert_bool(led.emission_enabled).is_true()
	assert_bool(led.emission.is_equal_approx(PortSocket.LED_AMBER)).is_true()

	sockets[0].set_link_state(true, true)
	assert_bool(led.emission.is_equal_approx(PortSocket.LED_GREEN)).is_true()
	assert_bool(_led(sockets[1]).emission_enabled).is_false()
	assert_bool(_led(other_model[0]).emission_enabled).is_false()

	sockets[0].set_link_state(false, false)
	assert_bool(led.emission_enabled).is_false()
	assert_bool(led.albedo_color.is_equal_approx(PortSocket.LED_OFF)).is_true()
