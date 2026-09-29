extends StaticBody3D

const SLOW_FACTOR = 0.4

func _ready():
	# Ditch is sunken into ground
	var mesh = $MeshInstance3D.mesh
	mesh.size = Vector3(4.0, 0.5, 4.0)
	$CollisionShape3D.shape.size = Vector3(4.0, 0.5, 4.0)
	
	# Blue-grey color to show it's a ditch
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.25, 0.3)
	mesh.surface_set_material(0, mat)
	
	# Sink it below ground level
	position.y = -0.3

# Called by movement scripts to check slow factor
func get_slow_factor():
	return SLOW_FACTOR
