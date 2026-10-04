extends Node3D
## Random block obstacles. The layout is remembered for the whole play session,
## so leaving a zone and coming back shows the same map.

const OBSTACLE_COUNT = 50


func _ready():
	add_to_group("zone_obstacles")
	var saved = GameState.saved_zone_part(self, "obstacles")
	if saved != null:
		for o in saved:
			_make_obstacle(o.p, o.s, o.c)
		return

	var count = roundi(OBSTACLE_COUNT * GameState.obstacle_multiplier())
	print("Obstacles: creating ", count)
	var half = map_half_size()
	for i in range(count):
		var size = Vector3(randf_range(1.0, 4.0), randf_range(1.0, 3.0), randf_range(1.0, 4.0))
		var color = Color(randf_range(0.2, 0.5), randf_range(0.2, 0.5), randf_range(0.2, 0.5))
		var pos = Vector3(randf_range(-half.x, half.x), 0.75, randf_range(-half.y, half.y))
		_make_obstacle(pos, size, color)


func _make_obstacle(pos: Vector3, size: Vector3, color: Color):
	var obstacle = StaticBody3D.new()
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.surface_set_material(0, mat)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	obstacle.add_child(mesh_instance)
	obstacle.add_child(collision)
	obstacle.set_meta("size", size)
	obstacle.set_meta("color", color)
	add_child(obstacle)
	obstacle.position = pos


## Snapshot of the layout, so it can be rebuilt exactly.
func save_state() -> Array:
	var out = []
	for o in get_children():
		out.append({p = o.position, s = o.get_meta("size"), c = o.get_meta("color")})
	return out


## Half the size of the current zone's floor (x, z), minus a margin so things stay inside the walls.
func map_half_size(margin := 4.0) -> Vector2:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		return floor_node.get_half_size() - Vector2(margin, margin)
	ErrorLog.fail("%s: no map floor found (floor must be in group map_floor). Using a guess of 45." % name)
	return Vector2(45.0, 45.0)
