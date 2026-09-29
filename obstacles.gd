extends Node3D

const OBSTACLE_COUNT = 50
const MAP_SIZE = 140.0

func _ready():
	print("Obstacles script running, creating ", OBSTACLE_COUNT, " obstacles")
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
			randf_range(-MAP_SIZE, MAP_SIZE),
			0.75,
			randf_range(-MAP_SIZE, MAP_SIZE)
		)
