class_name TestScenarioValidator
extends GdUnitTestSuite
## Every test edits the known-good fixture in one way and asserts the exact
## error list, so each also proves the mistake is reported once with its JSON
## path and does not cascade into more errors.

const FIXTURE: String = "res://tests/scenario/fixtures/valid_m1.json"
const FILE_ID: String = "m1_vlan_ping"

# Indices into the fixture's arrays.
const R1: int = 0
const S1: int = 1
const PC_A: int = 2
const PC_B: int = 3

const SNAKE: String = "must be snake_case (lowercase letters, digits and underscores, starting with a letter)"
const REASONS: String = "NO_IP, NO_LINK, ADMIN_DOWN, VLAN_MISMATCH, WRONG_SUBNET, NO_GATEWAY, NO_ROUTE, HOST_UNREACHABLE, ACL_DENIED"


# --- helpers ----------------------------------------------------------------


func _load() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(FIXTURE)
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).override_failure_message("fixture did not parse").is_true()
	return parsed


func _walk(root: Variant, path: Array) -> Variant:
	var node: Variant = root
	for key: Variant in path:
		node = node[key]
	return node


## Errors after setting `value` at `path` in a fresh copy of the fixture.
func _with(path: Array, value: Variant) -> Array[String]:
	var d: Dictionary = _load()
	_walk(d, path.slice(0, -1))[path[-1]] = value
	return ScenarioValidator.validate(d, FILE_ID)


func _without(path: Array) -> Array[String]:
	var d: Dictionary = _load()
	var parent: Variant = _walk(d, path.slice(0, -1))
	parent.erase(path[-1])
	return ScenarioValidator.validate(d, FILE_ID)


## Errors after `edit` runs on a fresh copy of the fixture.
func _edit(edit: Callable) -> Array[String]:
	var d: Dictionary = _load()
	edit.call(d)
	return ScenarioValidator.validate(d, FILE_ID)


func _device(index: int) -> String:
	return "devices[%d]" % index


# --- the known-good file -----------------------------------------------------


func test_the_m1_example_is_valid() -> void:
	assert_array(ScenarioValidator.validate(_load(), FILE_ID)).is_empty()


func test_file_name_is_optional() -> void:
	assert_array(ScenarioValidator.validate(_load())).is_empty()


func test_json_numbers_arrive_as_floats_and_still_count_as_integers() -> void:
	var d: Dictionary = _load()
	assert_bool(d["spare_cables"] is float).is_true()
	assert_array(ScenarioValidator.validate(d, FILE_ID)).is_empty()
	d["spare_cables"] = 1
	d["devices"][R1]["slot"] = 1
	assert_array(ScenarioValidator.validate(d, FILE_ID)).is_empty()


func test_validation_does_not_change_the_data() -> void:
	var d: Dictionary = _load()
	var before: String = JSON.stringify(d)
	ScenarioValidator.validate(d, FILE_ID)
	assert_str(JSON.stringify(d)).is_equal(before)


func test_the_same_input_gives_the_same_errors() -> void:
	var d: Dictionary = _load()
	d["title"] = ""
	d["devices"][R1]["model"] = "nope"
	d["hints"][0]["reason"] = "X"
	assert_array(ScenarioValidator.validate(d, FILE_ID)).is_equal(ScenarioValidator.validate(d, FILE_ID))


func test_a_scenario_must_be_an_object() -> void:
	for bad: Variant in [[], "text", null, 5, true]:
		assert_array(ScenarioValidator.validate(bad)).is_equal(["$: a scenario must be a JSON object"])


# --- all errors at once ---------------------------------------------------------


func test_independent_mistakes_are_all_reported_in_file_order() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["title"] = ""
		d["devices"][R1]["model"] = "nope"
		d["links"][1]["locked"] = "yes"
		d["hints"][0]["reason"] = "X"
	)
	assert_array(errors).is_equal([
		"title: must be a non-empty string",
		'devices[0].model: unknown model "nope"',
		"links[1].locked: must be true or false",
		"hints[0].reason: must be a ping fail reason (%s)" % REASONS,
	])


func test_a_bad_device_does_not_flag_everything_that_mentions_it() -> void:
	# R1's model is wrong; its links, reserved port and config objectives are fine.
	assert_array(_with([ "devices", R1, "model"], "switch_24")).is_equal(['devices[0].model: model "switch_24" is not a router'])
	assert_array(_with(["devices", R1, "type"], "firewall")).is_equal(["devices[0].type: must be one of router, switch, host, server"])
	assert_array(_with(["devices", R1, "model"], "nope")).is_equal(['devices[0].model: unknown model "nope"'])


# --- top level ----------------------------------------------------------------------


func test_required_top_level_keys() -> void:
	for key in ["schema_version", "id", "sequence", "title", "briefing", "links", "objectives", "solution"]:
		assert_array(_without([key])).override_failure_message(key).is_equal(["%s: required" % key])


func test_missing_devices_is_reported_first() -> void:
	var errors: Array[String] = _without(["devices"])
	assert_str(errors[0]).is_equal("devices: required")


func test_schema_version() -> void:
	for bad: Variant in [2, 0, "1", 1.5, null]:
		assert_array(_with(["schema_version"], bad)).override_failure_message(str(bad)).is_equal(["schema_version: must be 1"])


func test_id_must_be_snake_case() -> void:
	for bad: Variant in ["M1 bad", "1abc", "UPPER", "kebab-case", "", 5]:
		assert_array(_with(["id"], bad)).override_failure_message(str(bad)).is_equal(["id: " + SNAKE])


func test_id_must_match_the_file_name() -> void:
	assert_array(ScenarioValidator.validate(_load(), "other_name")).is_equal(['id: must match the file name "other_name"'])


func test_sequence() -> void:
	for bad: Variant in [0, -1, 1.5, "1", null]:
		assert_array(_with(["sequence"], bad)).override_failure_message(str(bad)).is_equal(["sequence: must be an integer of at least 1"])
	assert_array(_with(["sequence"], 7)).is_empty()


