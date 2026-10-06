extends RefCounted
## Looks for trees, hills and resource nodes, per world skin ("fantasy", "zombie", "scifi").
## Only the LOOK changes. Collision, gameplay and resource types are the same in every world.
## Every function returns a plain Node3D full of meshes; the caller adds collision.

static var _mats = {}


static func mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var key = "%s|%s" % [c.to_html(), glow]
	if not _mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


static func _mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(sz: Vector3) -> BoxMesh:
	var b = BoxMesh.new()
	b.size = sz
	return b


static func _cyl(top: float, bottom: float, h: float, seg := 10) -> CylinderMesh:
	var c = CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c


static func _sphere(r: float, h := -1.0) -> SphereMesh:
	var s = SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 12
	s.rings = 6
	return s


# ======================= TREES =======================
## data: {s = size, ancient = bool, v = variant number}
## Returns {root = Node3D, fade = [meshes that turn see-through when they hide the player]}
static func tree(style: String, data: Dictionary) -> Dictionary:
	var root = Node3D.new()
	var s = data.s
	var v = int(data.get("v", 0))
	var fade = []
	match style:
		"zombie":	# dead, bare trees with crooked branches
			var bark = mat(Color(0.22, 0.2, 0.19) if data.ancient else Color(0.3, 0.27, 0.24))
			_mesh(root, _cyl(0.18 * s, 0.32 * s, 3.2 * s, 7), bark, Vector3(0, 1.6 * s, 0), Vector3(0, 0, 0.08 * ((v % 3) - 1)))
			for i in range(3 + v % 3):
				var a = TAU * i / (3 + v % 3) + v
				var b = _mesh(root, _box(Vector3(0.12 * s, 1.4 * s, 0.12 * s)), bark,
					Vector3(cos(a) * 0.45 * s, (2.0 + 0.35 * i) * s, sin(a) * 0.45 * s), Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9))
				fade.append(b)
		"scifi":	# alien spires: tall dark stalk, glowing bulb, a couple of rings
			var stalk = mat(Color(0.2, 0.17, 0.3) if data.ancient else Color(0.25, 0.22, 0.38))
			_mesh(root, _cyl(0.12 * s, 0.35 * s, 4.0 * s, 6), stalk, Vector3(0, 2.0 * s, 0))
			var glow = Color(0.3, 0.95, 1.0) if v % 2 == 0 else Color(0.85, 0.4, 1.0)
			fade.append(_mesh(root, _sphere(0.6 * s), mat(glow, 1.5), Vector3(0, 4.2 * s, 0)))
			for i in range(2):
				fade.append(_mesh(root, _cyl(0.55 * s, 0.55 * s, 0.08, 16), mat(glow * 0.7, 0.6), Vector3(0, (2.6 + i * 0.8) * s, 0)))
		_:	# fantasy: mix of round oaks and tall pines; ancient trees are huge dark oaks
			var bark = mat(Color(0.3, 0.22, 0.2) if data.ancient else Color(0.42, 0.29, 0.17))
			_mesh(root, _cyl(0.25 * s, 0.38 * s, 2.6 * s, 8), bark, Vector3(0, 1.3 * s, 0))
			if data.ancient or v % 2 == 0:
				var leaves = [Color(0.16, 0.38, 0.2), Color(0.2, 0.46, 0.22), Color(0.25, 0.52, 0.24)]
				if data.ancient:
					leaves = [Color(0.12, 0.3, 0.2), Color(0.15, 0.34, 0.24), Color(0.18, 0.4, 0.26)]
				var spots = [Vector3(0, 3.2, 0), Vector3(0.7, 2.8, 0.3), Vector3(-0.6, 2.9, -0.4), Vector3(0.1, 3.0, 0.7)]
				for i in range(spots.size()):
					fade.append(_mesh(root, _sphere((1.0 - 0.1 * i) * s), mat(leaves[(i + v) % 3]), spots[i] * s))
			else:
				var pine = [Color(0.12, 0.35, 0.22), Color(0.14, 0.4, 0.25), Color(0.17, 0.45, 0.28)]
				for i in range(3):
					fade.append(_mesh(root, _cyl(0.0, (1.4 - 0.35 * i) * s, 1.6 * s, 10), mat(pine[i]), Vector3(0, (2.2 + 0.9 * i) * s, 0)))
	return {root = root, fade = fade}


