extends StaticBody3D
## Waist-high wall (fences, ruined walls). Blocks movement. Color comes from the world skin.

const DAMAGE_REDUCTION = 0.5
var length := -1.0	# set before adding to the scene; below 0 = random


func _ready():
	if length < 0.0:
		length = randf_range(5.0, 11.0)
	$MeshInstance3D.mesh = $MeshInstance3D.mesh.duplicate()
	$CollisionShape3D.shape = $CollisionShape3D.shape.duplicate()
	$MeshInstance3D.mesh.size = Vector3(length, 1.0, 0.5)
	$CollisionShape3D.shape.size = Vector3(length, 1.0, 0.5)
	$MeshInstance3D.material_override = SkinManager.material("wall_low", Color(0.54, 0.5, 0.45))


func get_damage_reduction():
	return DAMAGE_REDUCTION
