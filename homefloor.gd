extends StaticBody3D
const TILE_SIZE = 10.0
const GRID_WIDTH = 10
const GRID_DEPTH = 10
const COLOR_A = Color(0.3, 0.3, 0.3)
const COLOR_B = Color(0.5, 0.5, 0.5)

func add_floor_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(100, 0.2, 100)
	col.shape = shape
	col.position = Vector3(0, 0.1, 0)
	add_child(col)


func _ready():
	GameState.current_zone = "Home"
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
		# North — two halves with center gap for Zone2
		[Vector3(-27.5, 1, -50), Vector3(45, 2, 1)],
		[Vector3( 27.5, 1, -50), Vector3(45, 2, 1)],
		# South — closed for now (Zone 4 will connect here later)
		[Vector3(0, 1, 50), Vector3(100, 2, 1)],
		# West — two halves with center gap for Zone1
		[Vector3(-50, 1, -27.5), Vector3(1, 2, 45)],
		[Vector3(-50, 1,  27.5), Vector3(1, 2, 45)],
		# East — two halves with center gap for Zone3
		[Vector3( 50, 1, -27.5), Vector3(1, 2, 45)],
		[Vector3( 50, 1,  27.5), Vector3(1, 2, 45)],
	]
	for w in walls:
		var body = StaticBody3D.new()
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = w[1]
		col.shape = shape
		body.add_child(col)
		# Visible wall (they used to be invisible, so gaps looked like doors)
		var wall_mesh = BoxMesh.new()
		wall_mesh.size = w[1]
		var wall_view = MeshInstance3D.new()
		wall_view.mesh = wall_mesh
		wall_view.material_override = _wall_material()
		body.add_child(wall_view)
		body.position = w[0]
		add_child(body)

## Half the floor size (x, z). The spawner uses this to keep enemies on the map.
func get_half_size() -> Vector2:
	return Vector2(GRID_WIDTH * TILE_SIZE / 2.0, GRID_DEPTH * TILE_SIZE / 2.0)


var _wall_mat: StandardMaterial3D = null

func _wall_material() -> StandardMaterial3D:
	if _wall_mat == null:
		_wall_mat = StandardMaterial3D.new()
		_wall_mat.albedo_color = Color(0.15, 0.13, 0.12)
	return _wall_mat
