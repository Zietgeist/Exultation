extends Node3D
## Something you can gather (press G when close): ore, herbs, Treesilver or Cliff Orchid.
## Set `type`, `quality` and `reach` before adding it to the scene.

var type = "ore"	# "ore", "herb", "treesilver", "orchid"
var quality = 1
var reach = 0.0		# extra gather distance (for nodes sitting on a hill or trunk)

var _label: Label3D


func _ready():
	add_to_group("resource_node")
	var mi = MeshInstance3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = GameState.RESOURCE_INFO[type].color
	match type:
		"ore":
			var m = BoxMesh.new()
			m.size = Vector3(1.2, 0.9, 1.2)
			mi.mesh = m
			mi.position.y = 0.45
			mi.rotation.y = randf() * TAU
		"herb":
			var m = SphereMesh.new()
			m.radius = 0.45
			m.height = 0.6
			mi.mesh = m
			mi.position.y = 0.3
		"treesilver":
			var m = BoxMesh.new()
			m.size = Vector3(0.35, 0.8, 0.35)
			mi.mesh = m
			mi.position.y = 1.0
			mat.emission_enabled = true
			mat.emission = Color(0.6, 0.7, 0.8)
		"orchid":
			var m = SphereMesh.new()
			m.radius = 0.3
			m.height = 0.5
			mi.mesh = m
			mi.position.y = 0.25
			mat.emission_enabled = true
			mat.emission = Color(0.6, 0.2, 0.5)
	mi.material_override = mat
	add_child(mi)

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
