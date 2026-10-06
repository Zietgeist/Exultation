extends Node3D
## Ditches, low walls, solid walls, hills and trees. The layout is remembered for the whole play session.
## Hills: ore will gather around them (and rare Cliff Orchids on top).
## Trees grow in groves: herbs will gather around them, and ancient trees can hold Treesilver.

const DITCH_SCENE = preload("res://Ditch.tscn")
const LOW_WALL_SCENE = preload("res://LowWall.tscn")
const SOLID_WALL_SCENE = preload("res://SolidWall.tscn")
const CLEAR_RADIUS = 10.0
const GATE_CLEAR_RADIUS = 9.0	# keep gates free so you can always get in and out

# Hills and trees (counts are for Zone 1 density; bigger zones scale up like everything else)
const HILLS = 5
const GROVES = 6
const ANCIENT_TREE_CHANCE = 0.15

# Resources (only in zones with quality 1+, i.e. Zone 2 onward)
const ORE_PER_HILL = Vector2i(2, 4)
const ORCHID_CHANCE = 0.3		# per hill: a rare Cliff Orchid on its slope
const HERB_CHANCE = 0.3			# per tree: herbs at its feet
const TREESILVER_CHANCE = 0.5	# per ancient tree
const NODE_SCRIPT = preload("res://resource_node.gd")
const PROPS = preload("res://props.gd")
var _quality = 0

var _mats = {}
var _gates = []	# gate positions, read before anything is placed


func _ready():
	add_to_group("zone_terrain")
	var saved = GameState.saved_zone_part(self, "terrain")
	if saved != null:
		for t in saved:
			if t.has("kind"):
				_rebuild(t)
				continue
			var piece = load(t.scene).instantiate()
			add_child(piece)
			piece.position = t.p
			piece.rotation.y = t.r
			if "hidden" in piece:
				piece.set_hidden(t.get("h", false))
		return

	var m = GameState.obstacle_multiplier()
	_find_gates()
	_quality = GameState.zone_quality(owner.scene_file_path) if owner else 0
	spawn_hills(roundi(HILLS * m))
	spawn_groves(roundi(GROVES * m))
	if _quality > 0:
		spawn_resources()
	spawn_terrain(DITCH_SCENE, roundi(15 * m))	# half as many slow patches as before
	spawn_clusters(LOW_WALL_SCENE, roundi(15 * m))
	spawn_clusters(SOLID_WALL_SCENE, roundi(10 * m))


## Snapshot of the layout, so it can be rebuilt exactly.
func save_state() -> Array:
	var out = []
	for piece in get_children():
		if piece.has_meta("kind"):
			var t = piece.get_meta("data").duplicate()
			t.kind = piece.get_meta("kind")
			t.p = piece.position
			out.append(t)
			continue
		out.append({scene = piece.scene_file_path, p = piece.position, r = piece.rotation.y, h = piece.get("hidden") == true})
	return out


func get_clear_pos() -> Vector3:
	var pos = Vector3.ZERO
	var attempts = 0
	var half = map_half_size(8.0)  # extra margin: clusters scatter up to 4 units
	while (pos.length() < CLEAR_RADIUS or _near_gate(pos)) and attempts < 30:
		pos = Vector3(
			randf_range(-half.x, half.x),
			0,
			randf_range(-half.y, half.y)
		)
		attempts += 1
	return pos


func _find_gates():
	_gates.clear()
	for n in get_parent().get_children():
		if n is Area3D and "target_scene" in n:
			_gates.append(n.position)


func _near_gate(pos: Vector3) -> bool:
	for g in _gates:
		if Vector2(pos.x - g.x, pos.z - g.z).length() < GATE_CLEAR_RADIUS:
			return true
	return false


# ---------------- Hills ----------------

func spawn_hills(count: int):
	for i in range(count):
		var center = get_clear_pos()
		# 1-3 overlapping mounds make a lumpy hill
		for j in range(randi_range(1, 3)):
			var offset = Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) if j > 0 else Vector3.ZERO
			var p = center + offset
			if _near_gate(p):
				continue
			_make_hill(p, {r = randf_range(4.0, 7.0), h = randf_range(1.5, 3.0), v = randi() % 100})


func _make_hill(pos: Vector3, data: Dictionary):
	var body = StaticBody3D.new()
	body.set_meta("kind", "hill")
	body.set_meta("data", data)
	body.add_to_group("hill")
	body.add_child(PROPS.hill(SkinManager.props_style(), data))	# looks come from the world skin
	var shape = CylinderShape3D.new()
	shape.radius = data.r * 0.8
	shape.height = data.h
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = data.h / 2.0
	body.add_child(col)
	add_child(body)
	body.position = Vector3(pos.x, 0, pos.z)


# ---------------- Trees ----------------

func spawn_groves(count: int):
	for i in range(count):
		var center = get_clear_pos()
		for j in range(randi_range(4, 9)):
			var p = center + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			if _near_gate(p):
				continue
			var ancient = randf() < ANCIENT_TREE_CHANCE
			_make_tree(p, {s = randf_range(1.6, 2.0) if ancient else randf_range(0.8, 1.2), ancient = ancient, v = randi() % 100})


