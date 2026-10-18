extends "res://portal.gd"
## The "Real Place" ring at Home: walk in and a window asks for an address (real_place_ui.gd).
## It doesn't travel by itself; the window does once the map is ready.

var _ui = null


func _init():
	label_text = "Real Place"
	color = Color(0.3, 0.9, 1.0)


func _on_body_entered(body: Node):
	if not active or body != Zones.player:
		return
	if _ui and is_instance_valid(_ui):
		return
	_ui = load("res://real_place_ui.gd").new()
	_ui.back_pos = global_position + Vector3(0, 1, 4)	# come back just in front of the ring
	get_tree().root.add_child(_ui)	# on the main screen (typing works there)
