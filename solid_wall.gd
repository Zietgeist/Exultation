extends StaticBody3D
## Tall wall. Blocks movement (and later sight). Color comes from the world skin.

var length := -1.0	# set before adding to the scene; below 0 = random


func _ready():
	if length < 0.0:
		length = randf_range(3.0, 10.0)
	$MeshInstance3D.mesh = $MeshInstance3D.mesh.duplicate()
	$CollisionShape3D.shape = $CollisionShape3D.shape.duplicate()
	$MeshInstance3D.mesh.size = Vector3(length, 3.0, 0.5)
	$CollisionShape3D.shape.size = Vector3(length, 3.0, 0.5)
	$MeshInstance3D.material_override = SkinManager.material("wall_solid", Color(0.29, 0.27, 0.31))


func blocks_vision():
	return true

func blocks_attack():
	return true
