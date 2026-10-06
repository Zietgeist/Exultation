extends Node
## The one game scene. Holds the screen (showing the local player's zone), the parked zones
## running in the background, and the HUD. Zones.gd does the work.

@onready var screen: SubViewportContainer = $Screen
@onready var parked: Node = $Parked


func _ready():
	Zones.world_ready(self)


## Show this zone on screen (only one at a time); park the one that was showing.
func show_zone(z):
	for v in screen.get_children():
		if v != z:
			park(v)
	if z.get_parent() != screen:
		if z.get_parent():
			z.get_parent().remove_child(z)
		screen.add_child(z)
	z.render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Keep a zone running without drawing it.
func park(z):
	if z.get_parent() == parked:
		return
	if z.get_parent():
		z.get_parent().remove_child(z)
	parked.add_child(z)
	z.size = Vector2i(2, 2)
	z.render_target_update_mode = SubViewport.UPDATE_DISABLED
