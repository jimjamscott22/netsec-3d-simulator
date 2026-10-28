class_name TestCliFormatters
extends GdUnitTestSuite
## Golden tests: these strings are the contract for what the player sees.
## Change a formatter on purpose, update the golden on purpose.


func _g(lines: Array) -> String:
	return "\n".join(PackedStringArray(lines))


func _lines(text: String) -> PackedStringArray:
	return text.split("\n")


# --- ping -------------------------------------------------------------------


func test_ping_success_golden() -> void:
	assert_str(CliFormatters.ping_output("192.168.10.10", PingResult.ok(["R1", "PC-A"]))).is_equal(_g([
		"Type escape sequence to abort.",
		"Sending 5, 100-byte ICMP Echos to 192.168.10.10, timeout is 2 seconds:",
		"!!!!!",
		"Success rate is 100 percent (5/5), round-trip min/avg/max = 1/2/4 ms",
	]))


func test_ping_round_trip_scales_with_the_link_count() -> void:
	var two: String = CliFormatters.ping_output("10.0.0.9", PingResult.ok(["R1", "R2", "PC-B"]))
	assert_str(two).ends_with("round-trip min/avg/max = 2/4/8 ms")
	var three: String = CliFormatters.ping_output("10.0.0.9", PingResult.ok(["R1", "R2", "R3", "PC-B"]))
	assert_str(three).ends_with("round-trip min/avg/max = 3/6/12 ms")


func test_ping_to_the_device_itself_still_reports_one_link_of_time() -> void:
	assert_str(CliFormatters.ping_output("10.0.0.1", PingResult.ok(["R1"]))).ends_with("min/avg/max = 1/2/4 ms")


func test_ping_failure_golden() -> void:
	assert_str(CliFormatters.ping_output("10.9.9.9", PingResult.fail(PingResult.FailReason.NO_ROUTE, "R1", ["R1"]))).is_equal(_g([
		"Type escape sequence to abort.",
		"Sending 5, 100-byte ICMP Echos to 10.9.9.9, timeout is 2 seconds:",
		".....",
		"Success rate is 0 percent (0/5)",
	]))


func test_ping_failure_text_never_reveals_the_reason() -> void:
	var want: String = CliFormatters.ping_output("10.9.9.9", PingResult.fail(PingResult.FailReason.NO_ROUTE, "R1"))
	for reason in PingResult.FailReason.values():
		if reason == PingResult.FailReason.NONE:
			continue
		var got: String = CliFormatters.ping_output("10.9.9.9", PingResult.fail(reason, "R1", ["R1"]))
		assert_str(got).override_failure_message(PingResult.reason_name(reason)).is_equal(want)


# --- show ip interface brief ------------------------------------------------


func test_ip_brief_router_golden() -> void:
	var t := TopoBuilder.stick()
	assert_str(CliFormatters.ip_interface_brief(t.sim, "R1")).is_equal(_g([
		"Interface                  IP-Address      OK? Method Status                Protocol",
		"GigabitEthernet0/0         unassigned      YES unset  up                    up",
		"GigabitEthernet0/0.10      192.168.10.1    YES manual up                    up",
		"GigabitEthernet0/0.20      192.168.20.1    YES manual up                    up",
		"GigabitEthernet0/1         unassigned      YES unset  administratively down down",
	]))


func test_ip_brief_shutting_the_parent_takes_the_subinterfaces_with_it() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_admin_up("R1:Gi0/0", false)
	assert_str(CliFormatters.ip_interface_brief(t.sim, "R1")).is_equal(_g([
		"Interface                  IP-Address      OK? Method Status                Protocol",
		"GigabitEthernet0/0         unassigned      YES unset  administratively down down",
		"GigabitEthernet0/0.10      192.168.10.1    YES manual administratively down down",
		"GigabitEthernet0/0.20      192.168.20.1    YES manual administratively down down",
		"GigabitEthernet0/1         unassigned      YES unset  administratively down down",
	]))


func test_ip_brief_unplugged_cable_reads_down_down() -> void:
	var t := TopoBuilder.stick()
	t.sim.disconnect_link("R1:Gi0/0")
	assert_str(CliFormatters.ip_interface_brief(t.sim, "R1")).is_equal(_g([
		"Interface                  IP-Address      OK? Method Status                Protocol",
		"GigabitEthernet0/0         unassigned      YES unset  down                  down",
		"GigabitEthernet0/0.10      192.168.10.1    YES manual down                  down",
		"GigabitEthernet0/0.20      192.168.20.1    YES manual down                  down",
		"GigabitEthernet0/1         unassigned      YES unset  administratively down down",
	]))