func _make_tree(pos: Vector3, data: Dictionary):
	var s = data.s
	var body = StaticBody3D.new()
	body.set_meta("kind", "tree")
	body.set_meta("data", data)
	body.add_to_group("tree")
	if data.ancient:
		body.add_to_group("ancient_tree")
	var look = PROPS.tree(SkinManager.props_style(), data)	# looks come from the world skin
	body.add_child(look.root)
	body.set_meta("fade", look.fade)
	var shape = CylinderShape3D.new()	# only the trunk blocks you
	shape.radius = 0.4 * s
	shape.height = 3.0 * s
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5 * s
	body.add_child(col)
	add_child(body)
	body.position = Vector3(pos.x, 0, pos.z)


## Tree tops between the camera and the player turn see-through, so they never hide you.
var _fade_timer = 0.0

func _process(delta):
	_fade_timer -= delta
	if _fade_timer > 0.0:
		return
	_fade_timer = 0.1
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var pp = player.global_position
	for tree in get_tree().get_nodes_in_group("tree"):
		var tp = tree.global_position
		var s = tree.get_meta("data").s
		var in_the_way = tp.z > pp.z - 2.0 and tp.z < pp.z + 14.0 and abs(tp.x - pp.x) < 2.5 * s + 1.0
		for m in tree.get_meta("fade"):
			if not m.has_meta("solid"):
				m.set_meta("solid", m.material_override)
			m.material_override = _faded(m.get_meta("solid")) if in_the_way else m.get_meta("solid")


var _faded_mats = {}

## A see-through copy of a material (made once per material).
func _faded(solid: StandardMaterial3D) -> StandardMaterial3D:
	if not _faded_mats.has(solid):
		var f = solid.duplicate()
		f.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		f.albedo_color.a = 0.25
		_faded_mats[solid] = f
	return _faded_mats[solid]


func _rebuild(t: Dictionary):
	match t.kind:
		"hill": _make_hill(t.p, t)
		"tree": _make_tree(t.p, t)
		"node": _make_node(t.p, t)


# ---------------- Resources ----------------

func spawn_resources():
	for hill in get_tree().get_nodes_in_group("hill"):
		if not hill.get_parent() == self:
			continue
		var d = hill.get_meta("data")
		for i in range(randi_range(ORE_PER_HILL.x, ORE_PER_HILL.y)):
			var a = randf() * TAU
			var p = hill.position + Vector3(cos(a), 0, sin(a)) * (d.r * 0.8 + 0.9)
			if not _near_gate(p):
				_make_node(p, {type = "ore", q = _quality, reach = 0.0})
		if randf() < ORCHID_CHANCE:
			var a = randf() * TAU
			var p = hill.position + Vector3(cos(a) * d.r * 0.82, d.h * 0.35, sin(a) * d.r * 0.82)
			_make_node(p, {type = "orchid", q = _quality, reach = 1.0})
	for tree in get_tree().get_nodes_in_group("tree"):
		if not tree.get_parent() == self:
			continue
		var d = tree.get_meta("data")
		if d.ancient and randf() < TREESILVER_CHANCE:
			var a = randf() * TAU
			_make_node(tree.position + Vector3(cos(a), 0, sin(a)) * (0.35 * d.s + 0.25), {type = "treesilver", q = _quality, reach = 0.5})
		elif randf() < HERB_CHANCE:
			var a = randf() * TAU
			var p = tree.position + Vector3(cos(a), 0, sin(a)) * randf_range(1.2, 2.5)
			if not _near_gate(p):
				_make_node(p, {type = "herb", q = _quality, reach = 0.0})


func _make_node(pos: Vector3, data: Dictionary):
	var n = NODE_SCRIPT.new()
	n.type = data.type
	n.quality = data.q
	n.reach = data.get("reach", 0.0)
	n.set_meta("kind", "node")
	n.set_meta("data", {type = data.type, q = data.q, reach = n.reach})
	add_child(n)
	n.position = pos


func _mat(id: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(id):
		var m = StandardMaterial3D.new()
		m.albedo_color = color
		_mats[id] = m
	return _mats[id]


func spawn_terrain(scene, count):
	for i in range(count):
		var piece = scene.instantiate()
		add_child(piece)
		piece.position = get_clear_pos()
		piece.rotation.y = randf_range(0, TAU)


func spawn_clusters(scene, cluster_count):
	for i in range(cluster_count):
		var center = get_clear_pos()
		var pieces = randi_range(2, 4)
		for j in range(pieces):
			var piece = scene.instantiate()
			add_child(piece)
			# Scatter pieces close together
			var offset = Vector3(
				randf_range(-4.0, 4.0),
				0,
				randf_range(-4.0, 4.0)
			)
			piece.position = center + offset
			if _near_gate(piece.position):
				piece.queue_free()
			# Similar angle with slight variation for L-shapes
			piece.rotation.y = randf_range(0, TAU)


## Half the size of the current zone's floor (x, z), minus a margin so things stay inside the walls.
func map_half_size(margin := 4.0) -> Vector2:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		return floor_node.get_half_size() - Vector2(margin, margin)
	ErrorLog.fail("%s: no map floor found (floor must be in group map_floor). Using a guess of 45." % name)
	return Vector2(45.0, 45.0)
