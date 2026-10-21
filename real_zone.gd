extends Node3D
## A Real Place: a real neighborhood (real_map.gd) with enemy packs in its yards, streets and lots.
## Opened from the Real Place ring at Home (real_place_ui.gd). Clear every pack to finish it.
## The Return ring (where you arrived) goes back Home. Nothing here is saved; solo only for now.

const REAL_MAP = preload("res://real_map.gd")
const ENEMY_SCENE = preload("res://enemy.tscn")
const PACKS = 28			# leader + Trash groups on the map (600 x 600 m)
const BOSSES = 2			# far from where you arrive, each with a small escort
const BOSS_GAP = 150.0		# the two bosses at least this far apart
const MINIMAP_SIZE = 230.0	# pixels (top-right corner)
const MINIMAP_METERS = 160.0	# how much ground the mini-map shows across
const MAP_COLORS = {building = Color(0.62, 0.6, 0.58), road = Color(0.3, 0.3, 0.33), green = Color(0.25, 0.45, 0.22), water = Color(0.2, 0.35, 0.65)}
const PACK_TRASH = Vector2i(6, 10)
const PACK_SPREAD = 6.0
const PACK_GAP = 25.0		# packs at least this far apart
const SAFE_START = 30.0		# no pack this close to where you arrive
const MASTER_CHANCE = 0.25	# a pack's leader is a Master instead of a Thug
# Things to gather (G), placed from the real map: herbs in parks and lawns, ore (scrap, rubble) at the
# foot of buildings, Treesilver in bigger parks and woods, Cliff Orchids at the base of the tallest buildings.
const ORE_COUNT = 35
const HERB_COUNT = 45
const HERB_IN_GREEN = 0.75	# share of herbs that grow in parks/lawns (the rest: any open ground)
const TREESILVER_MAX = 8
const TREESILVER_MIN_AREA = 1500.0	# m2: only parks/woods at least this big
const ORCHID_COUNT = 4
const NODE_GAP = 4.0		# resources at least this far apart

var info := {}
var alive := 0
var bosses_left := 0
var cleared := false
var _ring = null			# the Return ring (real_return_ring.gd)
var _map: Node3D = null		# the buildings etc. (see-through around you: real_map.gd)
var map_mesh: ArrayMesh		# the whole map as one flat drawing (mini-map and M map)
var _sleep_t := 0.0
const WAKE_RADIUS = 50.0	# idle enemies farther than SLEEP_RADIUS from you stop thinking (keeps 300+ enemies fast)
const SLEEP_RADIUS = 60.0


## Far-away idle enemies sleep (no physics) until you come near, like the regular zones' spawner.
func _process(_delta):	# buildings between the camera and you get a see-through hole
	var me = Zones.player
	if me and is_instance_valid(me) and Zones.zone_of(me) == Zones.zone_of(self):
		REAL_MAP.update_see_through(_map, me, me.camera)


func _physics_process(delta):
	_sleep_t -= delta
	if _sleep_t > 0.0:
		return
	_sleep_t = 0.5
	var spots = []
	for m in GameState.party(self):
		if is_instance_valid(m) and m.is_inside_tree() and Zones.zone_of(m) == Zones.zone_of(self):
			spots.append(m.global_position)
	for e in Zones.all(self, "enemy"):
		if e.aggroed or e.hunter:
			e.set_physics_process(true)
			continue
		var d = INF
		for sp in spots:
			d = minf(d, Vector2(e.global_position.x - sp.x, e.global_position.z - sp.z).length())
		if d < WAKE_RADIUS:
			e.set_physics_process(true)
		elif d > SLEEP_RADIUS:
			e.set_physics_process(false)


func _ready():
	var z = Zones.zone_of(self)
	info = z.info if z else {}
	if not info.has("data"):
		ErrorLog.warn("Real Place opened without a map (started directly?): going Home")
		Net.go.call_deferred("res://Home.tscn")
		return
	z.zone_name = "Real Place"
	var rm = REAL_MAP.new()
	_map = rm.build(info.data)
	add_child(_map)
	_border()
	_return_ring(rm)
	if not Net.is_client():
		_spawn_packs(rm)
		_spawn_bosses(rm)
		_spawn_resources(rm)
		var director = load("res://real_director.gd").new()	# hordes: build-up, peak, a minute of calm
		director.zone = self
		add_child(director)
	rm.free()
	_build_map_mesh()
	_credit_and_minimap()
	if Zones.local_zone() == z:
		GameState.notify.call_deferred("A real place! %d packs and %d bosses. The Return ring opens once it's clear (G in it to leave early)." % [PACKS, BOSSES])


