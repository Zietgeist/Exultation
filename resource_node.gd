extends Node3D
## Something you can gather (press G when close): ore, herbs, Treesilver or Cliff Orchid.
## Set `type`, `quality` and `reach` before adding it to the scene.

var type = "ore"	# "ore", "herb", "treesilver", "orchid"
var quality = 1
var reach = 0.0		# extra gather distance (for nodes sitting on a hill or trunk)

var _label: Label3D


func _ready():
	add_to_group("resource_node")
	add_child(preload("res://props.gd").node(SkinManager.props_style(), type))	# looks come from the world skin

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.8
	_label.font_size = 36
	_label.pixel_size = 0.012	# readable from the zoomed-out camera
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.text = "G: " + GameState.resource_name(type, quality)
	_label.modulate = GameState.RESOURCE_INFO[type].color.lightened(0.4)
	_label.visible = false
	add_child(_label)


## The player turns this on for the one node that G would gather right now.
func set_highlight(on: bool):
	_label.visible = on


func horizontal_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()