func test_title_and_briefing_must_be_text() -> void:
	for key in ["title", "briefing"]:
		for bad: Variant in ["", 5, null]:
			assert_array(_with([key], bad)).override_failure_message(key).is_equal(["%s: must be a non-empty string" % key])


func test_spare_cables() -> void:
	for bad: Variant in [-1, 1.5, "1", null]:
		assert_array(_with(["spare_cables"], bad)).override_failure_message(str(bad)).is_equal(["spare_cables: must be an integer of at least 0"])


func test_spare_cables_is_optional_and_defaults_to_none() -> void:
	var errors: Array[String] = _without(["spare_cables"])
	assert_array(errors).is_equal(["solution: plugs in 1 cable(s) but spare_cables is 0"])


func test_debrief_is_optional_text() -> void:
	assert_array(_with(["debrief"], "Fixed with a trunk and subinterfaces.")).is_empty()
	for bad: Variant in ["", 5]:
		assert_array(_with(["debrief"], bad)).is_equal(["debrief: must be a non-empty string"])


func test_unknown_top_level_keys() -> void:
	assert_array(_with(["speare_cables"], 2)).is_equal(["speare_cables: unknown key"])


func test_later_milestone_keys_say_when_they_arrive() -> void:
	assert_array(_with(["logs"], [])).is_equal(["logs: is not supported yet (arrives in M2)"])
	assert_array(_with(["report"], {})).is_equal(["report: is not supported yet (arrives in M2)"])


# --- devices ---------------------------------------------------------------------


func test_devices_must_be_a_non_empty_array() -> void:
	var d: Dictionary = _load()
	d["devices"] = {}
	assert_str(ScenarioValidator.validate(d, FILE_ID)[0]).is_equal("devices: must be an array")
	d["devices"] = []
	assert_str(ScenarioValidator.validate(d, FILE_ID)[0]).is_equal("devices: needs at least one device")


func test_a_device_must_be_an_object() -> void:
	var d: Dictionary = _load()
	d["devices"][PC_B] = 5
	assert_str(ScenarioValidator.validate(d, FILE_ID)[0]).is_equal("devices[3]: must be an object")


func test_required_device_keys() -> void:
	for key in ["id", "type", "model"]:
		var errors: Array[String] = _without(["devices", PC_B, key])
		assert_str(errors[0]).override_failure_message(key).is_equal("devices[3].%s: required" % key)


func test_device_id_rules() -> void:
	for bad: Variant in ["PC B", "R:1", "", "-x", 5]:
		var errors: Array[String] = _with(["devices", PC_B, "id"], bad)
		assert_str(errors[0]).override_failure_message(str(bad)).is_equal("devices[3].id: must be letters, digits, '-' or '_' (no spaces or ':')")


func test_duplicate_device_id() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["devices"].append({"id": "R1", "type": "router", "model": "router_2port", "rack": "rack_a", "slot": 2})
	)
	assert_array(errors).is_equal(['devices[4].id: duplicate device id "R1"'])


func test_device_type_and_model() -> void:
	assert_array(_with(["devices", S1, "model"], "switch_48")).is_equal(['devices[1].model: unknown model "switch_48"'])
	assert_array(_with(["devices", S1, "model"], 5)).is_equal(["devices[1].model: unknown model int"])
	assert_array(_with(["devices", PC_A, "model"], "server")).is_equal(['devices[2].model: model "server" is not a host'])


func test_unknown_device_key() -> void:
	assert_array(_with(["devices", R1, "color"], "red")).is_equal(["devices[0].color: unknown key"])


func test_hostname_is_optional_and_one_word() -> void:
	assert_array(_without(["devices", R1, "hostname"])).is_empty()
	assert_array(_with(["devices", R1, "hostname"], "My Router")).is_equal(["devices[0].hostname: must be a single word with no spaces"])
	assert_array(_with(["devices", R1, "hostname"], 5)).is_equal(["devices[0].hostname: must be a single word with no spaces"])


func test_a_server_is_racked_like_a_router() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["devices"].append({"id": "SRV", "type": "server", "model": "server", "rack": "rack_a", "slot": 5, "config": {"ip": "10.0.0.5", "mask": "255.255.255.0"}})
	)
	assert_array(errors).is_empty()


# --- placement --------------------------------------------------------------------


func test_racked_devices_need_rack_and_slot() -> void:
	assert_array(_without(["devices", R1, "rack"])).is_equal(["devices[0].rack: required"])
	assert_array(_without(["devices", R1, "slot"])).is_equal(["devices[0].slot: required"])
	assert_array(_with(["devices", R1, "rack"], "")).is_equal(["devices[0].rack: must be a non-empty string"])
	for bad: Variant in [0, -1, 1.5, "1"]:
		assert_array(_with(["devices", R1, "slot"], bad)).override_failure_message(str(bad)).is_equal(["devices[0].slot: must be an integer of at least 1"])


func test_racked_devices_do_not_take_a_desk() -> void:
	assert_array(_with(["devices", R1, "desk"], "desk_9")).is_equal(["devices[0].desk: only hosts use desk; racked devices use rack and slot"])


func test_hosts_need_a_desk_and_no_rack() -> void:
	assert_array(_without(["devices", PC_A, "desk"])).is_equal(["devices[2].desk: required"])
	assert_array(_with(["devices", PC_A, "desk"], "")).is_equal(["devices[2].desk: must be a non-empty string"])
	assert_array(_with(["devices", PC_A, "rack"], "rack_a")).is_equal(["devices[2].rack: hosts use desk, not rack and slot"])
	assert_array(_with(["devices", PC_A, "slot"], 2)).is_equal(["devices[2].slot: hosts use desk, not rack and slot"])


