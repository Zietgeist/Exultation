extends StaticBody3D
const TILE_SIZE = 10.0
const GRID_WIDTH = 26
const GRID_DEPTH = 26
const COLOR_A = Color(0.25, 0.3, 0.22)
const COLOR_B = Color(0.38, 0.44, 0.33)

func add_floor_collision():
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(260, 0.2, 260)
	col.shape = shape
	col.position = Vector3(0, 0.1, 0)
	add_child(col)

func _ready():
	_name_zone("Zone 3")
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
	# Zone 3 sits east of Home and Zone 2 (Golden Ratio spiral).
	# West wall has two 10-wide gates: Zone 2 at z=-50, Home at z=80.
	var walls = [
		# North (closed for now)
		[Vector3(0, 1, -130), Vector3(260, 2, 1)],
		# South (Zone 4 will go here later)
		[Vector3(0, 1, 130), Vector3(260, 2, 1)],
		# East (closed)
		[Vector3(130, 1, 0), Vector3(1, 2, 260)],
		# West: three pieces around the two gates
		[Vector3(-130, 1, -92.5), Vector3(1, 2, 75)],
		[Vector3(-130, 1, 15), Vector3(1, 2, 120)],
		[Vector3(-130, 1, 107.5), Vector3(1, 2, 45)],
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


## The zone's name for the HUD (set on the zone, since several zones can be loaded at once).
func _name_zone(n: String):
	var z = Zones.zone_of(self)
	if z:
		z.zone_name = n
