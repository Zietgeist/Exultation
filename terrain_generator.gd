extends Node3D
## Builds a zone's terrain from a MAP TEMPLATE (map_templates.gd): open field, rolling hills, forest,
## river, ruins, rails or island. Zone 1 is an open field; later zones pick one the world skin allows.
## Every piece is saved as data, so the layout is remembered for the whole play session.
## Hills: ore gathers around them (and rare Cliff Orchids on top).
## Trees grow in groves: herbs gather around them, and ancient trees can hold Treesilver.

const DITCH_SCENE = preload("res://Ditch.tscn")
const LOW_WALL_SCENE = preload("res://LowWall.tscn")
const SOLID_WALL_SCENE = preload("res://SolidWall.tscn")
const MAPS = preload("res://map_templates.gd")
const CLEAR_RADIUS = 10.0
const GATE_CLEAR_RADIUS = 9.0	# keep gates free so you can always get in and out
const ANCIENT_TREE_CHANCE = 0.15

# Resources (only in zones with quality 1+, i.e. Zone 2 onward)
const ORE_PER_HILL = Vector2i(2, 4)
const ORCHID_CHANCE = 0.3		# per hill: a rare Cliff Orchid on its slope
const HERB_CHANCE = 0.3			# per tree: herbs at its feet
const TREESILVER_CHANCE = 0.5	# per ancient tree
const NODE_SCRIPT = preload("res://resource_node.gd")
const PROPS = preload("res://props.gd")
var _quality = 0

var template := "open_field"
var _gates = []		# gate positions, read before anything is placed
var _keep_out = []	# Rect2s (x, z) that layouts claimed: rivers, rooms, rail lanes
var _half := Vector2(45, 45)


func _ready():
	add_to_group("zone_terrain")
	_find_gates()
	_half = map_half_size(0.0)
	var saved = GameState.saved_zone_part(self, "terrain")
	if saved != null:
		for t in saved:
			if t.get("kind", "") == "template":
				template = t.id
			elif t.has("kind"):
				_rebuild(t)
		_announce.call_deferred()
		return

	var path = owner.scene_file_path if owner else ""
	template = GameState.zone_template(path)
	var def = MAPS.get_def(template)
	var m = GameState.obstacle_multiplier()
	_quality = GameState.zone_quality(path) if owner else 0
	match def.layout:
		"island": _layout_island()
		"river": _layout_river()
		"rooms": _layout_rooms(roundi(6 * m))
		"lanes": _layout_lanes()
		"fences": _layout_fences(roundi(4 * m))
	spawn_hills(roundi(def.hills * m))
	spawn_groves(roundi(def.groves * m), Vector2i(6, 12) if template == "forest" else Vector2i(4, 9))
	if _quality > 0:
		spawn_resources()
	for i in range(roundi(def.ditches * m)):
		var p = get_clear_pos(2.5)
		_make_ditch({p = p, sx = 4.0, sz = 4.0, w = false, r = randf_range(0, TAU)})
	spawn_clusters("low", roundi(def.low * m))
	spawn_clusters("solid", roundi(def.solid * m))
	if _quality > 0:	# shrine trials from Zone 2 on: 1 shrine in Zone 2, 2 after that
		for i in range(clampi(_quality, 1, 2)):
			_make_shrine({p = get_clear_pos(5.0), ability = Trials.random_ability()})
	print("Terrain: %s (%d pieces)" % [template, get_child_count()])
	_announce.call_deferred()


func _announce():
	var zone = GameState.ZONE_NAMES.get(owner.scene_file_path if owner else "", "")
	GameState.notify("%s: %s" % [zone, MAPS.label(template)])


## Snapshot of the layout, so it can be rebuilt exactly.
func save_state() -> Array:
	var out = [{kind = "template", id = template}]
	for piece in get_children():
		if piece.is_queued_for_deletion():
			continue
		if piece.has_meta("kind"):
			var t = piece.get_meta("data").duplicate()
			t.kind = piece.get_meta("kind")
			t.p = piece.position
			out.append(t)
	return out


