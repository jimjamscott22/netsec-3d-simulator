class_name Server
extends Host
## A host with services, source files and vulns (M3). Files and vulns are hidden
## server metadata: views expose only `services`, and source text goes out
## through NetworkSim.read_file.

## `{id, port, root}` entries.
var services: Array = []
## Path -> source file.
var files: Dictionary[String, SourceFile] = {}
## In declaration order.
var vulns: Array[Vuln] = []


func kind() -> Kind:
	return Kind.SERVER


## The vuln with this id, or null.
func vuln(vuln_id: String) -> Vuln:
	for v in vulns:
		if v.id == vuln_id:
			return v
	return null
