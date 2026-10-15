extends RefCounted
## Looks for trees, hills and resource nodes, per world skin ("fantasy", "zombie", "scifi", "darkfantasy").
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
		"darkfantasy":	# black, twisted dead trees; some keep a few blood-red leaves. Ancient ones have glowing eyes.
			var bark = mat(Color(0.09, 0.08, 0.09) if data.ancient else Color(0.16, 0.13, 0.13))
			_mesh(root, _cyl(0.14 * s, 0.4 * s, 3.4 * s, 6), bark, Vector3(0, 1.7 * s, 0), Vector3(0.06 * ((v % 3) - 1), 0, 0.1 * ((v % 3) - 1)))
			var arms = 4 + v % 3
			for i in range(arms):
				var a = TAU * i / arms + v
				fade.append(_mesh(root, _cyl(0.02 * s, 0.1 * s, 1.8 * s, 5), bark,
					Vector3(cos(a) * 0.55 * s, (2.3 + 0.3 * i) * s, sin(a) * 0.55 * s), Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1)))
			if v % 3 == 0:
				var red = [Color(0.38, 0.06, 0.08), Color(0.3, 0.05, 0.07)]
				for i in range(3):
					var a = TAU * i / 3.0 + v
					fade.append(_mesh(root, _sphere(0.45 * s), mat(red[i % 2]), Vector3(cos(a) * 0.9 * s, (3.3 + 0.2 * i) * s, sin(a) * 0.9 * s)))
			if data.ancient:
				for side in [-1, 1]:
					_mesh(root, _sphere(0.09 * s), mat(Color(1.0, 0.25, 0.1), 2.5), Vector3(side * 0.12 * s, 2.2 * s, 0.33 * s))
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
		"darkfantasy":	# barrow mounds: dead grass, ringed by leaning standing stones
			_mesh(root, _cyl(r * 0.45, r, h, 14), mat(Color(0.2, 0.18, 0.18)), Vector3(0, h / 2.0, 0))
			_mesh(root, _cyl(r * 0.5, r * 0.45, 0.25, 14), mat(Color(0.25, 0.24, 0.17)), Vector3(0, h + 0.1, 0))
			var stone = mat(Color(0.3, 0.29, 0.32))
			for i in range(5):
				var a = TAU * i / 5.0 + v
				_mesh(root, _box(Vector3(0.35, 1.4, 0.25) * r * 0.45), stone,
					Vector3(cos(a) * r * 0.75, h * 0.45, sin(a) * r * 0.75), Vector3(0.15 * ((i % 3) - 1), a, 0.12))
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
	if type == "geode":	# caverns only: a glowing crystal cluster in every world
		_mesh(root, _box(Vector3(1.0, 0.6, 0.9)), mat(Color(0.3, 0.28, 0.3)), Vector3(0, 0.3, 0))
		for i in range(4):
			_mesh(root, _cyl(0.0, 0.2, 0.9, 6), mat(Color(0.55, 0.85, 0.95), 1.5), Vector3(-0.3 + 0.2 * i, 0.9, 0.1 * (i % 2)), Vector3(0.3 * (i - 1.5), 0, 0.2))
		return root
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
		"darkfantasy:ore":	# black rock with glowing blood-red crystals
			_mesh(root, _box(Vector3(1.1, 0.8, 1.0)), mat(Color(0.12, 0.11, 0.12)), Vector3(0, 0.4, 0), Vector3(0.1, 0.6, 0.15))
			for i in range(3):
				_mesh(root, _cyl(0.0, 0.18, 0.75, 4), mat(Color(0.85, 0.1, 0.12), 1.2), Vector3(-0.3 + 0.3 * i, 0.9, 0.1 * i), Vector3(0.3 * (i - 1), 0, 0.25 * (1 - i)))
		"darkfantasy:herb":	# ashen leaves, a pale violet bloom
			for i in range(5):
				var a = TAU * i / 5.0
				_mesh(root, _box(Vector3(0.12, 0.05, 0.55)), mat(Color(0.3, 0.32, 0.28)), Vector3(cos(a) * 0.25, 0.2, sin(a) * 0.25), Vector3(0.5, -a + PI / 2.0, 0))
			_mesh(root, _cyl(0.03, 0.03, 0.6), mat(Color(0.22, 0.24, 0.2)), Vector3(0, 0.3, 0))
			_mesh(root, _sphere(0.15), mat(Color(0.7, 0.5, 1.0), 0.9), Vector3(0, 0.65, 0))
		"darkfantasy:treesilver":	# a bone-white rib cage jutting from the ground
			for i in range(4):
				_mesh(root, _cyl(0.03, 0.06, 1.1, 5), mat(Color(0.88, 0.85, 0.76), 0.5), Vector3(-0.3 + 0.2 * i, 0.5, 0), Vector3(0, 0, 0.35))
			_mesh(root, _box(Vector3(0.9, 0.08, 0.1)), mat(Color(0.8, 0.77, 0.68)), Vector3(0, 0.1, 0))
		"darkfantasy:orchid":	# a blood-red bloom with an ember heart
			_mesh(root, _cyl(0.03, 0.03, 0.5), mat(Color(0.18, 0.2, 0.16)), Vector3(0, 0.25, 0))
			for i in range(5):
				var a = TAU * i / 5.0
				_mesh(root, _sphere(0.12, 0.08), mat(Color(0.7, 0.05, 0.1), 0.7), Vector3(cos(a) * 0.15, 0.55, sin(a) * 0.15))
			_mesh(root, _sphere(0.07), mat(Color(1.0, 0.45, 0.1), 1.5), Vector3(0, 0.57, 0))
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


