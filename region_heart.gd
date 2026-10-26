extends Node3D
## The heart of a region (regions.gd): a set piece in the region's own style around a glowing BEACON,
## where the region's boss waits (zone_features.gd wakes it). Built only while someone is near, and
## always the same for the same region (seeded), so every player sees the same place.
## Four ways in (north, east, south, west) always stay open.
##   forest: a ring of old trees     rolling_hills: a ring of hills     ruins: broken walls
##   rails: a little rail yard       river: a moat of shallow water     open_field: a fenced farmstead

const PROPS = preload("res://props.gd")
const LOW_WALL_SCENE = preload("res://LowWall.tscn")
const SOLID_WALL_SCENE = preload("res://SolidWall.tscn")
const DITCH_SCENE = preload("res://Ditch.tscn")
const GOLD = Color(1.0, 0.82, 0.3)
const BEACON_HEIGHT = 16.0	# taller than the fog (fog_of_war HEIGHT 6.5), so it pokes through
const GAP = 0.32			# radians kept open around each way in

var region := {}
var zone_path := ""
var freed := false
var _rng := RandomNumberGenerator.new()
var _style := "fantasy"
var _pillar: MeshInstance3D
var _orb: MeshInstance3D
var _ring: MeshInstance3D
var _title: Label3D


func _ready():
	add_to_group("region_heart")
	_rng.seed = hash(zone_path + region.id + "heart")
	_style = SkinManager.props_style()
	_beacon()
	match region.template:
		"forest": _forest()
		"rolling_hills": _hills()
		"ruins": _ruins()
		"rails": _rails()
		"river": _moat()
		"open_field": _farmstead()
		_:
			ErrorLog.warn("Region heart: no set piece for template '%s' (%s)" % [region.template, region.name])
	set_freed(freed)


## The region boss is down: the beacon burns gold.
func set_freed(on: bool):
	freed = on
	var c = GOLD if on else region.color
	_pillar.material_override = _glow(c, 2.2)
	_orb.material_override = _glow(c, 3.0)
	_ring.material_override = _glow(Color(c, 0.35), 1.0, true)
	_title.text = region.name + ("\n(freed)" if on else "")
	_title.modulate = c.lightened(0.3)


func _process(delta):
	_orb.position.y = BEACON_HEIGHT + 0.6 + sin(Time.get_ticks_msec() / 500.0) * 0.4
	_orb.rotation.y += delta


# ---------------- The beacon ----------------

func _beacon():
	var base = StaticBody3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(3.0, 1.2, 3.0)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.6
	base.add_child(col)
	var plinth = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(3.0, 1.2, 3.0)
	plinth.mesh = bm
	plinth.position.y = 0.6
	plinth.material_override = SkinManager.material("heart_plinth", Color(0.3, 0.29, 0.32))
	base.add_child(plinth)
	add_child(base)
	_pillar = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.25
	cyl.bottom_radius = 0.55
	cyl.height = BEACON_HEIGHT
	_pillar.mesh = cyl
	_pillar.position.y = BEACON_HEIGHT / 2.0 + 1.2
	add_child(_pillar)
	_orb = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	_orb.mesh = sm
	add_child(_orb)
	_ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 6.0
	tm.outer_radius = 6.6
	_ring.mesh = tm
	_ring.position.y = 0.08
	_ring.scale.y = 0.05
	add_child(_ring)
	_title = Label3D.new()
	_title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_title.no_depth_test = true
	_title.font_size = 56
	_title.pixel_size = 0.014
	_title.outline_size = 14
	_title.position.y = 7.0
	add_child(_title)


