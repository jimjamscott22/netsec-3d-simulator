class_name ServerFiles
extends RefCounted
## What the server shell can see of a server's files, as one tree rooted at `/`
## built from the file paths. Directories exist only because a file lives under
## them. Today the files are the server's log files; M3 adds its source files
## here, so `ls`, `cat`, `grep` and `tail` need no change when it does.
##
## Every function takes a path as typed: it is normalised first, so `var/log/`,
## `/var//log` and `/var/log` are one directory.


## "/" plus the non-empty parts: `var//log/` -> `/var/log`, "" -> `/`.
static func normalize(path: String) -> String:
	return "/" + "/".join(path.split("/", false))


## Every file path on the device, in declaration order.
static func paths(sim: NetworkSim, device_id: String) -> Array[String]:
	return sim.log_paths(device_id)


static func is_file(sim: NetworkSim, device_id: String, path: String) -> bool:
	return paths(sim, device_id).has(normalize(path))


## The root always exists; any other directory exists when a file is under it.
static func is_dir(sim: NetworkSim, device_id: String, path: String) -> bool:
	var dir: String = normalize(path)
	if dir == "/":
		return true
	for p in paths(sim, device_id):
		if p.begins_with(dir + "/"):
			return true
	return false


## The names directly inside directory `path`, sorted. A subdirectory carries a
## trailing `/`. Empty for a file or a path that does not exist.
static func children(sim: NetworkSim, device_id: String, path: String) -> Array[String]:
	var dir: String = normalize(path)
	var prefix: String = "/" if dir == "/" else dir + "/"
	var seen: Dictionary = {}
	for p in paths(sim, device_id):
		if not p.begins_with(prefix):
			continue
		var rest: String = p.substr(prefix.length())
		var slash: int = rest.find("/")
		seen[rest if slash == -1 else rest.substr(0, slash) + "/"] = true
	var out: Array[String] = []
	out.assign(seen.keys())
	out.sort()
	return out


## A file's lines in order; empty for anything that is not a file.
static func lines(sim: NetworkSim, device_id: String, path: String) -> Array[LogLine]:
	return sim.query_logs(device_id, normalize(path), null)