## Can things stand here? (not water, not a gate, not inside a layout's claimed area)
## pad: extra room needed around the spot (a hill needs more than a tree).
func is_free(pos: Vector3, pad := 0.0) -> bool:
	if _near_gate(pos) or is_water(pos):
		return false
	var p = Vector2(pos.x, pos.z)
	for r in _keep_out:
		if r.grow(pad).has_point(p):
			return false
	return true


## Deep water (island maps). Nothing walks or spawns here.
func is_water(pos: Vector3) -> bool:
	return template == "island" and MAPS.is_island_water(pos, _half, _gates)


## Closest dry spot (searching outward in rings). Used if someone would start in deep water.
func nearest_land(pos: Vector3) -> Vector3:
	if not is_water(pos):
		return pos
	for ring in range(1, 40):
		for i in range(16):
			var a = TAU * i / 16.0
			var p = pos + Vector3(cos(a), 0, sin(a)) * ring * 2.0
			if not is_water(p) and abs(p.x) < _half.x and abs(p.z) < _half.y:
				return p
	ErrorLog.fail("No land found near %s" % pos)
	return pos


func get_clear_pos(pad := 0.0) -> Vector3:
	var pos = Vector3.ZERO
	var half = map_half_size(8.0)  # extra margin: clusters scatter up to 4 units
	for attempt in range(40):
		pos = Vector3(randf_range(-half.x, half.x), 0, randf_range(-half.y, half.y))
		if pos.length() >= CLEAR_RADIUS and is_free(pos, pad):
			return pos
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


# ---------------- Layouts (the shape of each template) ----------------

## Island: deep water all around, a land bridge from every gate to the middle.
func _layout_island():
	var step = 5.0
	var z = -_half.y + step / 2.0
	while z < _half.y:
		var run_start = null
		var x = -_half.x + step / 2.0
		while x < _half.x + step:
			var wet = x < _half.x and is_water(Vector3(x, 0, z))
			if wet and run_start == null:
				run_start = x
			elif not wet and run_start != null:
				var a = run_start - step / 2.0
				var b = x - step / 2.0
				_make_water({p = Vector3((a + b) / 2.0, 0, z), sx = b - a, sz = step})
				run_start = null
			x += step
		z += step
	# shallows: a ring of slow water along the shore
	for i in range(int(TAU * _half.length() * MAPS.ISLAND_SIZE / 6.0)):
		var a = TAU * i / int(TAU * _half.length() * MAPS.ISLAND_SIZE / 6.0)
		var p = Vector3(cos(a) * _half.x * MAPS.ISLAND_SIZE * 0.93, 0, sin(a) * _half.y * MAPS.ISLAND_SIZE * 0.93)
		if not _near_gate(p):
			_make_ditch({p = p, sx = 6.0, sz = 6.0, w = true, r = -a})


## River: a winding band of slow water across the map, with 2-3 bridges.
func _layout_river():
	var along_x = _half.x > _half.y	# the river runs the long way across the map
	var length = _half.x if along_x else _half.y	# half the river's length
	var span = _half.y if along_x else _half.x
	var center = randf_range(-0.3, 0.3) * span
	var amp = 0.12 * span
	var phase = randf() * TAU
	var wave = randf_range(0.6, 1.2) / length
	var bridges = []
	for i in range(randi_range(2, 3)):
		bridges.append(randf_range(-length * 0.8, length * 0.8))
	var t = -length + 2.0	# stay inside the walls
	while t <= length - 2.0:
		var c = center + amp * sin(t * wave * TAU / 4.0 + phase)
		var p = Vector3(c, 0, t) if not along_x else Vector3(t, 0, c)
		if bridges.any(func(b): return abs(t - b) < 3.0):
			pass	# bridge here: dry crossing
		elif not _near_gate(p):
			_make_ditch({p = p, sx = 10.0 if not along_x else 4.0, sz = 4.0 if not along_x else 10.0, w = true, r = 0.0})
		_keep_out.append(Rect2(p.x - 6, p.z - 6, 12, 12))
		t += 3.0
	for bt in bridges:
		var c = center + amp * sin(bt * wave * TAU / 4.0 + phase)
		var p = Vector3(c, 0.2, bt) if not along_x else Vector3(bt, 0.2, c)
		_make_deco({p = p, s = Vector3(12, 0.12, 4.5) if not along_x else Vector3(4.5, 0.12, 12), c = "bridge", f = Color(0.45, 0.32, 0.2)})