func test_ip_brief_peer_shut_down_reads_down_down() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_admin_up("S1:Gi0/1", false)
	var rows: PackedStringArray = _lines(CliFormatters.ip_interface_brief(t.sim, "R1"))
	assert_str(rows[1]).is_equal("GigabitEthernet0/0         unassigned      YES unset  down                  down")


func test_ip_brief_after_ip_address_changes() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_ip_address("R1:Gi0/1", "10.0.0.1", "255.255.255.252")
	t.sim.clear_ip_address("R1:Gi0/0.20")
	var rows: PackedStringArray = _lines(CliFormatters.ip_interface_brief(t.sim, "R1"))
	assert_str(rows[3]).is_equal("GigabitEthernet0/0.20      unassigned      YES unset  up                    up")
	assert_str(rows[4]).is_equal("GigabitEthernet0/1         10.0.0.1        YES manual administratively down down")


func test_ip_brief_switch_lists_every_port_in_socket_order() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_admin_up("S1:Fa0/2", false)
	var rows: PackedStringArray = _lines(CliFormatters.ip_interface_brief(t.sim, "S1"))
	assert_int(rows.size()).is_equal(27)
	assert_array(rows.slice(0, 4)).is_equal([
		"Interface                  IP-Address      OK? Method Status                Protocol",
		"FastEthernet0/1            unassigned      YES unset  up                    up",
		"FastEthernet0/2            unassigned      YES unset  administratively down down",
		"FastEthernet0/3            unassigned      YES unset  down                  down",
	])
	assert_array(rows.slice(-2)).is_equal([
		"GigabitEthernet0/1         unassigned      YES unset  up                    up",
		"GigabitEthernet0/2         unassigned      YES unset  down                  down",
	])


func test_ip_brief_columns_stay_aligned() -> void:
	var t := TopoBuilder.stick()
	for row in _lines(CliFormatters.ip_interface_brief(t.sim, "R1")):
		assert_str(row.substr(27, 15).strip_edges()).is_not_empty()
		assert_str(row.substr(26, 1)).is_equal(" ")


func test_ip_brief_unknown_device_is_empty() -> void:
	assert_str(CliFormatters.ip_interface_brief(TopoBuilder.stick().sim, "nope")).is_empty()


# --- show vlan brief --------------------------------------------------------


func test_vlan_brief_golden() -> void:
	var t := TopoBuilder.stick()
	assert_str(CliFormatters.vlan_brief(t.sim.get_device("S1"))).is_equal(_g([
		"VLAN Name                             Status    Ports",
		"---- -------------------------------- --------- -------------------------------",
		"1    default                          active    Fa0/3, Fa0/4, Fa0/5, Fa0/6",
		"                                                Fa0/7, Fa0/8, Fa0/9, Fa0/10",
		"                                                Fa0/11, Fa0/12, Fa0/13, Fa0/14",
		"                                                Fa0/15, Fa0/16, Fa0/17, Fa0/18",
		"                                                Fa0/19, Fa0/20, Fa0/21, Fa0/22",
		"                                                Fa0/23, Fa0/24, Gi0/2",
		"10   V10                              active    Fa0/1",
		"20   V20                              active    Fa0/2",
		"1002 fddi-default                     act/unsup",
		"1003 token-ring-default               act/unsup",
		"1004 fddinet-default                  act/unsup",
		"1005 trnet-default                    act/unsup",
	]))


func test_vlan_brief_follows_port_and_vlan_changes() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_access_vlan("S1:Fa0/3", 10)
	t.sim.create_vlan("S1", 30)
	t.sim.set_vlan_name("S1", 30, "Guests")
	var rows: PackedStringArray = _lines(CliFormatters.vlan_brief(t.sim.get_device("S1")))
	assert_str(rows[2]).is_equal("1    default                          active    Fa0/4, Fa0/5, Fa0/6, Fa0/7")
	assert_str(rows[8]).is_equal("10   V10                              active    Fa0/1, Fa0/3")
	assert_str(rows[10]).is_equal("30   Guests                           active")


func test_vlan_brief_trunk_ports_are_not_listed() -> void:
	var t := TopoBuilder.stick()
	assert_str(CliFormatters.vlan_brief(t.sim.get_device("S1"))).not_contains("Gi0/1")
	t.sim.set_switchport_mode("S1:Fa0/1", Interface.Mode.TRUNK)
	assert_str(CliFormatters.vlan_brief(t.sim.get_device("S1"))).not_contains("Fa0/1,")


