class_name Device
extends RefCounted

# await get_tree() Timer Input. are fine inside comments
var note: String = "Timer # not a comment"
var wait_state: int = 0   # await


class Inner extends RefCounted:
	var x: int = 0


class Inner2 extends Inner:
	var y: int = 0