func test_two_devices_cannot_share_a_spot() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["devices"][S1]["rack"] = "rack_a"
		d["devices"][S1]["slot"] = 1
	)
	assert_array(errors).is_equal(['devices[1]: same spot as "R1" (rack_a/1)'])
	assert_array(_with(["devices", PC_B, "desk"], "desk_1")).is_equal(['devices[3]: same spot as "PC-A" (desk_1)'])


func test_the_same_slot_in_different_racks_is_fine() -> void:
	assert_array(_with(["devices", S1, "rack"], "rack_b")).is_empty()


# --- router and switch config ------------------------------------------------------


func _router_config(config: Variant) -> Array[String]:
	return _with(["devices", R1, "config"], config)


func _switch_config(config: Variant) -> Array[String]:
	return _with(["devices", S1, "config"], config)


func test_config_must_be_an_object() -> void:
	assert_array(_router_config(5)).is_equal(["devices[0].config: must be an object"])
	assert_array(_with(["devices", PC_A, "config"], [])).is_equal(["devices[2].config: must be an object"])


func test_config_is_optional() -> void:
	assert_array(_without(["devices", R1, "config"])).is_empty()


func test_vlans_belong_to_switches_and_routes_to_routers() -> void:
	assert_array(_router_config({"vlans": {}})).is_equal(["devices[0].config.vlans: only switches have vlans"])
	assert_array(_switch_config({"routes": []})).is_equal(["devices[1].config.routes: only routers have routes"])


func test_later_milestone_config_says_when_it_arrives() -> void:
	for key in ["users", "domain_name", "lines"]:
		assert_array(_router_config({key: {}})).override_failure_message(key).is_equal(["devices[0].config.%s: is not supported yet (arrives in M4)" % key])


func test_unknown_config_key() -> void:
	assert_array(_router_config({"foo": 1})).is_equal(["devices[0].config.foo: unknown key"])


func test_enable_secret() -> void:
	assert_array(_router_config({"enable_secret": "class"})).is_empty()
	for bad: Variant in ["", 5]:
		assert_array(_router_config({"enable_secret": bad})).is_equal(["devices[0].config.enable_secret: must be a non-empty string"])


func test_interfaces_must_be_an_object() -> void:
	assert_array(_router_config({"interfaces": []})).is_equal(["devices[0].config.interfaces: must be an object"])


func test_interface_names_are_normalized_and_must_exist() -> void:
	assert_array(_router_config({"interfaces": {"g0/1": {}, "Gi0/0": {}}})).is_empty()
	assert_array(_router_config({"interfaces": {"banana": {}}})).is_equal(['devices[0].config.interfaces.banana: invalid interface name "banana"'])
	assert_array(_router_config({"interfaces": {"Gi0/9": {}}})).is_equal(
		['devices[0].config.interfaces["Gi0/9"]: unknown interface "GigabitEthernet0/9" for model router_2port']
	)
	assert_array(_switch_config({"interfaces": {"Fa0/25": {}}})).is_equal(
		['devices[1].config.interfaces["Fa0/25"]: unknown interface "FastEthernet0/25" for model switch_24']
	)


func test_the_same_interface_cannot_be_listed_twice() -> void:
	assert_array(_switch_config({"interfaces": {"Gi0/1": {}, "GigabitEthernet0/1": {}}})).is_equal(
		['devices[1].config.interfaces["GigabitEthernet0/1"]: same interface as "Gi0/1"']
	)


func test_a_router_can_start_with_subinterfaces_of_its_real_ports() -> void:
	var sub: Dictionary = {"dot1q_vlan": 10, "ip": "192.168.10.1", "mask": "255.255.255.0", "admin_up": true}
	assert_array(_router_config({"interfaces": {"Gi0/0.10": sub}})).is_empty()
	assert_array(_router_config({"interfaces": {"Gi0/5.10": {}}})).is_equal(
		['devices[0].config.interfaces["Gi0/5.10"]: unknown interface "GigabitEthernet0/5.10" for model router_2port']
	)
	assert_array(_switch_config({"interfaces": {"Gi0/1.10": {}}})).is_equal(
		['devices[1].config.interfaces["Gi0/1.10"]: subinterfaces exist only on routers']
	)


func test_router_interface_fields() -> void:
	var p: String = 'devices[0].config.interfaces["Gi0/0"]'
	var cases: Array = [
		[{"foo": 1}, p + ".foo: unknown key"],
		[{"mode": "access"}, p + ".mode: not valid on a router interface"],
		[{"dot1q_vlan": 10}, p + ".dot1q_vlan: only subinterfaces have dot1q_vlan"],
		[{"ip": "300.1.1.1", "mask": "255.255.255.0"}, p + ".ip: must be an IPv4 address such as 192.168.10.1"],
		[{"ip": "10.0.0.1", "mask": "255.0.255.0"}, p + ".mask: must be a subnet mask such as 255.255.255.0"],
		[{"ip": "10.0.0.1"}, p + ": ip and mask must be given together"],
		[{"mask": "255.255.255.0"}, p + ": ip and mask must be given together"],
		[{"admin_up": "yes"}, p + ".admin_up: must be true or false"],
	]
	for row: Array in cases:
		assert_array(_router_config({"interfaces": {"Gi0/0": row[0]}})).override_failure_message(str(row[0])).is_equal([row[1]])
	assert_array(_router_config({"interfaces": {"Gi0/0": {"ip": "10.0.0.1", "mask": "255.255.255.252", "admin_up": true}}})).is_empty()


func test_subinterface_tag_must_be_a_vlan_id() -> void:
	for bad: Variant in [0, 4095, 1.5, "10"]:
		assert_array(_router_config({"interfaces": {"Gi0/0.10": {"dot1q_vlan": bad}}})).override_failure_message(str(bad)).is_equal(
			['devices[0].config.interfaces["Gi0/0.10"].dot1q_vlan: must be a VLAN id from 1 to 4094']
		)