## Ruins: the broken outlines of old buildings, each with a doorway. Some wall pieces have fallen.
func _layout_rooms(count: int):
	for i in range(count):
		var w = randf_range(9, 16)
		var d = randf_range(9, 16)
		var c = Vector3.ZERO
		var found = false
		for attempt in range(25):
			c = get_clear_pos(10.0)
			var room = Rect2(c.x - w / 2.0, c.z - d / 2.0, w, d)
			if is_free(c, 10.0) and _keep_out.all(func(r): return not r.grow(3).intersects(room)):
				found = true
				break
		if not found:
			continue
		_keep_out.append(Rect2(c.x - w / 2.0 - 1, c.z - d / 2.0 - 1, w + 2, d + 2))
		var door_side = randi() % 4
		var sides = [
			{a = c + Vector3(-w / 2, 0, -d / 2), b = c + Vector3(w / 2, 0, -d / 2)},
			{a = c + Vector3(w / 2, 0, -d / 2), b = c + Vector3(w / 2, 0, d / 2)},
			{a = c + Vector3(w / 2, 0, d / 2), b = c + Vector3(-w / 2, 0, d / 2)},
			{a = c + Vector3(-w / 2, 0, d / 2), b = c + Vector3(-w / 2, 0, -d / 2)},
		]
		var type = "solid" if randf() < 0.4 else "low"
		for si in range(4):
			var a = sides[si].a
			var b = sides[si].b
			var mid = (a + b) / 2.0
			var gap = 2.0 if si == door_side else 0.0	# doorway in the middle
			for half_side in [[a, mid], [mid, b]]:
				if randf() < 0.2 and si != door_side:
					continue	# fallen down
				var p0 = half_side[0]
				var p1 = half_side[1]
				var dir = (p1 - p0).normalized()
				if p1 == mid:
					p1 -= dir * gap
				else:
					p0 += dir * gap
				_place_wall(type, p0, p1)


## Rails: long parallel walls make lanes, with crossings here and there. Tracks run down each lane.
func _layout_lanes():
	var along_x = _half.x >= _half.y
	var long = _half.x if along_x else _half.y
	var wide = _half.y if along_x else _half.x
	var spacing = 13.0
	var c = -wide + spacing * 0.75
	var lines = []
	while c < wide - spacing * 0.5:
		lines.append(c)
		c += spacing
	for line in lines:
		var t = -long + randf_range(0, 6)
		while t < long:
			var seg = randf_range(10, 18)
			var t1 = min(t + seg, long)
			var a = Vector3(t, 0, line) if along_x else Vector3(line, 0, t)
			var b = Vector3(t1, 0, line) if along_x else Vector3(line, 0, t1)
			_place_wall("solid", a, b)
			t = t1 + randf_range(5, 7)	# crossing
		var r = Rect2(-long, line - 1.5, long * 2, 3) if along_x else Rect2(line - 1.5, -long, 3, long * 2)
		_keep_out.append(r)
	# tracks down the middle of each lane
	var mids = []
	var edges = [-wide] + lines + [wide]
	for i in range(edges.size() - 1):
		mids.append((edges[i] + edges[i + 1]) / 2.0)
	for mid in mids:
		var bed = Vector3(long * 2, 0.04, 2.6) if along_x else Vector3(2.6, 0.04, long * 2)
		var rail = Vector3(long * 2, 0.1, 0.15) if along_x else Vector3(0.15, 0.1, long * 2)
		var o = Vector3(0, 0, 0.7) if along_x else Vector3(0.7, 0, 0)
		var base = Vector3(0, 0, mid) if along_x else Vector3(mid, 0, 0)
		_make_deco({p = base + Vector3(0, 0.19, 0), s = bed, c = "rail_bed", f = Color(0.42, 0.36, 0.3)})
		_make_deco({p = base + o + Vector3(0, 0.24, 0), s = rail, c = "rail", f = Color(0.25, 0.25, 0.27)})
		_make_deco({p = base - o + Vector3(0, 0.24, 0), s = rail, c = "rail", f = Color(0.25, 0.25, 0.27)})
		var r = Rect2(-long, mid - 1.5, long * 2, 3) if along_x else Rect2(mid - 1.5, -long, 3, long * 2)
		_keep_out.append(r)


