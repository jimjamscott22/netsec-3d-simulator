class_name L2Endpoint
extends RefCounted
## A non-switch port reached by L2 flooding, and the tag the frame arrived with.

var port: String
## 0 = untagged.
var tag: int


func _init(p_port: String, p_tag: int) -> void:
	port = p_port
	tag = p_tag