func test_vlan_brief_port_in_a_missing_vlan_is_listed_nowhere() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_access_vlan("S1:Fa0/3", 99)
	var text: String = CliFormatters.vlan_brief(t.sim.get_device("S1"))
	assert_str(text).not_contains("Fa0/3,").not_contains("99")
	assert_str(_lines(text)[2]).is_equal("1    default                          active    Fa0/4, Fa0/5, Fa0/6, Fa0/7")


func test_vlan_brief_shut_down_port_is_still_listed() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_admin_up("S1:Fa0/1", false)
	assert_str(CliFormatters.vlan_brief(t.sim.get_device("S1"))).contains("10   V10                              active    Fa0/1")


func test_vlan_brief_long_name_is_cut_at_32_characters() -> void:
	var t := TopoBuilder.stick()
	t.sim.create_vlan("S1", 40)
	t.sim.set_vlan_name("S1", 40, "A".repeat(40))
	assert_str(CliFormatters.vlan_brief(t.sim.get_device("S1"))).contains("40   " + "A".repeat(32) + " active")


func test_vlan_brief_a_switch_vlan_replaces_the_legacy_row() -> void:
	var t := TopoBuilder.stick()
	t.sim.create_vlan("S1", 1003)
	t.sim.set_vlan_name("S1", 1003, "Mine")
	var rows: PackedStringArray = _lines(CliFormatters.vlan_brief(t.sim.get_device("S1")))
	assert_str(rows[11]).is_equal("1003 Mine                             active")
	assert_int(rows.size()).is_equal(14)


# --- show running-config ----------------------------------------------------


func test_running_config_router_golden() -> void:
	var t := TopoBuilder.stick()
	assert_str(CliFormatters.running_config(t.sim.get_device("R1"))).is_equal(_g([
		"Building configuration...",
		"",
		"Current configuration : 315 bytes",
		"!",
		"hostname R1",
		"!",
		"interface GigabitEthernet0/0",
		" no ip address",
		"!",
		"interface GigabitEthernet0/0.10",
		" encapsulation dot1Q 10",
		" ip address 192.168.10.1 255.255.255.0",
		"!",
		"interface GigabitEthernet0/0.20",
		" encapsulation dot1Q 20",
		" ip address 192.168.20.1 255.255.255.0",
		"!",
		"interface GigabitEthernet0/1",
		" no ip address",
		" shutdown",
		"!",
		"end",
	]))


func test_running_config_router_after_config_changes() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_hostname("R1", "EDGE")
	t.sim.set_admin_up("R1:Gi0/1", true)
	t.sim.set_admin_up("R1:Gi0/0", false)
	t.sim.set_ip_address("R1:Gi0/1", "10.0.0.1", "255.255.255.252")
	t.sim.clear_ip_address("R1:Gi0/0.20")
	t.sim.set_dot1q_vlan("R1:Gi0/0.20", 25)
	var rows: PackedStringArray = _lines(CliFormatters.running_config(t.sim.get_device("R1")))
	assert_array(rows.slice(3)).is_equal([
		"!",
		"hostname EDGE",
		"!",
		"interface GigabitEthernet0/0",
		" no ip address",
		" shutdown",
		"!",
		"interface GigabitEthernet0/0.10",
		" encapsulation dot1Q 10",
		" ip address 192.168.10.1 255.255.255.0",
		"!",
		"interface GigabitEthernet0/0.20",
		" encapsulation dot1Q 25",
		" no ip address",
		"!",
		"interface GigabitEthernet0/1",
		" ip address 10.0.0.1 255.255.255.252",
		"!",
		"end",
	])


func test_running_config_subinterface_without_a_tag_prints_no_encapsulation() -> void:
	var t := TopoBuilder.stick()
	t.sim.create_subinterface("R1", "g0/1.5")
	assert_array(_lines(CliFormatters.running_config(t.sim.get_device("R1"))).slice(-6)).is_equal([
		" shutdown",
		"!",
		"interface GigabitEthernet0/1.5",
		" no ip address",
		"!",
		"end",
	])


func test_running_config_switch_head_and_tail() -> void:
	var t := TopoBuilder.stick()
	var rows: PackedStringArray = _lines(CliFormatters.running_config(t.sim.get_device("S1")))
	assert_array(rows.slice(3, 20)).is_equal([
		"!",
		"hostname S1",
		"!",
		"vlan 10",
		" name V10",
		"!",
		"vlan 20",
		" name V20",
		"!",
		"interface FastEthernet0/1",
		" switchport access vlan 10",
		" switchport mode access",
		"!",
		"interface FastEthernet0/2",
		" switchport access vlan 20",
		" switchport mode access",
		"!",
	])
	assert_array(rows.slice(-8)).is_equal([
		"interface FastEthernet0/24",
		"!",
		"interface GigabitEthernet0/1",
		" switchport mode trunk",
		"!",
		"interface GigabitEthernet0/2",
		"!",
		"end",
	])