## Rolling hills: old stone fences between the hills.
func _layout_fences(count: int):
	for i in range(count):
		var a = get_clear_pos(4.0)
		var dir = Vector3(1, 0, 0) if randf() < 0.5 else Vector3(0, 0, 1)
		var pieces = randi_range(3, 5)
		for j in range(pieces):
			var p0 = a + dir * (j * 6.5)
			_place_wall("low", p0, p0 + dir * 5.0)
		_keep_out.append(Rect2(a.x - 1, a.z - 1, dir.x * pieces * 6.5 + 2, dir.z * pieces * 6.5 + 2).abs())


# ---------------- Hills ----------------

func spawn_hills(count: int):
	for i in range(count):
		var center = get_clear_pos(8.0)
		# 1-3 overlapping mounds make a lumpy hill
		for j in range(randi_range(1, 3)):
			var offset = Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) if j > 0 else Vector3.ZERO
			var p = center + offset
			if not is_free(p, 6.0):
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

func spawn_groves(count: int, trees := Vector2i(4, 9)):
	for i in range(count):
		var center = get_clear_pos(3.0)
		for j in range(randi_range(trees.x, trees.y)):
			var p = center + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			if not is_free(p, 1.0):
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
		"wall": _make_wall(t)
		"ditch": _make_ditch(t)
		"water": _make_water(t)
		"deco": _make_deco(t)
		"shrine": _make_shrine(t)
		"gate": _make_gate(t)


# ---------------- Resources ----------------

func spawn_resources():
	for hill in get_tree().get_nodes_in_group("hill"):
		if not hill.get_parent() == self:
			continue
		var d = hill.get_meta("data")
		for i in range(randi_range(ORE_PER_HILL.x, ORE_PER_HILL.y)):
			var a = randf() * TAU
			var p = hill.position + Vector3(cos(a), 0, sin(a)) * (d.r * 0.8 + 0.9)
			if is_free(p):
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
			if is_free(p):
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


## Loose clusters of 2-4 wall pieces (a few per map; layouts do the real shaping).
func spawn_clusters(type: String, cluster_count: int):
	for i in range(cluster_count):
		var center = get_clear_pos(4.0)
		for j in range(randi_range(2, 4)):
			var p = center + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
			var a = randf_range(0, TAU)
			var half_len = randf_range(2.5, 5.0)
			var dir = Vector3(cos(a), 0, sin(a))
			_place_wall(type, p - dir * half_len, p + dir * half_len)


## A wall from a to b, unless it would block a gate or stand in water.
func _place_wall(type: String, a: Vector3, b: Vector3):
	if a.distance_to(b) < 1.0:
		return
	for p in [a, b, (a + b) / 2.0]:
		if _near_gate(p) or is_water(p):
			return
	var dir = b - a
	_make_wall({type = type, l = dir.length(), r = -atan2(dir.z, dir.x), p = (a + b) / 2.0})


func _make_wall(t: Dictionary):
	var piece = (SOLID_WALL_SCENE if t.type == "solid" else LOW_WALL_SCENE).instantiate()
	piece.length = t.l
	piece.set_meta("kind", "wall")
	piece.set_meta("data", {type = t.type, l = t.l, r = t.r})
	add_child(piece)
	piece.position = Vector3(t.p.x, 0, t.p.z)
	piece.rotation.y = t.r


