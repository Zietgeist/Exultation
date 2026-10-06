extends StaticBody3D
## Floor and walls of a Trial Ground: a small closed square (40 x 40).

const HALF = 20.0
const TILE = 8.0


func _ready():
	add_to_group("map_floor")
	var shape = BoxShape3D.new()
	shape.size = Vector3(HALF * 2 + 2, 0.2, HALF * 2 + 2)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.1
	add_child(col)
	var a = SkinManager.material("arena_floor_a", Color(0.22, 0.2, 0.28))
	var b = SkinManager.material("arena_floor_b", Color(0.3, 0.27, 0.36))
	var n = int(HALF * 2 / TILE)
	for x in range(n):
		for z in range(n):
			var tile = MeshInstance3D.new()
			var mesh = BoxMesh.new()
			mesh.size = Vector3(TILE, 0.1, TILE)
			tile.mesh = mesh
			tile.material_override = a if (x + z) % 2 == 0 else b
			tile.position = Vector3(-HALF + TILE * (x + 0.5), 0.1, -HALF + TILE * (z + 0.5))
			add_child(tile)
	var wall_mat = SkinManager.material("wall_solid", Color(0.29, 0.27, 0.31))
	for w in [[Vector3(0, 1.5, -HALF), Vector3(HALF * 2, 3, 1)], [Vector3(0, 1.5, HALF), Vector3(HALF * 2, 3, 1)],
			[Vector3(-HALF, 1.5, 0), Vector3(1, 3, HALF * 2)], [Vector3(HALF, 1.5, 0), Vector3(1, 3, HALF * 2)]]:
		var body = StaticBody3D.new()
		var s = BoxShape3D.new()
		s.size = w[1]
		var c = CollisionShape3D.new()
		c.shape = s
		body.add_child(c)
		var m = BoxMesh.new()
		m.size = w[1]
		var mi = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = wall_mat
		body.add_child(mi)
		body.position = w[0]
		add_child(body)


func get_half_size() -> Vector2:
	return Vector2(HALF, HALF)
