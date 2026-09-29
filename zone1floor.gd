extends StaticBody3D
const TILE_SIZE = 10.0
const GRID_WIDTH = 6
const GRID_DEPTH = 10
const COLOR_A = Color(0.3, 0.3, 0.3)
const COLOR_B = Color(0.5, 0.5, 0.5)

func add_floor_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(62, 0.2, 100)
	col.shape = shape
	col.position = Vector3(0, 0.1, 0)
	add_child(col)

func _ready():
	GameState.current_zone = "Zone 1"
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
				x * TILE_SIZE - (GRID_WIDTH * TILE_SIZE / 2),
				0.1,
				z * TILE_SIZE - (GRID_DEPTH * TILE_SIZE / 2)
			)
			add_child(tile)
	add_border_walls()
	add_floor_collision()

func add_border_walls():
	var walls = [
		# North — gap at center for Zone2
		[Vector3(-18, 1, -50), Vector3(26, 2, 1)],
		[Vector3( 18, 1, -50), Vector3(26, 2, 1)],
		# South — gap at center for future
		[Vector3(-18, 1,  50), Vector3(26, 2, 1)],
		[Vector3( 18, 1,  50), Vector3(26, 2, 1)],
		# West — gap at center (outer edge)
		[Vector3(-31, 1, -27.5), Vector3(1, 2, 45)],
		[Vector3(-31, 1,  27.5), Vector3(1, 2, 45)],
		# East — gap at center for Home
		[Vector3( 31, 1, -27.5), Vector3(1, 2, 45)],
		[Vector3( 31, 1,  27.5), Vector3(1, 2, 45)],
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
