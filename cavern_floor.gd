extends StaticBody3D
## Floor and outer walls of a cavern (Cavern.tscn): 140 x 140, dark rock. The winding walls inside
## are built by cavern.gd.

const HALF = 70.0


func _ready():
	add_to_group("map_floor")
	var shape = BoxShape3D.new()
	shape.size = Vector3(HALF * 2 + 2, 0.2, HALF * 2 + 2)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.1
	add_child(col)
	var plane = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(HALF * 2, HALF * 2)
	plane.mesh = pm
	plane.position.y = 0.15
	plane.material_override = SkinManager.material("cave_floor", Color(0.2, 0.18, 0.17))
	add_child(plane)


func get_half_size() -> Vector2:
	return Vector2(HALF, HALF)