func test_switch_interface_fields() -> void:
	var p: String = 'devices[1].config.interfaces["Gi0/1"]'
	var cases: Array = [
		[{"foo": 1}, p + ".foo: unknown key"],
		[{"ip": "10.0.0.1"}, p + ".ip: not valid on a switch interface"],
		[{"mode": "dynamic"}, p + '.mode: must be "access" or "trunk"'],
		[{"access_vlan": 5000}, p + ".access_vlan: must be a VLAN id from 1 to 4094"],
		[{"trunk_allowed": []}, p + ".trunk_allowed: must not be empty (leave it out to allow every VLAN)"],
		[{"trunk_allowed": [10, 10]}, p + ".trunk_allowed: must list each VLAN once"],
		[{"trunk_allowed": ["a"]}, p + ".trunk_allowed: must be a list of VLAN ids from 1 to 4094"],
		[{"admin_up": 1}, p + ".admin_up: must be true or false"],
	]
	for row: Array in cases:
		assert_array(_switch_config({"interfaces": {"Gi0/1": row[0]}})).override_failure_message(str(row[0])).is_equal([row[1]])
	assert_array(_switch_config({"interfaces": {"Gi0/1": {"mode": "trunk", "trunk_allowed": [10, 20]}}})).is_empty()


func test_interface_fields_must_be_an_object() -> void:
	assert_array(_switch_config({"interfaces": {"Gi0/1": "trunk"}})).is_equal(['devices[1].config.interfaces["Gi0/1"]: must be an object'])


func test_starting_vlans() -> void:
	assert_array(_switch_config({"vlans": {"10": "SALES", "20": "ENG"}})).is_empty()
	assert_array(_switch_config({"vlans": {"abc": "X"}})).is_equal(["devices[1].config.vlans.abc: VLAN ids are numbers from 1 to 4094"])
	for key in ["0", "4095", "010", "-5"]:
		assert_array(_switch_config({"vlans": {key: "X"}})).override_failure_message(key).is_equal(
			['devices[1].config.vlans["%s"]: VLAN ids are numbers from 1 to 4094' % key]
		)
	assert_array(_switch_config({"vlans": {"20": "two words"}})).is_equal(['devices[1].config.vlans["20"]: name must be a single word with no spaces'])
	assert_array(_switch_config({"vlans": {"20": ""}})).is_equal(['devices[1].config.vlans["20"]: name must be a single word with no spaces'])
	assert_array(_switch_config({"vlans": []})).is_equal(["devices[1].config.vlans: must be an object"])


func test_starting_routes() -> void:
	var route: Dictionary = {"network": "10.9.0.0", "mask": "255.255.0.0", "next_hop": "192.168.10.2"}
	assert_array(_router_config({"routes": [route]})).is_empty()
	assert_array(_router_config({"routes": {}})).is_equal(["devices[0].config.routes: must be an array"])
	assert_array(_router_config({"routes": [5]})).is_equal(["devices[0].config.routes[0]: must be an object"])
	var cases: Array = [
		[{"mask": "255.255.0.0", "next_hop": "192.168.10.2"}, "devices[0].config.routes[0].network: required"],
		[{"network": "10.9.0.0", "next_hop": "192.168.10.2"}, "devices[0].config.routes[0].mask: required"],
		[{"network": "10.9.0.0", "mask": "255.255.0.0"}, "devices[0].config.routes[0].next_hop: required"],
		[{"network": "nope", "mask": "255.255.0.0", "next_hop": "192.168.10.2"}, "devices[0].config.routes[0].network: must be an IPv4 address such as 192.168.10.1"],
		[{"network": "10.9.0.0", "mask": "255.0.255.0", "next_hop": "192.168.10.2"}, "devices[0].config.routes[0].mask: must be a subnet mask such as 255.255.255.0"],
		[{"network": "10.9.0.0", "mask": "255.255.0.0", "next_hop": "x"}, "devices[0].config.routes[0].next_hop: must be an IPv4 address such as 192.168.10.1"],
		[{"network": "10.9.0.5", "mask": "255.255.255.0", "next_hop": "192.168.10.2"}, "devices[0].config.routes[0].network: 10.9.0.5 is not a network address for mask 255.255.255.0"],
		[{"network": "10.9.0.0", "mask": "255.255.0.0", "next_hop": "192.168.10.2", "metric": 5}, "devices[0].config.routes[0].metric: unknown key"],
	]
	for row: Array in cases:
		assert_array(_router_config({"routes": [row[0]]})).override_failure_message(str(row[0])).is_equal([row[1]])


# --- host and server config ------------------------------------------------------


func test_host_config_rules() -> void:
	var cases: Array = [
		[["devices", PC_A, "config", "mask"], null, "devices[2].config: ip and mask must be given together"],
		[["devices", PC_A, "config", "ip"], null, "devices[2].config: ip and mask must be given together"],
		[["devices", PC_A, "config", "gateway"], "x", "devices[2].config.gateway: must be an IPv4 address such as 192.168.10.1"],
		[["devices", PC_A, "config", "ip"], "999.1.1.1", "devices[2].config.ip: must be an IPv4 address such as 192.168.10.1"],
		[["devices", PC_A, "config", "mask"], "255.0.255.0", "devices[2].config.mask: must be a subnet mask such as 255.255.255.0"],
		[["devices", PC_A, "config", "locked"], "yes", "devices[2].config.locked: must be true or false"],
		[["devices", PC_A, "config", "dns"], "8.8.8.8", "devices[2].config.dns: unknown key"],
	]
	for row: Array in cases:
		var errors: Array[String]
		if row[1] == null:
			errors = _without(row[0])
		else:
			errors = _with(row[0], row[1])
		assert_array(errors).override_failure_message(str(row[0])).is_equal([row[2]])


func test_a_host_may_leave_out_its_gateway_and_locked() -> void:
	assert_array(_without(["devices", PC_A, "config", "gateway"])).is_empty()
	assert_array(_without(["devices", PC_A, "config", "locked"])).is_empty()