func _glow(c: Color, energy: float, see_through := false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = energy
	if see_through:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ---------------- Helpers ----------------

## Spots around the beacon at radius r_min..r_max, never in the four ways in.
func _around(count: int, r_min: float, r_max: float) -> Array:
	var out = []
	var tries = 0
	while out.size() < count and tries < count * 6:
		tries += 1
		var a = _rng.randf() * TAU
		if _in_gap(a):
			continue
		out.append(Vector3(cos(a), 0, sin(a)) * _rng.randf_range(r_min, r_max))
	return out


func _in_gap(a: float) -> bool:
	for k in 4:
		if absf(angle_difference(a, k * PI / 2.0)) < GAP:
			return true
	return false


func _tree(p: Vector3, ancient: bool):
	var s = _rng.randf_range(1.6, 2.1) if ancient else _rng.randf_range(0.9, 1.3)
	var body = StaticBody3D.new()
	var look = PROPS.tree(_style, {s = s, ancient = ancient, v = _rng.randi() % 100})
	body.add_child(look.root)
	var shape = CylinderShape3D.new()	# only the trunk blocks you
	shape.radius = 0.4 * s
	shape.height = 3.0 * s
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5 * s
	body.add_child(col)
	body.position = p
	add_child(body)


func _hill(p: Vector3, r: float, h: float):
	var data = {r = r, h = h, v = _rng.randi() % 100}
	var body = StaticBody3D.new()
	body.add_to_group("hill")	# slow to climb, like any hill
	body.add_child(PROPS.hill(_style, data))
	var cone = CylinderMesh.new()
	cone.bottom_radius = r * 0.9
	cone.top_radius = maxf(0.3, r * 0.9 - h * 1.3)
	cone.height = h
	cone.radial_segments = 12
	cone.rings = 1
	var col = CollisionShape3D.new()
	col.shape = cone.create_convex_shape()
	col.position.y = h / 2.0
	body.add_child(col)
	body.position = p
	add_child(body)


## A wall from a to b (local). type: "solid", "low" or "fence".
func _wall(type: String, a: Vector3, b: Vector3):
	var piece = (SOLID_WALL_SCENE if type == "solid" else LOW_WALL_SCENE).instantiate()
	var d = b - a
	piece.length = d.length()
	add_child(piece)
	if type == "fence":
		var mi = piece.get_node("MeshInstance3D")
		mi.mesh.size = Vector3(d.length(), 1.1, 0.2)
		mi.material_override = SkinManager.material("fence", Color(0.45, 0.32, 0.2))
	piece.position = (a + b) / 2.0
	piece.rotation.y = -atan2(d.z, d.x)


## A wall bent around the beacon: pieces from angle a0 to a1 at radius r.
func _arc(type: String, r: float, a0: float, a1: float, piece_len := 6.0):
	var steps = maxi(1, ceili(r * absf(a1 - a0) / piece_len))
	for i in steps:
		var t0 = a0 + (a1 - a0) * i / steps
		var t1 = a0 + (a1 - a0) * (i + 1) / steps
		_wall(type, Vector3(cos(t0), 0, sin(t0)) * r, Vector3(cos(t1), 0, sin(t1)) * r)


## The four arcs between the ways in.
func _ring_wall(type: String, r: float, broken := 0.0):
	for k in 4:
		var a0 = k * PI / 2.0 + GAP
		var a1 = (k + 1) * PI / 2.0 - GAP
		if broken > 0.0:	# fallen sections
			var mid = (a0 + a1) / 2.0
			_arc(type, r, a0, mid - broken * _rng.randf())
			_arc(type, r, mid + broken * _rng.randf(), a1)
		else:
			_arc(type, r, a0, a1)


func _block(size: Vector3, p: Vector3, c: Color, yaw := 0.0):
	var body = StaticBody3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	var col = CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = SkinManager.material("heart_block_%s" % c.to_html(false), c)
	body.add_child(mi)
	body.position = p + Vector3(0, size.y / 2.0, 0)
	body.rotation.y = yaw
	add_child(body)


func _deco(size: Vector3, p: Vector3, c: Color, yaw := 0.0):
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = SkinManager.material("heart_deco_%s" % c.to_html(false), c)
	mi.position = p
	mi.rotation.y = yaw
	add_child(mi)


# ---------------- The set pieces ----------------

func _forest():
	for p in _around(_rng.randi_range(18, 26), 13.0, 34.0):
		_tree(p, false)
	for p in _around(3, 18.0, 26.0):
		_tree(p, true)


func _hills():
	for p in _around(_rng.randi_range(6, 8), 20.0, 30.0):
		_hill(p, _rng.randf_range(4.5, 7.5), _rng.randf_range(2.0, 3.5))


func _ruins():
	_ring_wall("solid", 20.0, 0.35)
	_ring_wall("low", 30.0, 0.5)
	for p in _around(8, 10.0, 34.0):	# rubble
		_block(Vector3(_rng.randf_range(1.0, 2.2), _rng.randf_range(0.5, 1.2), _rng.randf_range(1.0, 2.2)), p, Color(0.4, 0.38, 0.37), _rng.randf() * TAU)


func _rails():
	var bed = Color(0.42, 0.36, 0.3)
	var rail = Color(0.25, 0.25, 0.27)
	for z in [-14.0, 14.0]:	# two tracks passing either side of the beacon
		_deco(Vector3(76, 0.04, 2.6), Vector3(0, 0.19, z), bed)
		_deco(Vector3(76, 0.1, 0.15), Vector3(0, 0.24, z + 0.7), rail)
		_deco(Vector3(76, 0.1, 0.15), Vector3(0, 0.24, z - 0.7), rail)
		var x = -30.0
		while x < 30.0:	# a train of wagons, with gaps to walk through
			if _rng.randf() < 0.6 and absf(x) > 5.0:
				_block(Vector3(8.0, 2.6, 2.8), Vector3(x, 0, z), Color(0.45, 0.3, 0.22) if _rng.randf() < 0.5 else Color(0.32, 0.36, 0.4))
			x += 10.0


func _moat():
	for k in 4:
		var a0 = k * PI / 2.0 + GAP
		var a1 = (k + 1) * PI / 2.0 - GAP
		var steps = 6
		for i in steps:
			var a = lerpf(a0, a1, (i + 0.5) / steps)
			var d = DITCH_SCENE.instantiate()
			d.size = Vector2(7.0, 6.0)
			d.water = true
			add_child(d)
			d.position = Vector3(cos(a), 0, sin(a)) * 18.0
			d.rotation.y = -a
	for p in _around(10, 24.0, 34.0):	# reeds
		_deco(Vector3(0.3, 1.6, 0.3), p + Vector3(0, 0.8, 0), Color(0.35, 0.5, 0.25))


func _farmstead():
	_ring_wall("fence", 26.0)
	for p in _around(3, 12.0, 18.0):
		var hut = StaticBody3D.new()
		hut.add_child(PROPS.hut(_style, {v = _rng.randi() % 100}))
		var shape = BoxShape3D.new()
		shape.size = Vector3(3.0, 2.2, 3.0)
		var col = CollisionShape3D.new()
		col.shape = shape
		col.position.y = 1.1
		hut.add_child(col)
		hut.position = p
		hut.rotation.y = atan2(p.x, p.z)	# doors face the beacon
		add_child(hut)
	var crop = [Color(0.72, 0.62, 0.25), Color(0.35, 0.55, 0.22)][_rng.randi() % 2]
	for z in range(-3, 4):	# a crop patch outside the fence (walk-through)
		_deco(Vector3(14, 0.35, 1.1), Vector3(36, 0.3, z * 3.0), crop)
