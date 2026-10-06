extends StaticBody3D
## A slow patch on the ground. Walking through it slows you (and enemies) down.
## Two looks: mud (loose patches) and water (rivers and shallows, colored by the world skin).

const SLOW_FACTOR = 0.2		# move at 20% speed while inside
const HIDDEN_CHANCE = 0.0	# all slow patches visible (hidden ones were tried and felt annoying)

var size := Vector2(4.0, 4.0)	# set before adding to the scene (x = width, y = depth)
var water := false
var hidden = false


func _ready():
	add_to_group("ditch")
	# Walk-through: no collision, it just slows
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.disabled = true

	var mesh = BoxMesh.new()
	mesh.size = Vector3(size.x, 0.04, size.y)
	$MeshInstance3D.mesh = mesh
	if water:
		$MeshInstance3D.material_override = SkinManager.material("water", Color(0.18, 0.43, 0.69))
		$MeshInstance3D.visibility_range_end = 0.0	# rivers are seen from far away
	else:
		$MeshInstance3D.material_override = SkinManager.material("ditch", Color(0.12, 0.16, 0.22))
	set_hidden(randf() < HIDDEN_CHANCE)

	# Sit just on top of the floor tiles so it's visible (the mesh is lifted, so moving the patch keeps it right)
	$MeshInstance3D.position.y = 0.17 if not water else 0.18


## Is this world position inside the patch?
func contains(world_pos: Vector3) -> bool:
	var local = to_local(world_pos)
	return abs(local.x) <= size.x / 2.0 and abs(local.z) <= size.y / 2.0


func set_hidden(value: bool):
	hidden = value
	$MeshInstance3D.visible = not hidden


## Stepping into a hidden patch shows it from then on.
func reveal():
	if hidden:
		set_hidden(false)
		print("Hidden slow patch found!")


func get_slow_factor():
	return SLOW_FACTOR