func test_a_host_has_no_interfaces_or_vlans() -> void:
	assert_array(_with(["devices", PC_A, "config", "interfaces"], {})).is_equal(["devices[2].config.interfaces: unknown key"])


func test_server_only_keys_say_when_they_arrive() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["devices"].append({"id": "SRV", "type": "server", "model": "server", "rack": "rack_a", "slot": 5, "config": {"files": {}, "vulns": []}})
	)
	assert_array(errors).is_equal([
		"devices[4].config.files: is not supported yet (arrives in M3)",
		"devices[4].config.vulns: is not supported yet (arrives in M3)",
	])


# --- reserved ports ---------------------------------------------------------------


func test_reserved_ports() -> void:
	assert_array(_with(["reserved_ports"], [])).is_empty()
	assert_array(_with(["reserved_ports"], "R1:Gi0/1")).is_equal(["reserved_ports: must be an array"])
	assert_array(_with(["reserved_ports"], [5])).is_equal(['reserved_ports[0]: must be a port such as "S1:Fa0/1"'])
	assert_array(_with(["reserved_ports"], ["Gi0/1"])).is_equal(['reserved_ports[0]: must be a port such as "S1:Fa0/1"'])
	assert_array(_with(["reserved_ports"], ["X9:Gi0/1"])).is_equal(['reserved_ports[0]: unknown device "X9"'])
	assert_array(_with(["reserved_ports"], ["R1:banana"])).is_equal(['reserved_ports[0]: invalid interface name "banana"'])
	assert_array(_with(["reserved_ports"], ["R1:Gi0/7"])).is_equal(['reserved_ports[0]: unknown interface "GigabitEthernet0/7" for model router_2port'])
	assert_array(_with(["reserved_ports"], ["R1:Gi0/1.5"])).is_equal(["reserved_ports[0]: a subinterface has no socket; cables use physical ports"])


func test_a_port_cannot_be_reserved_twice_even_by_another_name() -> void:
	assert_array(_with(["reserved_ports"], ["R1:Gi0/1", "R1:g0/1"])).is_equal(["reserved_ports[1]: R1:GigabitEthernet0/1 is already reserved"])


# --- links ------------------------------------------------------------------------


func test_links_must_be_an_array_and_each_an_object() -> void:
	assert_array(_with(["links"], {})).is_equal(["links: must be an array"])
	assert_array(_with(["links", 0], 5)).is_equal(["links[0]: must be an object"])
	assert_array(_with(["links"], [])).is_empty()


func test_link_ends_are_required_ports() -> void:
	assert_array(_without(["links", 0, "a"])).is_equal(["links[0].a: required"])
	assert_array(_without(["links", 0, "b"])).is_equal(["links[0].b: required"])
	assert_array(_with(["links", 0, "a"], 5)).is_equal(['links[0].a: must be a port such as "S1:Fa0/1"'])
	assert_array(_with(["links", 0, "a"], "nocolon")).is_equal(['links[0].a: must be a port such as "S1:Fa0/1"'])


func test_link_ports_must_exist() -> void:
	assert_array(_with(["links", 0, "a"], "X9:Gi0/0")).is_equal(['links[0].a: unknown device "X9"'])
	assert_array(_with(["links", 0, "a"], "R1:banana")).is_equal(['links[0].a: invalid interface name "banana"'])
	assert_array(_with(["links", 1, "a"], "S1:Fa0/99")).is_equal(['links[1].a: unknown interface "FastEthernet0/99" for model switch_24'])
	assert_array(_with(["links", 0, "a"], "R1:Gi0/0.10")).is_equal(["links[0].a: a subinterface has no socket; cables use physical ports"])


func test_link_ports_accept_short_names() -> void:
	assert_array(_with(["links", 1, "a"], "S1:fa0/1")).is_empty()
	assert_array(_with(["links", 1, "b"], "PC-A:eth0")).is_empty()


func test_a_cable_needs_two_devices() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["reserved_ports"] = []
		d["links"][0]["b"] = "R1:Gi0/1"
	)
	assert_array(errors).is_equal(["links[0]: a cable needs two different devices"])


func test_a_port_is_used_by_one_link() -> void:
	assert_array(_with(["links", 1, "a"], "S1:Gi0/1")).is_equal(["links[1].a: S1:GigabitEthernet0/1 is already used by links[0]"])
	assert_array(_with(["links", 1, "a"], "S1:gigabitethernet0/1")).is_equal(["links[1].a: S1:GigabitEthernet0/1 is already used by links[0]"])


func test_no_start_link_may_use_a_reserved_port() -> void:
	assert_array(_with(["links", 0, "a"], "R1:Gi0/1")).is_equal(["links[0].a: R1:GigabitEthernet0/1 is reserved; no cable may use it"])


func test_link_flags() -> void:
	assert_array(_with(["links", 0, "locked"], "yes")).is_equal(["links[0].locked: must be true or false"])
	assert_array(_without(["links", 0, "locked"])).is_empty()
	assert_array(_with(["links", 0, "mood"], "blue")).is_equal(["links[0].mood: unknown key"])


# --- objectives (shared rules) --------------------------------------------------


func test_objectives_shape() -> void:
	assert_array(_with(["objectives"], {})).is_equal(["objectives: must be an array"])
	assert_array(_with(["objectives"], [])).is_equal(["objectives: needs at least one objective"])
	assert_array(_with(["objectives", 0], 5)).is_equal(["objectives[0]: must be an object"])


func test_objective_id_rules() -> void:
	assert_array(_without(["objectives", 0, "id"])).is_equal(["objectives[0].id: required"])
	for bad: Variant in ["Bad Id", "1x", "", 5]:
		assert_array(_with(["objectives", 0, "id"], bad)).override_failure_message(str(bad)).is_equal(["objectives[0].id: " + SNAKE])
	assert_array(_with(["objectives", 1, "id"], "ping_ab")).is_equal(['objectives[1].id: duplicate objective id "ping_ab"'])


