extends StaticBody3D

func _ready():
	$MeshInstance3D.mesh = $MeshInstance3D.mesh.duplicate()
	$CollisionShape3D.shape = $CollisionShape3D.shape.duplicate()
	var mesh = $MeshInstance3D.mesh
	var length = randf_range(3.0, 10.0)
	mesh.size = Vector3(length, 3.0, 0.5)
	$CollisionShape3D.shape.size = Vector3(length, 3.0, 0.5)	# collision now matches what you see
	
	# Dark metal color for sci-fi feel
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.25)
	mesh.surface_set_material(0, mat)

func blocks_vision():
	return true

func blocks_attack():
	return true