## Slow patch: mud (w = false) or water (w = true).
func _make_ditch(t: Dictionary):
	var piece = DITCH_SCENE.instantiate()
	piece.size = Vector2(t.sx, t.sz)
	piece.water = t.w
	piece.set_meta("kind", "ditch")
	piece.set_meta("data", {sx = t.sx, sz = t.sz, w = t.w, r = t.r})
	add_child(piece)
	piece.position = Vector3(t.p.x, 0, t.p.z)
	piece.rotation.y = t.r


## Deep water: can't be walked through.
func _make_water(t: Dictionary):
	var body = StaticBody3D.new()
	body.set_meta("kind", "water")
	body.set_meta("data", {sx = t.sx, sz = t.sz})
	body.add_to_group("deep_water")
	var shape = BoxShape3D.new()
	shape.size = Vector3(t.sx, 4.0, t.sz)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5
	body.add_child(col)
	var mesh = BoxMesh.new()
	mesh.size = Vector3(t.sx, 0.05, t.sz)
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = SkinManager.material("deep_water", Color(0.1, 0.27, 0.5))
	mi.position.y = 0.19
	body.add_child(mi)
	add_child(body)
	body.position = Vector3(t.p.x, 0, t.p.z)


# ---------------- Shrines and trial gates ----------------

func _make_shrine(t: Dictionary):
	var s = load("res://shrine.gd").new()
	s.ability = t.ability
	s.set_meta("kind", "shrine")
	s.set_meta("data", {ability = t.ability})
	add_child(s)
	s.position = Vector3(t.p.x, 0, t.p.z)


## Failed: the shrine shows up somewhere else in the zone (maybe with a different trial).
func move_shrine(s):
	s.ability = Trials.random_ability()
	s.set_meta("data", {ability = s.ability})
	var p = get_clear_pos(5.0)
	s.queue_free()
	_make_shrine({p = p, ability = s.ability})


## Passed: the shrine becomes a gate to a Trial Ground.
func open_trial_gate(s):
	var q = max(1, GameState.zone_quality(owner.scene_file_path) if owner else 1)
	var p = s.position
	s.queue_free()
	_make_gate({p = p, ability = s.ability, q = q})
	GameState.notify("A gate opens! Clear the Trial Ground beyond it. The last foe holds the Sigil.")


func _make_gate(t: Dictionary):
	var g = load("res://portal.gd").new()
	g.target_scene = Trials.ARENA
	g.label_text = "%s\n%s" % [SkinManager.name_of("trial_gate"), Trials.ability_name(t.ability)]
	g.color = Trials.TYPES[t.ability].color
	g.party_pull = true
	g.set_meta("kind", "gate")
	g.set_meta("data", {ability = t.ability, q = t.q})
	var back = Vector3(t.p.x, 0, t.p.z + 3.0)
	g.before_travel = func():
		Trials.arena = {ability = t.ability, q = t.q, back_scene = owner.scene_file_path, back_pos = back}
		g.queue_free()	# used up (not saved with the zone)
	add_child(g)
	g.position = Vector3(t.p.x, 0, t.p.z)


## Looks only (bridges, rail tracks): no collision. c = skin color id, f = fallback color.
func _make_deco(t: Dictionary):
	var mi = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = t.s
	mi.mesh = mesh
	mi.material_override = SkinManager.material(t.c, t.f)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("kind", "deco")
	mi.set_meta("data", {s = t.s, c = t.c, f = t.f})
	add_child(mi)
	mi.position = t.p


## Half the size of the current zone's floor (x, z), minus a margin so things stay inside the walls.
func map_half_size(margin := 4.0) -> Vector2:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		return floor_node.get_half_size() - Vector2(margin, margin)
	ErrorLog.fail("%s: no map floor found (floor must be in group map_floor). Using a guess of 45." % name)
	return Vector2(45.0, 45.0)