func test_objective_description_and_order() -> void:
	assert_array(_without(["objectives", 0, "description"])).is_equal(["objectives[0].description: required"])
	assert_array(_with(["objectives", 0, "description"], "")).is_equal(["objectives[0].description: must be a non-empty string"])
	for bad: Variant in [0, -1, 1.5, "1"]:
		assert_array(_with(["objectives", 0, "order"], bad)).override_failure_message(str(bad)).is_equal(["objectives[0].order: must be an integer of at least 1"])
	assert_array(_with(["objectives", 0, "order"], 2)).is_empty()


func test_objective_type() -> void:
	assert_array(_without(["objectives", 0, "type"])).is_equal(["objectives[0].type: required"])
	assert_array(_with(["objectives", 0, "type"], "banana")).is_equal(["objectives[0].type: unknown objective type"])
	assert_array(_with(["objectives", 0, "type"], 5)).is_equal(["objectives[0].type: must be a string"])


func test_later_milestone_objective_types_say_when_they_arrive() -> void:
	var due: Dictionary = {"report": "M2", "vuln_patched": "M3", "exploit_test": "M3", "ssh": "M4", "no_ping": "M5"}
	for type: String in due:
		assert_array(_with(["objectives", 0, "type"], type)).override_failure_message(type).is_equal(
			['objectives[0].type: "%s" is not supported yet (arrives in %s)' % [type, due[type]]]
		)


# --- ping objectives -----------------------------------------------------------


func test_ping_objective_requires_from_and_to_ip() -> void:
	assert_array(_without(["objectives", 0, "from"])).is_equal(["objectives[0].from: required"])
	assert_array(_without(["objectives", 0, "to_ip"])).is_equal(["objectives[0].to_ip: required"])


func test_ping_objective_devices_must_exist() -> void:
	assert_array(_with(["objectives", 0, "from"], "PC-Z")).is_equal(['objectives[0].from: unknown device "PC-Z"'])
	assert_array(_with(["objectives", 0, "from"], 5)).is_equal(["objectives[0].from: must be a device id"])
	assert_array(_with(["objectives", 0, "to_device"], "PC-Z")).is_equal(['objectives[0].to_device: unknown device "PC-Z"'])
	assert_array(_with(["objectives", 0, "via"], "R9")).is_equal(['objectives[0].via: unknown device "R9"'])


func test_a_switch_cannot_ping() -> void:
	assert_array(_with(["objectives", 0, "from"], "S1")).is_equal(["objectives[0].from: a switch has no address to ping from"])


func test_only_a_router_can_be_via() -> void:
	assert_array(_with(["objectives", 0, "via"], "PC-B")).is_equal(["objectives[0].via: must be a router (only routers forward packets)"])
	assert_array(_with(["objectives", 0, "via"], "S1")).is_equal(["objectives[0].via: must be a router (only routers forward packets)"])


func test_ping_to_ip_must_be_an_address() -> void:
	for bad: Variant in ["pc-b", "10.0.0", "300.1.1.1", 5]:
		assert_array(_with(["objectives", 0, "to_ip"], bad)).override_failure_message(str(bad)).is_equal(
			["objectives[0].to_ip: must be an IPv4 address such as 192.168.10.1"]
		)


func test_to_device_and_via_are_optional() -> void:
	assert_array(_without(["objectives", 0, "to_device"])).is_empty()
	assert_array(_without(["objectives", 0, "via"])).is_empty()


func test_ping_objective_rejects_other_types_params() -> void:
	assert_array(_with(["objectives", 0, "expect_reason"], "ACL_DENIED")).is_equal(["objectives[0].expect_reason: unknown key"])
	assert_array(_with(["objectives", 0, "path"], ["hostname"])).is_equal(["objectives[0].path: unknown key"])


# --- config objectives --------------------------------------------------------------


func _config_obj(device: String, path: Variant, equals: Variant) -> Array[String]:
	return _edit(func(d: Dictionary) -> void:
		d["objectives"][1] = {"id": "trunk", "type": "config", "description": "x", "device": device, "path": path, "equals": equals}
	)


func test_config_objective_requires_its_params() -> void:
	assert_array(_without(["objectives", 1, "device"])).is_equal(["objectives[1].device: required"])
	assert_array(_without(["objectives", 1, "path"])).is_equal(["objectives[1].path: required"])
	assert_array(_without(["objectives", 1, "equals"])).is_equal(["objectives[1].equals: required"])


func test_config_objective_may_expect_null() -> void:
	assert_array(_config_obj("R1", ["interfaces", "Gi0/0", "ip"], null)).is_empty()
	assert_array(_config_obj("R1", ["interfaces", "Gi0/0.30"], null)).is_empty()


func test_config_objective_device_must_exist() -> void:
	assert_array(_with(["objectives", 1, "device"], "X9")).is_equal(['objectives[1].device: unknown device "X9"'])


func test_config_path_is_a_key_or_a_list_of_keys() -> void:
	assert_array(_config_obj("R1", "hostname", "Router")).is_empty()
	assert_array(_config_obj("R1", ["hostname"], "Router")).is_empty()
	for bad: Variant in [5, [], ""]:
		assert_array(_config_obj("R1", bad, "x")).override_failure_message(str(bad)).is_equal(
			["objectives[1].path: must be a key or a non-empty array of keys"]
		)
	for bad: Variant in [[5], ["interfaces", ""]]:
		assert_array(_config_obj("R1", bad, "x")).override_failure_message(str(bad)).is_equal(["objectives[1].path: every key must be a non-empty string"])


func test_config_path_interfaces_are_normalized() -> void:
	assert_array(_config_obj("S1", ["interfaces", "gi0/1", "mode"], "trunk")).is_empty()
	assert_array(_config_obj("S1", ["interfaces", "GigabitEthernet0/1", "mode"], "trunk")).is_empty()