# ======================= HILLS =======================
## data: {r = radius, h = height, v = variant}. Collision is a cylinder of radius r*0.8.
static func hill(style: String, data: Dictionary) -> Node3D:
	var root = Node3D.new()
	var r = data.r
	var h = data.h
	var v = int(data.get("v", 0))
	match style:
		"zombie":	# rubble piles: broken concrete and rusted junk
			var colors = [Color(0.45, 0.44, 0.42), Color(0.38, 0.36, 0.34), Color(0.42, 0.3, 0.22), Color(0.3, 0.3, 0.32)]
			for i in range(7):
				var a = TAU * i / 7.0 + v
				var d = r * (0.25 + 0.5 * float((i * 37 + v) % 10) / 10.0)
				var sz = Vector3(r * 0.5, h * (0.4 + 0.12 * (i % 4)), r * 0.35)
				_mesh(root, _box(sz), mat(colors[(i + v) % 4]), Vector3(cos(a) * d, sz.y / 2.0, sin(a) * d), Vector3(0.15 * (i % 3), a, 0.1))
			_mesh(root, _cyl(r * 0.45, r * 0.85, h * 0.5, 8), mat(Color(0.36, 0.34, 0.32)), Vector3(0, h * 0.25, 0))
		"scifi":	# hexagonal mesas with a lighter top
			_mesh(root, _cyl(r * 0.7, r * 0.85, h, 6), mat(Color(0.3, 0.34, 0.45)), Vector3(0, h / 2.0, 0))
			_mesh(root, _cyl(r * 0.68, r * 0.7, 0.12, 6), mat(Color(0.5, 0.56, 0.68)), Vector3(0, h + 0.06, 0))
			_mesh(root, _cyl(r * 0.3, r * 0.4, h * 0.6, 6), mat(Color(0.28, 0.3, 0.4)), Vector3(r * 0.6, h * 0.3, -r * 0.3))
		_:	# fantasy: grassy, rocky mound with boulders
			_mesh(root, _cyl(r * 0.45, r, h, 14), mat(Color(0.43, 0.39, 0.32)), Vector3(0, h / 2.0, 0))
			_mesh(root, _cyl(r * 0.5, r * 0.45, 0.25, 14), mat(Color(0.3, 0.5, 0.25)), Vector3(0, h + 0.1, 0))
			var rock = mat(Color(0.5, 0.48, 0.45))
			for i in range(3 + v % 2):
				var a = TAU * i / 3.0 + v
				_mesh(root, _box(Vector3(0.9, 0.8, 1.1) * (0.8 + 0.2 * (i % 2)) * r * 0.3), rock,
					Vector3(cos(a) * r * 0.7, h * 0.35, sin(a) * r * 0.7), Vector3(0.3, a, 0.2))
	return root


