extends StaticBody3D
const TILE_SIZE = 10.0
const GRID_WIDTH = 17
const GRID_DEPTH = 17
const COLOR_A = Color(0.2, 0.2, 0.3)
const COLOR_B = Color(0.35, 0.35, 0.45)

func add_floor_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(170, 0.2, 170)
	col.shape = shape
	col.position = Vector3(0, 0.1, 0)
	add_child(col)

func _ready():
	GameState.current_zone = "Zone 2"
	add_to_group("map_floor")
	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var tile = MeshInstance3D.new()
			var mesh = BoxMesh.new()
			mesh.size = Vector3(TILE_SIZE, 0.1, TILE_SIZE)
			tile.mesh = mesh
			var mat = StandardMaterial3D.new()
			if (x + z) % 2 == 0:
				mat.albedo_color = COLOR_A
			else:
				mat.albedo_color = COLOR_B
			tile.mesh.surface_set_material(0, mat)
			tile.position = Vector3(
				x * TILE_SIZE - (GRID_WIDTH * TILE_SIZE / 2) + TILE_SIZE / 2,
				0.1,
				z * TILE_SIZE - (GRID_DEPTH * TILE_SIZE / 2) + TILE_SIZE / 2
			)
			add_child(tile)
	add_border_walls()
	add_floor_collision()

func add_border_walls():
	var walls = [
		# North — gap at center for future zone
		[Vector3(-42, 1, -85), Vector3(86, 2, 1)],
		[Vector3( 42, 1, -85), Vector3(86, 2, 1)],
		# South — two gaps: one for Home door, one for Zone1 door
		# Zone1 door at x=-50 (left side), Home door at x=+20 (right side)
		[Vector3(-80, 1, 85), Vector3(30, 2, 1)],   # Far left
		[Vector3(-42, 1, 85), Vector3(26, 2, 1)],   # Between doors
		[Vector3( 20, 1, 85), Vector3(90, 2, 1)],   # Right of Home door
		# West
		[Vector3(-85, 1, 0), Vector3(1, 2, 170)],
		# East
		[Vector3( 85, 1, 0), Vector3(1, 2, 170)],
	]
	for w in walls:
		var body = StaticBody3D.new()
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = w[1]
		col.shape = shape
		body.add_child(col)
		body.position = w[0]
		add_child(body)

## Half the floor size (x, z). The spawner uses this to keep enemies on the map.
func get_half_size() -> Vector2:
	return Vector2(GRID_WIDTH * TILE_SIZE / 2.0, GRID_DEPTH * TILE_SIZE / 2.0)
