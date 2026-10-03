extends Node3D

const OBSTACLE_COUNT = 50

func _ready():
	print("Obstacles script running, creating ", OBSTACLE_COUNT, " obstacles")
	var half = map_half_size()
	for i in range(OBSTACLE_COUNT):
		var obstacle = StaticBody3D.new()
		
		var mesh_instance = MeshInstance3D.new()
		var mesh = BoxMesh.new()
		var size = Vector3(randf_range(1.0, 4.0), randf_range(1.0, 3.0), randf_range(1.0, 4.0))
		mesh.size = size
		mesh_instance.mesh = mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(randf_range(0.2, 0.5), randf_range(0.2, 0.5), randf_range(0.2, 0.5))
		mesh.surface_set_material(0, mat)
		
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		
		obstacle.add_child(mesh_instance)
		obstacle.add_child(collision)
		add_child(obstacle)
		
		obstacle.position = Vector3(
			randf_range(-half.x, half.x),
			0.75,
			randf_range(-half.y, half.y)
		)

## Half the size of the current zone's floor (x, z), minus a margin so things stay inside the walls.
func map_half_size(margin := 4.0) -> Vector2:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		return floor_node.get_half_size() - Vector2(margin, margin)
	ErrorLog.fail("%s: no map floor found (floor must be in group map_floor). Using a guess of 45." % name)
	return Vector2(45.0, 45.0)
