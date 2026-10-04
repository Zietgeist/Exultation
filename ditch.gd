extends StaticBody3D
## A slow patch: a dark sunken area on the ground. Walking through it slows you (and enemies) down.

const SLOW_FACTOR = 0.2		# move at 20% speed while inside (was meant to be 40% before)
const SIZE = 4.0
const HIDDEN_CHANCE = 0.0	# all slow patches visible (hidden ones were tried and felt annoying)

var hidden = false


func _ready():
	add_to_group("ditch")
	# Walk-through: no collision, it just slows
	collision_layer = 0
	collision_mask = 0
	$CollisionShape3D.disabled = true

	# Each ditch gets its own mesh (they used to share one)
	var mesh = BoxMesh.new()
	mesh.size = Vector3(SIZE, 0.04, SIZE)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.16, 0.22)
	mesh.surface_set_material(0, mat)
	$MeshInstance3D.mesh = mesh
	set_hidden(randf() < HIDDEN_CHANCE)

	# Sit just on top of the floor tiles so it's visible
	position.y = 0.17


## Is this world position inside the patch?
func contains(world_pos: Vector3) -> bool:
	var local = to_local(world_pos)
	return abs(local.x) <= SIZE / 2.0 and abs(local.z) <= SIZE / 2.0


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