# ======================= RESOURCE NODES =======================
## Same four resource types in every world, different looks:
##   ore         fantasy: rock with glowing copper crystals | zombie: scrap heap | scifi: metal crystal cluster
##   herb        fantasy: leafy herb with a flower | zombie: weedy tuft | scifi: glowing moss
##   treesilver  fantasy: silver vein on a trunk | zombie: supply crate | scifi: glowing fiber strand
##   orchid      fantasy: pink orchid | zombie: glowing mold | scifi: plasma crystal
static func node(style: String, type: String) -> Node3D:
	var root = Node3D.new()
	match style + ":" + type:
		"fantasy:ore":
			_mesh(root, _box(Vector3(1.1, 0.8, 1.0)), mat(Color(0.35, 0.33, 0.32)), Vector3(0, 0.4, 0), Vector3(0.1, 0.6, 0.15))
			for i in range(3):
				_mesh(root, _cyl(0.0, 0.18, 0.7, 4), mat(Color(0.95, 0.55, 0.25), 0.8), Vector3(-0.3 + 0.3 * i, 0.9, 0.1 * i), Vector3(0.3 * (i - 1), 0, 0.25 * (1 - i)))
		"fantasy:herb":
			for i in range(5):
				var a = TAU * i / 5.0
				_mesh(root, _box(Vector3(0.12, 0.05, 0.55)), mat(Color(0.35, 0.7, 0.3)), Vector3(cos(a) * 0.25, 0.2, sin(a) * 0.25), Vector3(0.5, -a + PI / 2.0, 0))
			_mesh(root, _cyl(0.03, 0.03, 0.6), mat(Color(0.3, 0.55, 0.25)), Vector3(0, 0.3, 0))
			_mesh(root, _sphere(0.15), mat(Color(1.0, 0.9, 0.3), 0.6), Vector3(0, 0.65, 0))
		"fantasy:treesilver":
			_mesh(root, _box(Vector3(0.12, 1.2, 0.08)), mat(Color(0.85, 0.9, 1.0), 1.2), Vector3(0, 1.1, 0))
			_mesh(root, _box(Vector3(0.08, 0.5, 0.06)), mat(Color(0.85, 0.9, 1.0), 1.2), Vector3(0.12, 1.5, 0), Vector3(0, 0, 0.5))
		"fantasy:orchid":
			_mesh(root, _cyl(0.03, 0.03, 0.5), mat(Color(0.3, 0.55, 0.25)), Vector3(0, 0.25, 0))
			for i in range(5):
				var a = TAU * i / 5.0
				_mesh(root, _sphere(0.12, 0.08), mat(Color(0.95, 0.5, 0.85), 0.7), Vector3(cos(a) * 0.15, 0.55, sin(a) * 0.15))
			_mesh(root, _sphere(0.07), mat(Color(1, 1, 0.6), 0.8), Vector3(0, 0.57, 0))
		"zombie:ore":
			var rust = [Color(0.5, 0.3, 0.18), Color(0.4, 0.38, 0.36), Color(0.55, 0.36, 0.2)]
			for i in range(4):
				_mesh(root, _box(Vector3(0.6, 0.3, 0.4)), mat(rust[i % 3]), Vector3(-0.2 + 0.15 * i, 0.15 + 0.2 * (i % 2), 0.1 * (i % 3)), Vector3(0.2 * i, 0.7 * i, 0.1))
			_mesh(root, _cyl(0.08, 0.08, 1.0), mat(Color(0.45, 0.42, 0.4)), Vector3(0.2, 0.4, 0), Vector3(0, 0, 1.1))
		"zombie:herb":
			for i in range(6):
				var a = TAU * i / 6.0
				_mesh(root, _box(Vector3(0.05, 0.6, 0.05)), mat(Color(0.55, 0.6, 0.3)), Vector3(cos(a) * 0.12, 0.3, sin(a) * 0.12), Vector3(cos(a) * 0.4, 0, sin(a) * 0.4))
			_mesh(root, _sphere(0.1), mat(Color(0.9, 0.9, 0.85)), Vector3(0, 0.62, 0))
		"zombie:treesilver":
			_mesh(root, _box(Vector3(0.7, 0.5, 0.5)), mat(Color(0.45, 0.4, 0.25)), Vector3(0, 0.25, 0))
			_mesh(root, _box(Vector3(0.72, 0.08, 0.52)), mat(Color(0.8, 0.2, 0.15), 0.4), Vector3(0, 0.35, 0))
		"zombie:orchid":
			for i in range(4):
				_mesh(root, _sphere(0.2, 0.12), mat(Color(0.7, 1.0, 0.6), 0.9), Vector3(-0.2 + 0.15 * i, 0.08, 0.1 * (i % 2)))
		"scifi:ore":
			var metal = [Color(0.55, 0.6, 0.7), Color(0.45, 0.5, 0.6), Color(0.65, 0.7, 0.8)]
			for i in range(4):
				_mesh(root, _cyl(0.0, 0.2, 0.9 - 0.15 * i, 4), mat(metal[i % 3], 0.2), Vector3(-0.25 + 0.17 * i, 0.4, 0.12 * (i % 2)), Vector3(0.25 * (i - 1.5), 0, 0.2 * (1.5 - i)))
		"scifi:herb":
			_mesh(root, _cyl(0.45, 0.5, 0.08, 12), mat(Color(0.3, 0.9, 0.55), 0.8), Vector3(0, 0.05, 0))
			_mesh(root, _sphere(0.12), mat(Color(0.5, 1.0, 0.7), 1.0), Vector3(0.15, 0.15, 0.1))
		"scifi:treesilver":
			_mesh(root, _cyl(0.05, 0.05, 1.6), mat(Color(0.4, 1.0, 1.0), 1.5), Vector3(0, 1.0, 0), Vector3(0, 0, 0.15))
		"scifi:orchid":
			_mesh(root, _cyl(0.0, 0.25, 0.8, 5), mat(Color(0.3, 0.85, 1.0), 1.4), Vector3(0, 0.4, 0))
			_mesh(root, _cyl(0.0, 0.15, 0.5, 5), mat(Color(0.3, 0.85, 1.0), 1.4), Vector3(0.2, 0.25, 0.1), Vector3(0, 0, -0.4))
		_:	# unknown style: simple colored block
			_mesh(root, _box(Vector3(0.8, 0.6, 0.8)), mat(GameState.RESOURCE_INFO[type].color), Vector3(0, 0.3, 0))
	return root