## How tough: grows with how far you've got (zones open), like the zone you'd be fighting in.
func _difficulty() -> Array:
	var open = 0
	for p in GameState.unlocked_zones:
		if p in GameState.ZONE_ORDER:
			open += 1
	open = clampi(open, 1, GameState.ZONE_ORDER.size())
	return [1.0 + 0.5 * (open - 1), GameState.ZONE_ORDER[open - 1]]


func _spawn_packs(rm):
	var d = _difficulty()
	var start = Vector2(info.spawn.x, info.spawn.z)
	var h = REAL_MAP.HALF_SIZE - 10.0
	var centers = []
	var tries = 0
	while centers.size() < PACKS and tries < 500:
		tries += 1
		var p = Vector2(randf_range(-h, h), randf_range(-h, h))
		if p.distance_to(start) < SAFE_START or rm._inside_building(info.data, p):
			continue
		if centers.any(func(c): return c.distance_to(p) < PACK_GAP):
			continue
		centers.append(p)
	if centers.size() < PACKS:
		ErrorLog.warn("Real Place: only room for %d of %d packs (very built-up area)" % [centers.size(), PACKS])
	for c in centers:
		_spawn(2 if randf() < MASTER_CHANCE else 1, c, d)
		for i in range(randi_range(PACK_TRASH.x, PACK_TRASH.y)):
			for attempt in range(6):
				var a = randf() * TAU
				var p = c + Vector2(cos(a), sin(a)) * randf_range(1.5, PACK_SPREAD)
				if not rm._inside_building(info.data, p):
					_spawn(0, p, d)
					break


## Bosses go as far from where you arrive as possible (and far from each other), with an escort.
func _spawn_bosses(rm):
	var d = _difficulty()
	var start = Vector2(info.spawn.x, info.spawn.z)
	var h = REAL_MAP.HALF_SIZE - 15.0
	var spots = []
	for i in range(400):	# open ground all over the map
		var p = Vector2(randf_range(-h, h), randf_range(-h, h))
		if not rm._inside_building(info.data, p):
			spots.append(p)
	var picked = []
	for b in range(BOSSES):
		var best = null
		var best_d = -1.0
		for p in spots:
			if picked.any(func(q): return q.distance_to(p) < BOSS_GAP):
				continue
			var dd = p.distance_to(start)
			if dd > best_d:
				best = p
				best_d = dd
		if best == null:
			ErrorLog.warn("Real Place: no room for boss %d" % (b + 1))
			continue
		picked.append(best)
		_spawn(3, best, d)
		for i in range(8):	# escort: 2 Thugs, 6 Trash
			for attempt in range(6):
				var a = randf() * TAU
				var p = best + Vector2(cos(a), sin(a)) * randf_range(3.0, 8.0)
				if not rm._inside_building(info.data, p):
					_spawn(1 if i < 2 else 0, p, d)
					break


func _spawn(tier: int, p: Vector2, d: Array):
	var e = ENEMY_SCENE.instantiate()
	e.defeated.connect(_on_enemy_died)	# defeated = died OR turned
	add_child(e)
	e.global_position = Vector3(p.x, 1.2, p.y)
	e.setup(d[0], tier, Crafting.roll_enemy_element(d[1], tier == 3))
	alive += 1
	if tier == 3:
		bosses_left += 1


## A rival came here (rivals.gd): it has to fall too.
func adopt_enemy(e):
	e.defeated.connect(_on_enemy_died)	# defeated = died OR turned
	alive += 1


func _on_enemy_died(tier):
	alive -= 1
	if tier == 3:
		bosses_left -= 1
		GameState.notify("A boss is down! %s" % ("One more to go." if bosses_left == 1 else ("Both bosses down!" if bosses_left <= 0 else "%d to go." % bosses_left)))
	if alive <= 0 and not cleared:
		cleared = true
		GameState.notify("This place is clear! The Return ring is open.")
		if is_instance_valid(_ring):
			_ring.unlock()


## Invisible walls at the edge of the downloaded area.
func _border():
	var h = REAL_MAP.HALF_SIZE
	for w in [[Vector3(0, 2, -h), Vector3(h * 2, 4, 1)], [Vector3(0, 2, h), Vector3(h * 2, 4, 1)],
			[Vector3(-h, 2, 0), Vector3(1, 4, h * 2)], [Vector3(h, 2, 0), Vector3(1, 4, h * 2)]]:
		var body = StaticBody3D.new()
		var shape = BoxShape3D.new()
		shape.size = w[1]
		var col = CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		body.position = w[0]
		add_child(body)


func _return_ring(rm):
	var g = load("res://real_return_ring.gd").new()	# locked until cleared (G leaves early)
	g.target_scene = info.back_scene
	g.target_position = info.back_pos
	_ring = g
	var s = info.spawn
	var spot = Vector2(s.x + 4.0, s.z)
	for off in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
		if not rm._inside_building(info.data, Vector2(s.x, s.z) + off):
			spot = Vector2(s.x, s.z) + off
			break
	add_child(g)
	g.position = Vector3(spot.x, 0, spot.y)