# ======================= CAMPS AND VALLEYS (pack sites) =======================
## A hut, about 3 x 3 (collision: a 3 x 2.4 x 3 box). data: {v = variant}
##   fantasy: log hut with a thatched roof | zombie: scrap shack | scifi: dome pod
static func hut(style: String, data: Dictionary) -> Node3D:
	var root = Node3D.new()
	var v = int(data.get("v", 0))
	match style:
		"zombie":
			var sheet = [Color(0.45, 0.42, 0.4), Color(0.5, 0.33, 0.22), Color(0.38, 0.4, 0.42)]
			_mesh(root, _box(Vector3(3.0, 2.2, 3.0)), mat(sheet[v % 3]), Vector3(0, 1.1, 0))
			_mesh(root, _box(Vector3(3.4, 0.12, 3.4)), mat(sheet[(v + 1) % 3]), Vector3(0, 2.35, 0), Vector3(0.12, 0, 0.05))
			_mesh(root, _box(Vector3(0.9, 1.5, 0.08)), mat(Color(0.2, 0.18, 0.16)), Vector3(0, 0.75, 1.52))
		"scifi":
			_mesh(root, _cyl(1.6, 1.6, 0.6, 12), mat(Color(0.35, 0.38, 0.5)), Vector3(0, 0.3, 0))
			_mesh(root, _sphere(1.6, 2.6), mat(Color(0.55, 0.6, 0.75)), Vector3(0, 0.9, 0))
			_mesh(root, _box(Vector3(0.8, 0.8, 0.1)), mat(Color(0.3, 0.9, 1.0), 1.2), Vector3(0, 0.9, 1.5))
		"darkfantasy":	# a black stone crypt with a steep roof and a glowing red door
			var stone = [Color(0.2, 0.19, 0.22), Color(0.24, 0.22, 0.25), Color(0.17, 0.16, 0.18)]
			_mesh(root, _box(Vector3(3.0, 2.2, 3.0)), mat(stone[v % 3]), Vector3(0, 1.1, 0))
			_mesh(root, _cyl(0.0, 2.3, 2.4, 4), mat(Color(0.12, 0.1, 0.12)), Vector3(0, 3.4, 0), Vector3(0, PI / 4.0, 0))
			_mesh(root, _box(Vector3(0.9, 1.5, 0.08)), mat(Color(0.75, 0.1, 0.08), 1.2), Vector3(0, 0.75, 1.52))
		_:
			var wood = [Color(0.45, 0.3, 0.18), Color(0.5, 0.35, 0.2), Color(0.4, 0.27, 0.16)]
			_mesh(root, _box(Vector3(3.0, 2.0, 3.0)), mat(wood[v % 3]), Vector3(0, 1.0, 0))
			_mesh(root, _cyl(0.0, 2.4, 1.6, 4), mat(Color(0.72, 0.6, 0.32)), Vector3(0, 2.8, 0), Vector3(0, PI / 4.0, 0))
			_mesh(root, _box(Vector3(0.9, 1.4, 0.08)), mat(Color(0.2, 0.13, 0.08)), Vector3(0, 0.7, 1.52))
	return root


## The fire / beacon in the middle of a camp (no collision).
static func campfire(style: String) -> Node3D:
	var root = Node3D.new()
	match style:
		"zombie":
			_mesh(root, _cyl(0.5, 0.5, 0.9, 10), mat(Color(0.35, 0.3, 0.28)), Vector3(0, 0.45, 0))
			_mesh(root, _sphere(0.45, 0.5), mat(Color(1.0, 0.5, 0.15), 2.0), Vector3(0, 0.95, 0))
		"scifi":
			_mesh(root, _cyl(0.15, 0.3, 2.0, 6), mat(Color(0.3, 0.32, 0.42)), Vector3(0, 1.0, 0))
			_mesh(root, _sphere(0.35), mat(Color(0.3, 0.95, 1.0), 2.0), Vector3(0, 2.2, 0))
		"darkfantasy":	# a ring of gray stones around green witchfire
			var ring = mat(Color(0.28, 0.27, 0.3))
			for i in range(6):
				var a = TAU * i / 6.0
				_mesh(root, _box(Vector3(0.35, 0.25, 0.35)), ring, Vector3(cos(a) * 0.6, 0.12, sin(a) * 0.6), Vector3(0, a, 0))
			_mesh(root, _cyl(0.0, 0.45, 0.9, 6), mat(Color(0.35, 1.0, 0.45), 2.0), Vector3(0, 0.45, 0))
		_:
			var stone = mat(Color(0.45, 0.43, 0.4))
			for i in range(6):
				var a = TAU * i / 6.0
				_mesh(root, _box(Vector3(0.35, 0.25, 0.35)), stone, Vector3(cos(a) * 0.6, 0.12, sin(a) * 0.6), Vector3(0, a, 0))
			_mesh(root, _cyl(0.0, 0.45, 0.8, 6), mat(Color(1.0, 0.55, 0.15), 2.0), Vector3(0, 0.4, 0))
	return root


