extends RefCounted
## Simple pathfinding for smarter enemies (Thug, Master, Boss). Trash just walks straight at you.
## How it works: the ground is cut into CELL-sized squares. A square is "solid" if a wall, hut,
## building, tree or other StaticBody3D stands there. A* (AStarGrid2D) then finds a way around.
## Which squares are solid is remembered for a while (walls don't move), so it stays cheap.

const CELL = 2.0			# meters per grid square
const MARGIN = 14.0			# how far past you and the enemy the search may wander
const MAX_SIDE = 48			# biggest search area, in squares (48 x 2 m = 96 m)
const PROBE_Y = 1.2			# the height enemies stand at (spawner ENEMY_REST_HEIGHT)
const FORGET_AFTER = 20.0	# seconds before re-checking squares (landmarks can build new walls)

static var _solid = {}		# Vector2i square -> true/false
static var _since := 0.0	# Time (seconds) when _solid was last cleared
static var _probe: BoxShape3D


## Can I walk in a straight line from a to b without hitting a wall?
static func clear_line(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q = PhysicsRayQueryParameters3D.create(Vector3(a.x, PROBE_Y, a.z), Vector3(b.x, PROBE_Y, b.z), 1)
	var hit = space.intersect_ray(q)
	return hit.is_empty() or not (hit.collider is StaticBody3D) or hit.collider.is_in_group("hill")	# hills: climb over


## Waypoints (world positions) from a to b around walls. Empty = no way found (walk straight).
static func find(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Array:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _since > FORGET_AFTER:
		_solid.clear()
		_since = now
	var ca = _cell(a)
	var cb = _cell(b)
	var lo = Vector2i(mini(ca.x, cb.x), mini(ca.y, cb.y)) - Vector2i.ONE * int(MARGIN / CELL)
	var hi = Vector2i(maxi(ca.x, cb.x), maxi(ca.y, cb.y)) + Vector2i.ONE * int(MARGIN / CELL)
	if hi.x - lo.x > MAX_SIDE or hi.y - lo.y > MAX_SIDE:
		return []	# too far apart to plan; the enemy just heads straight for you
	var grid = AStarGrid2D.new()
	grid.region = Rect2i(lo, hi - lo + Vector2i.ONE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var c = Vector2i(x, z)
			if c != ca and c != cb and _is_solid(space, c):
				grid.set_point_solid(c, true)
	var cells = grid.get_id_path(ca, cb, true)	# true: if fully walled off, get as close as possible
	var out = []
	for i in range(1, cells.size()):	# skip the square the enemy is already in
		out.append(Vector3((cells[i].x + 0.5) * CELL, a.y, (cells[i].y + 0.5) * CELL))
	if not out.is_empty():
		out[-1] = Vector3(b.x, a.y, b.z)
	return out


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func _is_solid(space: PhysicsDirectSpaceState3D, c: Vector2i) -> bool:
	if _solid.has(c):
		return _solid[c]
	if _probe == null:
		_probe = BoxShape3D.new()
		_probe.size = Vector3(CELL * 0.8, 1.0, CELL * 0.8)
	var q = PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.collision_mask = 1	# walls and props (enemies are on layer 3)
	q.transform = Transform3D(Basis(), Vector3((c.x + 0.5) * CELL, PROBE_Y, (c.y + 0.5) * CELL))
	var solid = false
	for hit in space.intersect_shape(q, 4):
		if hit.collider is StaticBody3D and not hit.collider.is_in_group("hill"):	# hills can be climbed
			solid = true
			break
	_solid[c] = solid
	return solid