# ---------------- Maps ----------------

## Everything flat (parks, water, roads, buildings) as one 2D mesh: cheap to draw every frame.
func _build_map_mesh():
	var verts = PackedVector2Array()
	var cols = PackedColorArray()
	var add_poly = func(pts: PackedVector2Array, c: Color):
		var idx = Geometry2D.triangulate_polygon(pts)
		for i in idx:
			verts.append(pts[i])
			cols.append(c)
	for a in info.data.areas:
		add_poly.call(a.pts, MAP_COLORS.water if a.kind == "water" else MAP_COLORS.green)
	for r in info.data.roads:
		var w = maxf(r.w, 3.0)	# thin paths still show
		for i in range(r.pts.size() - 1):
			var dv = r.pts[i + 1] - r.pts[i]
			if dv.length() < 0.01:
				continue
			var s = Vector2(-dv.y, dv.x).normalized() * w / 2.0
			for p in [r.pts[i] + s, r.pts[i + 1] + s, r.pts[i + 1] - s, r.pts[i] + s, r.pts[i + 1] - s, r.pts[i] - s]:
				verts.append(p)
				cols.append(MAP_COLORS.road)
	for b in info.data.buildings:
		add_poly.call(b.pts, MAP_COLORS.building)
	map_mesh = ArrayMesh.new()
	if verts.is_empty():
		return
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	map_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Draw this place onto a map (the mini-map, or the M map: map_overlay.gd calls this).
## offset = where world (0, 0) lands on screen, s = pixels per meter, view = the visible rectangle.
func draw_map(ci: CanvasItem, offset: Vector2, s: float, view: Rect2):
	var h = REAL_MAP.HALF_SIZE
	ci.draw_rect(Rect2(offset + Vector2(-h, -h) * s, Vector2(h, h) * 2.0 * s), Color(0.16, 0.17, 0.15))
	if map_mesh and map_mesh.get_surface_count() > 0:
		ci.draw_mesh(map_mesh, null, Transform2D(0.0, Vector2(s, s), 0.0, offset))
	ci.draw_rect(Rect2(offset + Vector2(-h, -h) * s, Vector2(h, h) * 2.0 * s), Color(1.0, 0.85, 0.3), false, 1.5)
	var inner = view.grow(-7.0)
	for e in Zones.all(self, "enemy"):
		var p = offset + Vector2(e.global_position.x, e.global_position.z) * s
		if e.tier == 3:	# bosses: always shown; off the edge -> an arrow at the edge pointing at it
			var q = Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.y, inner.position.y, inner.end.y))
			var r = 7.0 if q == p else 5.0
			ci.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -r), q + Vector2(r, 0), q + Vector2(0, r), q + Vector2(-r, 0)]), Color(1.0, 0.8, 0.0))
		elif view.has_point(p):
			ci.draw_circle(p, 2.5 if e.tier == 0 else 3.5, [Color(0.3, 0.9, 0.3), Color(0.35, 0.55, 1.0), Color(0.75, 0.3, 1.0)][e.tier])
	for a in Zones.all(self, "ally_mob"):
		var p = offset + Vector2(a.global_position.x, a.global_position.z) * s
		if view.has_point(p):
			ci.draw_circle(p, 3.0, Color(0.35, 1.0, 0.75))
	if is_instance_valid(_ring):	# the Return ring: gold when open, gray while locked
		var p = offset + Vector2(_ring.global_position.x, _ring.global_position.z) * s
		ci.draw_arc(p, 6.0, 0, TAU, 16, Color(0.6, 0.6, 0.6) if _ring.locked else Color(1.0, 0.8, 0.2), 2.0)
	var me = Zones.player
	if me and is_instance_valid(me):
		var p = offset + Vector2(me.global_position.x, me.global_position.z) * s
		ci.draw_circle(p, 5.0, Color.WHITE)
		ci.draw_arc(p, 5.0, 0, TAU, 16, Color.BLACK, 1.5)


## The map's credit (must be on screen while you play here) and the mini-map in the top-right corner.
func _credit_and_minimap():
	var ui = CanvasLayer.new()
	var mm = Control.new()
	mm.set_script(load("res://real_minimap.gd"))
	mm.zone = self
	mm.meters = MINIMAP_METERS
	mm.anchor_left = 1.0	# pinned to the top-right corner
	mm.anchor_right = 1.0
	mm.offset_left = -MINIMAP_SIZE - 12.0
	mm.offset_right = -12.0
	mm.offset_top = 12.0
	mm.offset_bottom = MINIMAP_SIZE + 12.0
	ui.add_child(mm)
	var l = Label.new()
	l.text = "Map data (c) OpenStreetMap contributors"
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.position += Vector2(8, -6)
	ui.add_child(l)
	add_child(ui)


