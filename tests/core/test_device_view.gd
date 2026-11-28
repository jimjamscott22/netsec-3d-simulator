class_name TestDeviceView
extends GdUnitTestSuite


func test_device_view_is_a_copy() -> void:
	var sim := NetworkSim.new(1)
	sim.add_device(DeviceModels.build("router_2port", "R1"))
	var view: DeviceView = sim.device_view("R1")
	(sim.get_device("R1") as Router).interface("g0/0").admin_up = true
	assert_bool(view.interface("Gi0/0")["admin_up"]).is_false()
	assert_bool(sim.device_view("R1").interface("Gi0/0")["admin_up"]).is_true()
	var d: Dictionary = view.interface("Gi0/0")
	d["ip"] = "x"
	assert_str(view.interface("Gi0/0")["ip"]).is_equal("")
	assert_object(sim.device_view("nope")).is_null()


func test_view_of_a_switch_trunk_port() -> void:
	var sim := NetworkSim.new()
	var s1 := Switch.new("S1")
	s1.add_interface(Interface.new("S1", "g0/1", true))
	s1.add_vlan(10, "SALES")
	var p: Interface = s1.interface("g0/1")
	p.mode = Interface.Mode.TRUNK
	p.trunk_allowed_all = false
	p.trunk_allowed = [10, 20]
	sim.add_device(s1)
	var v: DeviceView = sim.device_view("S1")
	assert_int(v.kind()).is_equal(Device.Kind.SWITCH)
	assert_array(v.interface_names()).is_equal(["GigabitEthernet0/1"])
	var d: Dictionary = v.interface("gi0/1")
	assert_str(d["name"]).is_equal("GigabitEthernet0/1")
	assert_str(d["short_name"]).is_equal("Gi0/1")
	assert_int(d["mode"]).is_equal(Interface.Mode.TRUNK)
	assert_bool(d["trunk_allowed_all"]).is_false()
	assert_array(d["trunk_allowed"]).is_equal([10, 20])
	assert_bool(d["oper_up"]).is_false()
	assert_object(d["peer"]).is_null()
	assert_dict(v.vlans()).is_equal({1: "default", 10: "SALES"})
	assert_dict(v.interface("g9/9")).is_empty()


func test_view_of_a_router_subinterface() -> void:
	var sim := NetworkSim.new()
	var r1 := Router.new("R1")
	r1.add_interface(Interface.new("R1", "g0/0", true))
	var sub: Interface = r1.add_subinterface("g0/0.10")
	sub.dot1q_vlan = 10
	sub.ip = "192.168.10.1"
	sub.mask = "255.255.255.0"
	r1.static_routes.append({"network": "10.0.0.0", "mask": "255.0.0.0", "next_hop": "192.168.10.2"})
	sim.add_device(r1)
	var v: DeviceView = sim.device_view("R1")
	var d: Dictionary = v.interface("Gi0/0.10")
	assert_str(d["parent"]).is_equal("GigabitEthernet0/0")
	assert_int(d["dot1q_vlan"]).is_equal(10)
	assert_str(d["ip"]).is_equal("192.168.10.1")
	assert_object(d["peer"]).is_null()
	assert_int(v.static_routes().size()).is_equal(1)
	assert_str(v.static_routes()[0]["next_hop"]).is_equal("192.168.10.2")
	# A returned route list is a copy too.
	v.static_routes().clear()
	assert_int(v.static_routes().size()).is_equal(1)
	assert_dict(v.vlans()).is_empty()


func test_view_of_a_host() -> void:
	var sim := NetworkSim.new()
	var pc := DeviceModels.build("pc", "PC-A") as Host
	pc.gateway = "192.168.10.1"
	pc.locked = true
	sim.add_device(pc)
	var v: DeviceView = sim.device_view("PC-A")
	assert_str(v.hostname()).is_equal("PC-A")
	assert_str(v.gateway()).is_equal("192.168.10.1")
	assert_bool(v.locked()).is_true()
	assert_array(v.static_routes()).is_empty()


func test_view_peer_is_a_string_when_cabled() -> void:
	var sim := NetworkSim.new(1)
	sim.add_device(DeviceModels.build("pc", "PC-A"))
	sim.add_device(DeviceModels.build("pc", "PC-B"))
	sim.connect_link("PC-A:eth0", "PC-B:eth0")
	var d: Dictionary = sim.device_view("PC-A").interface("eth0")
	assert_str(d["peer"]).is_equal("PC-B:Ethernet0")
	assert_bool(d["oper_up"]).is_true()


func test_a_server_view_shows_services_but_no_hidden_metadata() -> void:
	var sim := NetworkSim.new()
	var web := Server.new("WEB1")
	web.services = [{"id": "http", "port": 80, "root": "/var/www", "secret": "x"}]
	sim.add_device(web)
	sim.add_source_file("WEB1", "/var/www/login.php", "a\nb\n")
	var v := Vuln.new("sqli_login", "/var/www/login.php", 1, 1)
	v.accept.assign(["pattern"])
	v.accept_fixtures.assign(["fixture"])
	v.exploit = {"payload": "' OR '1'='1"}
	sim.add_vuln("WEB1", v)
	var view: DeviceView = sim.device_view("WEB1")
	assert_int(view.kind()).is_equal(Device.Kind.SERVER)
	assert_array(view.services()).is_equal([{"id": "http", "port": 80, "root": "/var/www"}])
	# A copy: changing it touches neither the view nor the server.
	view.services()[0]["port"] = 8080
	assert_int(view.services()[0]["port"]).is_equal(80)
	# No files, vulns, accept patterns, fixtures or exploit anywhere in the view.
	var props: Array = view.get_property_list().map(func(p: Dictionary) -> String: return p["name"])
	for hidden: String in ["files", "_files", "vulns", "_vulns", "accept", "exploit"]:
		assert_bool(props.has(hidden)).is_false()
	var dump: String = ""
	for p: Dictionary in view.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			dump += str(view.get(p["name"]))
	for secret: String in ["login.php", "sqli_login", "pattern", "fixture", "OR '1'", "secret"]:
		assert_str(dump).not_contains(secret)


func test_non_servers_have_no_services() -> void:
	var sim := NetworkSim.new()
	sim.add_device(Host.new("PC-1"))
	assert_array(sim.device_view("PC-1").services()).is_empty()
