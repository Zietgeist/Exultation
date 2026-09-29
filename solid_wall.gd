extends StaticBody3D

func _ready():
	var mesh = $MeshInstance3D.mesh
	mesh.size = Vector3(randf_range(3.0, 10.0), 3.0, 0.5)
	$CollisionShape3D.shape.size = Vector3(4.0, 3.0, 0.5)
	
	# Dark metal color for sci-fi feel
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.25)
	mesh.surface_set_material(0, mat)

func blocks_vision():
	return true

func blocks_attack():
	return true
