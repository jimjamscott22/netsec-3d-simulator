class_name Server
extends Host
## Extras stay empty until M3 fills them.

var services: Array = []
var files: Dictionary = {}
var vulns: Array = []


func kind() -> Kind:
	return Kind.SERVER