func test_running_config_switch_after_config_changes() -> void:
	var t := TopoBuilder.stick()
	t.sim.set_access_vlan("S1:Fa0/3", 30)
	t.sim.set_admin_up("S1:Fa0/4", false)
	t.sim.set_switchport_mode("S1:Fa0/2", Interface.Mode.TRUNK)
	t.sim.create_vlan("S1", 30)
	var text: String = CliFormatters.running_config(t.sim.get_device("S1"))
	assert_str(text).contains(_g(["vlan 30", "!", "interface FastEthernet0/1"]))
	assert_str(text).contains(_g(["interface FastEthernet0/2", " switchport mode trunk", "!"]))
	assert_str(text).contains(_g(["interface FastEthernet0/3", " switchport access vlan 30", " switchport mode access", "!"]))
	assert_str(text).contains(_g(["interface FastEthernet0/4", " shutdown", "!"]))


func test_running_config_default_vlan_name_is_not_printed() -> void:
	var t := TopoBuilder.stick()
	t.sim.create_vlan("S1", 30)
	assert_str(CliFormatters.running_config(t.sim.get_device("S1"))).contains(_g(["vlan 30", "!", "interface"]))


func test_running_config_trunk_allowed_list() -> void:
	var t := TopoBuilder.stick()
	t.trunk("S1:Gi0/1", [20, 10] as Array[int])
	assert_str(CliFormatters.running_config(t.sim.get_device("S1"))).contains(
		_g(["interface GigabitEthernet0/1", " switchport trunk allowed vlan 10,20", " switchport mode trunk", "!"])
	)


func test_running_config_static_routes() -> void:
	var t := TopoBuilder.stick()
	(t.sim.get_device("R1") as Router).static_routes.append({"network": "10.9.0.0", "mask": "255.255.0.0", "next_hop": "192.168.10.2"})
	assert_array(_lines(CliFormatters.running_config(t.sim.get_device("R1"))).slice(-4)).is_equal([
		"!",
		"ip route 10.9.0.0 255.255.0.0 192.168.10.2",
		"!",
		"end",
	])


func test_running_config_enable_secret_is_hashed_never_plain() -> void:
	var t := TopoBuilder.stick()
	t.sim.get_device("R1").enable_secret = "cisco123"
	var text: String = CliFormatters.running_config(t.sim.get_device("R1"))
	assert_str(text).not_contains("cisco123")
	var rows: PackedStringArray = _lines(text)
	assert_str(rows[6]).is_equal("enable secret 5 " + CliFormatters.secret_hash("cisco123"))
	assert_str(rows[7]).is_equal("!")
	assert_str(CliFormatters.secret_hash("cisco123")).is_equal(CliFormatters.secret_hash("cisco123"))
	assert_str(CliFormatters.secret_hash("cisco123")).is_not_equal(CliFormatters.secret_hash("cisco124"))


func test_secret_hash_looks_like_a_type_5_hash() -> void:
	var h: String = CliFormatters.secret_hash("x")
	assert_bool(h.begins_with("$1$")).is_true()
	assert_int(h.length()).is_equal(3 + 4 + 1 + 22)
	assert_str(h.substr(7, 1)).is_equal("$")


func test_running_config_has_no_enable_secret_line_when_unset() -> void:
	var t := TopoBuilder.stick()
	assert_str(CliFormatters.running_config(t.sim.get_device("R1"))).not_contains("enable secret")


func test_running_config_byte_count_matches_the_text() -> void:
	var t := TopoBuilder.stick()
	for id in ["R1", "S1"]:
		var text: String = CliFormatters.running_config(t.sim.get_device(id))
		var header_end: int = text.find("\n!")
		var declared: int = text.get_slice("\n", 2).trim_prefix("Current configuration : ").trim_suffix(" bytes").to_int()
		assert_int(declared).is_equal(text.substr(header_end + 1).to_utf8_buffer().size())


func test_ordered_interfaces_put_subinterfaces_after_their_parent_by_tag() -> void:
	var t := TopoBuilder.stick()
	t.sim.create_subinterface("R1", "g0/0.5")
	var names: Array[String] = []
	for i in CliFormatters.ordered_interfaces(t.sim.get_device("R1")):
		names.append(i.full_name)
	assert_array(names).is_equal([
		"GigabitEthernet0/0",
		"GigabitEthernet0/0.5",
		"GigabitEthernet0/0.10",
		"GigabitEthernet0/0.20",
		"GigabitEthernet0/1",
	])