func test_config_path_must_point_at_something_real() -> void:
	var p: String = "objectives[1].path: "
	assert_array(_config_obj("S1", ["interfaces", "banana", "mode"], "trunk")).is_equal([p + 'invalid interface name "banana"'])
	assert_array(_config_obj("S1", ["interfaces", "Gi0/9", "mode"], "trunk")).is_equal([p + 'unknown interface "GigabitEthernet0/9" for model switch_24'])
	assert_array(_config_obj("S1", ["interfaces", "Gi0/1", "speed"], "100")).is_equal(
		[p + 'unknown interface field "speed" (use one of admin_up, mode, access_vlan, trunk_allowed)']
	)
	assert_array(_config_obj("S1", ["interfaces", "Gi0/1", "dot1q_vlan"], 10)).is_equal(
		[p + 'unknown interface field "dot1q_vlan" (use one of admin_up, mode, access_vlan, trunk_allowed)']
	)
	assert_array(_config_obj("R1", ["interfaces", "Gi0/0", "dot1q_vlan"], 10)).is_equal([p + "only subinterfaces have dot1q_vlan"])
	assert_array(_config_obj("S1", ["interfaces"], "x")).is_equal([p + "unknown config path for a switch (start with one of hostname, interfaces, vlans)"])
	assert_array(_config_obj("S1", ["interfaces", "Gi0/1", "mode", "extra"], "x")).is_equal([p + "unknown config path for a switch (start with one of hostname, interfaces, vlans)"])
	assert_array(_config_obj("R1", ["vlans", "10"], "x")).is_equal([p + "unknown config path for a router (start with one of hostname, interfaces)"])
	assert_array(_config_obj("R1", ["hostname", "x"], "x")).is_equal([p + "unknown config path for a router (start with one of hostname, interfaces)"])


func test_config_path_vlans_on_a_switch() -> void:
	assert_array(_config_obj("S1", ["vlans", "10"], "ACCOUNTING")).is_empty()
	assert_array(_config_obj("S1", ["vlans", "10"], null)).is_empty()
	assert_array(_config_obj("S1", ["vlans", "ten"], "x")).is_equal(["objectives[1].path: VLAN ids are numbers from 1 to 4094"])


func test_config_path_for_a_host() -> void:
	for key in ["hostname", "ip", "mask", "gateway", "locked"]:
		var value: Variant = true if key == "locked" else "PC-A" if key == "hostname" else "192.168.10.10" if key == "ip" or key == "gateway" else "255.255.255.0"
		assert_array(_config_obj("PC-A", [key], value)).override_failure_message(key).is_empty()
	var msg: String = "objectives[1].path: unknown config path for a host (use one of hostname, ip, mask, gateway, locked)"
	assert_array(_config_obj("PC-A", ["dns"], "x")).is_equal([msg])
	assert_array(_config_obj("PC-A", ["interfaces", "Eth0"], {})).is_equal([msg])


func test_config_equals_must_fit_what_the_path_points_at() -> void:
	assert_array(_config_obj("S1", ["interfaces", "Gi0/1", "mode"], "banana")).is_equal(['objectives[1].equals: must be "access" or "trunk" (or null)'])
	assert_array(_config_obj("S1", ["interfaces", "Fa0/1", "access_vlan"], 5000)).is_equal(["objectives[1].equals: must be a VLAN id from 1 to 4094 (or null)"])
	assert_array(_config_obj("R1", ["interfaces", "Gi0/0", "ip"], "nope")).is_equal(["objectives[1].equals: must be an IPv4 address such as 192.168.10.1 (or null)"])
	assert_array(_config_obj("R1", ["hostname"], 5)).is_equal(["objectives[1].equals: must be a single word with no spaces (or null)"])
	assert_array(_config_obj("S1", ["vlans", "10"], 5)).is_equal(["objectives[1].equals: must be a single word with no spaces (or null)"])
	assert_array(_config_obj("PC-A", ["locked"], "yes")).is_equal(["objectives[1].equals: must be true or false (or null)"])


func test_config_equals_for_a_whole_interface() -> void:
	var path: Array = ["interfaces", "Gi0/0.10"]
	assert_array(_config_obj("R1", path, {"dot1q_vlan": 10, "ip": null})).is_empty()
	assert_array(_config_obj("R1", path, "up")).is_equal(["objectives[1].equals: must be an object of interface fields (or null)"])
	assert_array(_config_obj("R1", path, {"foo": 1})).is_equal(["objectives[1].equals.foo: unknown interface field (use one of admin_up, ip, mask, dot1q_vlan)"])
	assert_array(_config_obj("R1", path, {"ip": "nope"})).is_equal(["objectives[1].equals.ip: must be an IPv4 address such as 192.168.10.1 (or null)"])
	assert_array(_config_obj("R1", ["interfaces", "Gi0/0"], {"dot1q_vlan": 10})).is_equal(["objectives[1].equals.dot1q_vlan: only subinterfaces have dot1q_vlan"])
	assert_array(_config_obj("S1", ["interfaces", "Gi0/1"], {"mode": "trunk"})).is_empty()


func test_config_objective_rejects_other_types_params() -> void:
	assert_array(_with(["objectives", 1, "from"], "PC-A")).is_equal(["objectives[1].from: unknown key"])


# --- hints ------------------------------------------------------------------------


func test_hints_are_optional() -> void:
	assert_array(_without(["hints"])).is_empty()
	assert_array(_with(["hints"], [])).is_empty()


func test_hint_shape() -> void:
	assert_array(_with(["hints"], {})).is_equal(["hints: must be an array"])
	assert_array(_with(["hints", 0], 5)).is_equal(["hints[0]: must be an object"])
	assert_array(_without(["hints", 0, "reason"])).is_equal(["hints[0].reason: required"])
	assert_array(_without(["hints", 0, "text"])).is_equal(["hints[0].text: required"])
	assert_array(_with(["hints", 0, "text"], "")).is_equal(["hints[0].text: must be a non-empty string"])
	assert_array(_with(["hints", 0, "tone"], "kind")).is_equal(["hints[0].tone: unknown key"])