# ---------------- Resources ----------------

## Gatherable nodes, quality like the zone the enemies are scaled to.
func _spawn_resources(rm):
	var q = maxi(1, GameState.zone_quality(_difficulty()[1]))	# Zone 1 has no resources (quality 0): start at 1
	var h = REAL_MAP.HALF_SIZE - 6.0
	var placed = []	# Vector2s
	var ok = func(p: Vector2) -> bool:
		if abs(p.x) > h or abs(p.y) > h or rm._inside_building(info.data, p) or _in_water(p):
			return false
		return not placed.any(func(o): return o.distance_to(p) < NODE_GAP)
	var put = func(type: String, p: Vector2, reach: float):
		placed.append(p)
		var n = load("res://resource_node.gd").new()
		n.type = type
		n.quality = q
		n.reach = reach
		add_child(n)
		n.position = Vector3(p.x, 0.0, p.y)
	var greens = info.data.areas.filter(func(a): return a.kind == "green" and a.pts.size() >= 3)
	var counts = {ore = 0, herb = 0, treesilver = 0, orchid = 0}
	# Herbs: mostly in parks and lawns (weighted by size), the rest anywhere open
	var green_area = 0.0
	for a in greens:
		green_area += _area(a.pts)
	for i in range(HERB_COUNT * 6):
		if counts.herb >= HERB_COUNT:
			break
		var p = Vector2.ZERO
		if green_area > 0.0 and randf() < HERB_IN_GREEN:
			p = _random_in(_pick_by_area(greens, green_area).pts)
		else:
			p = Vector2(randf_range(-h, h), randf_range(-h, h))
		if ok.call(p):
			put.call("herb", p, 0.0)
			counts.herb += 1
	# Treesilver: bigger parks and woods
	var big = greens.filter(func(a): return _area(a.pts) >= TREESILVER_MIN_AREA)
	for a in big:
		if counts.treesilver >= TREESILVER_MAX:
			break
		for attempt in range(8):
			var p = _random_in(a.pts)
			if ok.call(p):
				put.call("treesilver", p, 0.5)
				counts.treesilver += 1
				break
	# Ore: scrap and rubble along building walls (a step outside the middle of a wall)
	var blds = info.data.buildings.filter(func(b): return b.pts.size() >= 3)
	for i in range(ORE_COUNT * 6):
		if counts.ore >= ORE_COUNT or blds.is_empty():
			break
		var p = _beside_wall(blds.pick_random(), 1.3)
		if p != null and ok.call(p):
			put.call("ore", p, 0.0)
			counts.ore += 1
	# Cliff Orchids: at the foot of the tallest buildings
	var tall = blds.duplicate()
	tall.sort_custom(func(a, b): return a.h > b.h)
	for b in tall.slice(0, ORCHID_COUNT * 4):
		if counts.orchid >= ORCHID_COUNT:
			break
		var p = _beside_wall(b, 1.0)
		if p != null and ok.call(p):
			put.call("orchid", p, 0.5)
			counts.orchid += 1
	if counts.ore + counts.herb == 0:
		ErrorLog.warn("Real Place: no room for any resources on this map")
	print("Real Place resources: %s (quality %d)" % [counts, q])


## A spot just outside the middle of one of a building's walls (null if the wall is tiny).
func _beside_wall(b: Dictionary, out: float):
	var pts = b.pts
	var i = randi() % pts.size()
	var a = pts[i]
	var c = pts[(i + 1) % pts.size()]
	if a.distance_to(c) < 2.0:
		return null
	var mid = (a + c) / 2.0
	var normal = (c - a).normalized().orthogonal()
	var p = mid + normal * out
	if Geometry2D.is_point_in_polygon(p, pts):	# that side was inward: go the other way
		p = mid - normal * out
	return p


func _in_water(p: Vector2) -> bool:
	for a in info.data.areas:
		if a.kind == "water" and Geometry2D.is_point_in_polygon(p, a.pts):
			return true
	return false


func _area(pts: PackedVector2Array) -> float:
	var s = 0.0
	for i in range(pts.size()):
		var a = pts[i]
		var b = pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return abs(s) / 2.0


func _pick_by_area(list: Array, total: float) -> Dictionary:
	var r = randf() * total
	for a in list:
		r -= _area(a.pts)
		if r <= 0.0:
			return a
	return list[-1]


## A random point inside a polygon (tries its bounding box; the middle of the box if unlucky).
func _random_in(pts: PackedVector2Array) -> Vector2:
	var lo = pts[0]
	var hi = pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	for i in range(12):
		var p = Vector2(randf_range(lo.x, hi.x), randf_range(lo.y, hi.y))
		if Geometry2D.is_point_in_polygon(p, pts):
			return p
	return (lo + hi) / 2.0
