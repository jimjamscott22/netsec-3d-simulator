class_name Device
extends RefCounted

# await get_tree() Timer Input. are fine inside comments
var note: String = "Timer # not a comment"
var wait_state: int = 0   # await


class Inner extends RefCounted:
	var x: int = 0


class Inner2 extends Inner:
	var y: int = 0


## Prose in a multiline string must never trip the check:
const DOC := """
First line.
We never await anything, never call get_tree(), never use a Timer,
and never preload("res://ui/panel.tscn") or Input.is_key_pressed.
"""
const ONE_LINE := """await get_tree() inside one line"""
const SINGLE := '''
randf() in single-quote triple string
'''