func test_hint_reason_must_be_a_ping_fail_reason() -> void:
	for bad: Variant in ["BANANA", "NONE", "no_link", 5]:
		assert_array(_with(["hints", 0, "reason"], bad)).override_failure_message(str(bad)).is_equal(
			["hints[0].reason: must be a ping fail reason (%s)" % REASONS]
		)
	for reason in ["NO_IP", "NO_LINK", "ADMIN_DOWN", "VLAN_MISMATCH", "WRONG_SUBNET", "NO_GATEWAY", "NO_ROUTE", "HOST_UNREACHABLE", "ACL_DENIED"]:
		assert_array(_with(["hints"], [{"reason": reason, "text": "x"}])).override_failure_message(reason).is_empty()


func test_reason_list_matches_the_fail_reason_enum() -> void:
	var expected: Array = PingResult.FailReason.keys()
	expected.erase("NONE")
	assert_str(", ".join(PackedStringArray(expected))).is_equal(REASONS)


func test_only_one_hint_per_reason() -> void:
	assert_array(_with(["hints", 1, "reason"], "NO_LINK")).is_equal(['hints[1].reason: a second hint for "NO_LINK"'])


# --- solution ---------------------------------------------------------------------


func test_solution_shape() -> void:
	assert_array(_with(["solution"], {})).is_equal(["solution: must be an array"])
	assert_array(_with(["solution"], [])).is_equal(["solution: needs at least one step"])
	assert_array(_with(["solution", 1], 5)).is_equal(["solution[1]: must be an object"])


func test_a_step_is_either_commands_or_a_link() -> void:
	var msg: String = 'solution[1]: a step has either "device" and "commands", or "link"'
	assert_array(_with(["solution", 1], {})).is_equal([msg])
	assert_array(_with(["solution", 1, "link"], {"a": "S1:Fa0/3", "b": "PC-B:Eth0"})).is_equal([msg])


func test_solution_command_steps() -> void:
	assert_array(_with(["solution", 1, "device"], "X9")).is_equal(['solution[1].device: unknown device "X9"'])
	assert_array(_without(["solution", 1, "device"])).is_equal(['solution[1]: a step has either "device" and "commands", or "link"'])
	assert_array(_without(["solution", 1, "commands"])).is_equal(["solution[1].commands: required"])
	assert_array(_with(["solution", 1, "commands"], "enable")).is_equal(["solution[1].commands: must be an array"])
	assert_array(_with(["solution", 1, "commands"], [])).is_equal(["solution[1].commands: needs at least one command"])
	assert_array(_with(["solution", 1, "commands"], ["enable", 5])).is_equal(["solution[1].commands[1]: must be a non-empty command"])
	assert_array(_with(["solution", 1, "commands"], ["enable", "  "])).is_equal(["solution[1].commands[1]: must be a non-empty command"])
	assert_array(_with(["solution", 1, "note"], "x")).is_equal(["solution[1].note: unknown key"])


func test_solution_link_steps() -> void:
	assert_array(_with(["solution", 0, "link"], 5)).is_equal(["solution[0].link: must be an object"])
	assert_array(_with(["solution", 0, "link", "a"], "X9:Fa0/2")).is_equal(['solution[0].link.a: unknown device "X9"'])
	assert_array(_without(["solution", 0, "link", "b"])).is_equal(["solution[0].link.b: required"])
	assert_array(_with(["solution", 0, "extra"], 1)).is_equal(["solution[0].extra: unknown key"])
	assert_array(_with(["solution", 0, "link", "speed"], 1)).is_equal(["solution[0].link.speed: unknown key"])


func test_the_solution_cannot_cable_a_reserved_port() -> void:
	assert_array(_with(["solution", 0, "link", "a"], "R1:Gi0/1")).is_equal(["solution[0].link.a: R1:GigabitEthernet0/1 is reserved; the player cannot cable it"])


func test_the_solution_cannot_cable_a_port_that_is_already_cabled() -> void:
	assert_array(_with(["solution", 0, "link", "a"], "S1:Fa0/1")).is_equal(["solution[0].link.a: S1:FastEthernet0/1 is already cabled"])


func test_the_solution_cannot_cable_a_port_twice() -> void:
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["spare_cables"] = 2
		d["solution"].append({"link": {"a": "S1:Fa0/2", "b": "PC-A:Eth0"}})
	)
	assert_array(errors).is_equal(["solution[3].link.a: S1:FastEthernet0/2 is already cabled", "solution[3].link.b: PC-A:Ethernet0 is already cabled"])


func test_the_solution_needs_no_more_cables_than_spare_cables() -> void:
	assert_array(_with(["spare_cables"], 0)).is_equal(["solution: plugs in 1 cable(s) but spare_cables is 0"])
	var errors: Array[String] = _edit(func(d: Dictionary) -> void:
		d["spare_cables"] = 2
		d["solution"].append({"link": {"a": "S1:Fa0/3", "b": "R1:Gi0/0"}})
	)
	assert_array(errors).is_equal(["solution[3].link.b: R1:GigabitEthernet0/0 is already cabled"])
	assert_array(_edit(func(d: Dictionary) -> void:
		d["spare_cables"] = 2
		d["solution"].append({"link": {"a": "S1:Fa0/3", "b": "R1:Gi0/0.10"}})
	)).is_equal(["solution[3].link.b: a subinterface has no socket; cables use physical ports"])


func test_a_bad_spare_cables_does_not_also_fail_the_cable_count() -> void:
	assert_array(_with(["spare_cables"], -1)).is_equal(["spare_cables: must be an integer of at least 0"])
	assert_array(_with(["spare_cables"], "many")).is_equal(["spare_cables: must be an integer of at least 0"])
