extends "res://portal.gd"
## The Return ring in a Real Place. LOCKED until the place is cleared, so walking through it by
## accident doesn't send you home mid-fight. To leave early on purpose: stand in it and press G.
## (It's in the "npc" group so G finds it, like a shopkeeper.)

var reach = 1.0
var locked := true


func _init():
	label_text = "Return\n(locked: clear the place)"
	active = false


func _ready():
	super._ready()
	add_to_group("npc")


func unlock():
	locked = false
	active = true
	label_text = "Return"
	refresh()


func horizontal_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func set_highlight(on: bool):
	if locked:
		label_text = "G: leave early (go Home)" if on else "Return\n(locked: clear the place)"
		refresh()


## G: leave now (only needed while locked; once cleared, just walk in).
func talk():
	Net.go.call_deferred(target_scene, travel_key, target_position, travel_info)