## A mountain: the walls of a valley. data: {m = base radius, h = height, v = variant}
## Collision: a cylinder of radius m * 0.75.
##   fantasy: rocky peak with a snow cap | zombie: ruined building | scifi: crystal spire
static func mountain(style: String, data: Dictionary) -> Node3D:
	var root = Node3D.new()
	var m = data.m
	var h = data.h
	var v = int(data.get("v", 0))
	match style:
		"zombie":	# a ruined city block: concrete tower, dark window rows, broken roof, rubble
			var walls = [Color(0.42, 0.4, 0.38), Color(0.5, 0.44, 0.38), Color(0.36, 0.37, 0.4)][v % 3]
			var w = m * 1.2	# square footprint fits the round collision (radius m * 0.75)
			var turn = Vector3(0, v * 0.37, 0)
			var bld = Node3D.new()
			bld.rotation = turn
			root.add_child(bld)
			_mesh(bld, _box(Vector3(w, h, w * 0.9)), mat(walls), Vector3(0, h / 2.0, 0))
			var floors = int(h / 2.2)
			for f in range(floors):	# one dark band per floor wraps all four sides: the windows
				_mesh(bld, _box(Vector3(w + 0.06, 0.6, w * 0.9 + 0.06)), mat(Color(0.08, 0.08, 0.09)), Vector3(0, 1.4 + f * 2.2, 0))
			# broken roof: a tilted slab of the top floor, sliding off one corner
			_mesh(bld, _box(Vector3(w * 0.6, 0.4, w * 0.5)), mat(walls.darkened(0.15)), Vector3(w * 0.2, h + 0.1, w * 0.15), Vector3(0.25, 0, -0.35))
			if v % 2 == 0:	# a rusty rooftop water tank on some
				_mesh(bld, _cyl(w * 0.15, w * 0.15, 1.2, 8), mat(Color(0.45, 0.28, 0.18)), Vector3(-w * 0.25, h + 0.6, -w * 0.2))
			for i in range(3):	# rubble heaped at the base
				var a = TAU * i / 3.0 + v
				_mesh(root, _box(Vector3(m * 0.35, m * 0.2, m * 0.3)), mat(Color(0.35, 0.33, 0.31)), Vector3(cos(a) * m * 0.7, m * 0.08, sin(a) * m * 0.7), Vector3(0.3, a, 0.2))
		"scifi":
			_mesh(root, _cyl(0.0, m, h, 6), mat(Color(0.32, 0.36, 0.5)), Vector3(0, h / 2.0, 0))
			_mesh(root, _cyl(0.0, m * 0.35, h * 0.6, 6), mat(Color(0.4, 0.75, 1.0), 0.6), Vector3(m * 0.45, h * 0.3, m * 0.2), Vector3(0, 0, -0.25))
		"darkfantasy":	# jagged black peak with a smoldering red top
			_mesh(root, _cyl(m * 0.05, m, h, 7), mat(Color(0.14, 0.13, 0.15)), Vector3(0, h / 2.0, 0), Vector3(0, v, 0))
			_mesh(root, _cyl(0.0, m * 0.22, h * 0.2, 7), mat(Color(0.8, 0.2, 0.08), 1.4), Vector3(0, h * 0.9, 0))
			_mesh(root, _cyl(0.0, m * 0.35, h * 0.55, 5), mat(Color(0.18, 0.17, 0.19)), Vector3(m * 0.5, h * 0.27, m * 0.15), Vector3(0, 0, -0.2))
		_:
			_mesh(root, _cyl(m * 0.08, m, h, 9), mat(Color(0.42, 0.4, 0.38)), Vector3(0, h / 2.0, 0), Vector3(0, v, 0))
			_mesh(root, _cyl(0.0, m * 0.3, h * 0.25, 9), mat(Color(0.92, 0.94, 0.97)), Vector3(0, h * 0.88, 0))
			_mesh(root, _cyl(m * 0.6, m * 1.05, h * 0.18, 9), mat(Color(0.32, 0.45, 0.26)), Vector3(0, h * 0.09, 0))
	return root
