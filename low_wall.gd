extends StaticBody3D

const DAMAGE_REDUCTION = 0.5

func _ready():
	var length = randf_range(5.0, 11.0)
	$MeshInstance3D.mesh = $MeshInstance3D.mesh.duplicate()
	$CollisionShape3D.shape = $CollisionShape3D.shape.duplicate()
	var mesh = $MeshInstance3D.mesh
	mesh.size = Vector3(length, 1.0, 0.5)
	$CollisionShape3D.shape.size = Vector3(length, 1.0, 0.5)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.45)
	mesh.surface_set_material(0, mat)

func get_damage_reduction():
	return DAMAGE_REDUCTION
