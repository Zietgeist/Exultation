extends RefCounted
## A knight body for the player, built from simple shapes with textures made in code
## (hammered steel, chainmail, woven cloth). No image files needed.
## A skin turns it on with a "player_model" block, e.g.:
##
##   "player_model": {"type": "knight", "armor": "#3a3a42", "trim": "#8a6a2a",
##                    "cloth": "#5a0f14", "cape": "#2a0a0e", "plume": "#7a0f16", "eyes": "#ff3a1a"}
##
##   armor  steel color        trim   gold/brass edges, shield rim, sword guard
##   cloth  tabard and shield  cape   the cape on the back
##   plume  feather on the helm   eyes  glow in the visor slit (leave out for a plain dark slit)
##   glow   strength of a faint lantern light around the knight (0 = off, default 0.6)
##   glow_color   its color
##
## Size matches the old capsule (feet at y = -1, top of the helm near y = 1), facing -Z.

static var _mats = {}
static var _tex = {}


static func build(look: Dictionary) -> Node3D:
	var armor = _c(look, "armor", Color(0.62, 0.64, 0.68))
	var trim = _c(look, "trim", Color(0.75, 0.6, 0.25))
	var cloth = _c(look, "cloth", Color(0.15, 0.25, 0.6))
	var cape_c = _c(look, "cape", cloth.darkened(0.3))
	var plume = _c(look, "plume", cloth)
	var steel = _metal(armor)
	var dark_steel = _metal(armor.darkened(0.35))
	var gold = _metal(trim, 0.3)
	var mail = _chain(armor.darkened(0.15))
	var tabard = _cloth(cloth)
	var cape = _cloth(cape_c)
	var leather = _cloth(Color(0.28, 0.18, 0.1))
	var root = Node3D.new()
	root.name = "Knight"

	# Legs: greaves and pointed boots (sabatons)
	for x in [-0.15, 0.15]:
		_add(root, _cyl(0.1, 0.12, 0.72), steel, Vector3(x, -0.6, 0))
		_add(root, _sphere(0.12, 0.16), dark_steel, Vector3(x, -0.36, -0.06))	# knee cop
		_add(root, _box(Vector3(0.18, 0.12, 0.34)), dark_steel, Vector3(x, -0.94, -0.06))
	# Chainmail skirt and belt
	_add(root, _cyl(0.3, 0.37, 0.4), mail, Vector3(0, -0.22, 0))
	_add(root, _cyl(0.31, 0.31, 0.07), leather, Vector3(0, -0.04, 0))
	_add(root, _box(Vector3(0.09, 0.08, 0.03)), gold, Vector3(0, -0.04, -0.31))	# buckle
	# Breastplate with a center ridge
	_add(root, _cyl(0.33, 0.28, 0.58), steel, Vector3(0, 0.25, 0))
	_add(root, _box(Vector3(0.05, 0.5, 0.05)), steel, Vector3(0, 0.27, -0.3), Vector3(0, PI / 4.0, 0))
	# Tabard over the armor, with a simple cross in the trim color
	_add(root, _box(Vector3(0.4, 0.95, 0.025)), tabard, Vector3(0, 0.02, -0.315))
	_add(root, _box(Vector3(0.36, 0.5, 0.025)), tabard, Vector3(0, 0.08, 0.3))
	_add(root, _box(Vector3(0.07, 0.36, 0.01)), gold, Vector3(0, 0.12, -0.333))
	_add(root, _box(Vector3(0.24, 0.07, 0.01)), gold, Vector3(0, 0.18, -0.333))
	# Gorget (neck), shoulders, arms and gauntlets
	_add(root, _cyl(0.15, 0.2, 0.1), dark_steel, Vector3(0, 0.56, 0))
	for side in [-1, 1]:
		_add(root, _sphere(0.2, 0.22), steel, Vector3(side * 0.36, 0.48, 0))
		_add(root, _cyl(0.21, 0.21, 0.03), gold, Vector3(side * 0.36, 0.44, 0))
		_add(root, _cyl(0.08, 0.09, 0.48), mail, Vector3(side * 0.42, 0.18, 0))
		_add(root, _cyl(0.09, 0.1, 0.22), steel, Vector3(side * 0.42, 0.06, -0.02))	# vambrace
		_add(root, _box(Vector3(0.13, 0.14, 0.15)), dark_steel, Vector3(side * 0.42, -0.1, -0.04))
	# Great helm: barrel, flat-ish dome, visor slit and breaths, gold band, plume
	_add(root, _cyl(0.19, 0.2, 0.34), steel, Vector3(0, 0.77, 0))
	_add(root, _sphere(0.19, 0.16), steel, Vector3(0, 0.94, 0))
	_add(root, _box(Vector3(0.03, 0.34, 0.03)), gold, Vector3(0, 0.8, -0.2))	# nose guard
	_add(root, _cyl(0.205, 0.205, 0.03), gold, Vector3(0, 0.9, 0))
	var slit = _glow(_c(look, "eyes", Color(0.02, 0.02, 0.03)), look.has("eyes"))
	_add(root, _box(Vector3(0.3, 0.035, 0.04)), slit, Vector3(0, 0.8, -0.18))
	for i in range(3):
		_add(root, _box(Vector3(0.02, 0.02, 0.04)), _glow(Color(0.02, 0.02, 0.03), false), Vector3(0.06 + 0.04 * i, 0.7, -0.185))
	_add(root, _sphere(0.08, 0.36), _cloth(plume), Vector3(0, 1.08, 0.08), Vector3(-0.7, 0, 0))
	_add(root, _sphere(0.06, 0.3), _cloth(plume.lightened(0.15)), Vector3(0, 1.12, -0.02), Vector3(-0.3, 0, 0))
	# Cape (hangs down the back, swept back a little)
	_add(root, _box(Vector3(0.62, 1.35, 0.03)), cape, Vector3(0, -0.06, 0.36), Vector3(0.12, 0, 0))
	_add(root, _cyl(0.04, 0.04, 0.7), gold, Vector3(0, 0.56, 0.3), Vector3(0, 0, PI / 2.0))	# cape bar
	# Shield on the left arm: steel rim, cloth face, cross, boss. Pointed at the bottom.
	var shield = Node3D.new()
	shield.position = Vector3(-0.58, 0.08, -0.08)
	shield.rotation = Vector3(0, 0.25, 0)
	root.add_child(shield)
	_add(shield, _box(Vector3(0.05, 0.5, 0.48)), gold, Vector3(0, 0.08, 0))
	_add(shield, _box(Vector3(0.05, 0.36, 0.36)), gold, Vector3(0, -0.2, 0), Vector3(PI / 4.0, 0, 0))
	_add(shield, _box(Vector3(0.06, 0.46, 0.43)), tabard, Vector3(-0.005, 0.08, 0))
	_add(shield, _box(Vector3(0.06, 0.31, 0.31)), tabard, Vector3(-0.005, -0.2, 0), Vector3(PI / 4.0, 0, 0))
	_add(shield, _box(Vector3(0.02, 0.62, 0.06)), gold, Vector3(-0.04, -0.02, 0))
	_add(shield, _box(Vector3(0.02, 0.06, 0.4)), gold, Vector3(-0.04, 0.12, 0))
	_add(shield, _sphere(0.06), steel, Vector3(-0.05, 0.12, 0))
	# Sword in the right hand, held point-up and a little forward
	var sword = Node3D.new()
	sword.position = Vector3(0.44, -0.1, -0.12)
	sword.rotation = Vector3(-0.35, 0, 0)
	root.add_child(sword)
	_add(sword, _cyl(0.025, 0.025, 0.2), leather, Vector3(0, 0, 0))
	_add(sword, _sphere(0.04), gold, Vector3(0, -0.12, 0))
	_add(sword, _box(Vector3(0.26, 0.04, 0.05)), gold, Vector3(0, 0.11, 0))
	_add(sword, _box(Vector3(0.07, 0.9, 0.018)), _metal(Color(0.85, 0.87, 0.9), 0.15), Vector3(0, 0.58, 0))
	_add(sword, _cyl(0.0, 0.035, 0.1, 4), _metal(Color(0.85, 0.87, 0.9), 0.15), Vector3(0, 1.08, 0))
	# A faint lantern glow so the armor reads in dark zones (skin: "glow": 0 turns it off)
	var energy = float(look.get("glow", 0.6))
	if energy > 0.0:
		var lamp = OmniLight3D.new()
		lamp.light_color = _c(look, "glow_color", Color(1.0, 0.85, 0.65))
		lamp.light_energy = energy
		lamp.omni_range = 3.5
		lamp.position = Vector3(0, 0.6, -0.9)
		lamp.shadow_enabled = false
		root.add_child(lamp)
	return root


# ---------------- Shapes ----------------

static func _add(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF	# many small parts: shadows would cost a lot
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(sz: Vector3) -> BoxMesh:
	var b = BoxMesh.new()
	b.size = sz
	return b


static func _cyl(top: float, bottom: float, h: float, seg := 16) -> CylinderMesh:
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
	s.radial_segments = 16
	s.rings = 8
	return s


static func _c(look: Dictionary, key: String, fallback: Color) -> Color:
	var v = look.get(key, "")
	if v is String and v != "":
		return Color.from_string(v, fallback)
	return fallback


# ---------------- Materials (shared, made once per color) ----------------

## Hammered steel: soft dents (normal map) and light streaks in the color.
static func _metal(c: Color, rough := 0.35) -> StandardMaterial3D:
	var key = "metal|%s|%s" % [c.to_html(), rough]
	if not _mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		m.albedo_texture = _texture("streaks")
		m.metallic = 0.3	# low: the zones have no sky to reflect, so very shiny metal turns black
		m.metallic_specular = 0.8
		m.roughness = rough
		m.normal_enabled = true
		m.normal_texture = _texture("dents")
		m.normal_scale = 0.6
		m.rim_enabled = true	# a bright edge so dark armor still reads against a dark floor
		m.rim = 0.35
		m.rim_tint = 0.6
		_mats[key] = m
	return _mats[key]


## Chainmail: tiny rings, repeated many times.
static func _chain(c: Color) -> StandardMaterial3D:
	var key = "chain|" + c.to_html()
	if not _mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		m.albedo_texture = _texture("chain")
		m.metallic = 0.3
		m.roughness = 0.5
		m.normal_enabled = true
		m.normal_texture = _texture("chain_normal")
		m.uv1_scale = Vector3(6, 4, 1)
		_mats[key] = m
	return _mats[key]


## Woven cloth (tabard, cape, plume, leather grip).
static func _cloth(c: Color) -> StandardMaterial3D:
	var key = "cloth|" + c.to_html()
	if not _mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		m.albedo_texture = _texture("weave")
		m.roughness = 0.9
		m.uv1_scale = Vector3(3, 3, 1)
		_mats[key] = m
	return _mats[key]


static func _glow(c: Color, on: bool) -> StandardMaterial3D:
	var key = "glow|%s|%s" % [c.to_html(), on]
	if not _mats.has(key):
		var m = StandardMaterial3D.new()
		m.albedo_color = c
		if on:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 3.0
		_mats[key] = m
	return _mats[key]


# ---------------- Textures made in code ----------------

static func _texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var t: Texture2D
	match kind:
		"streaks":	# light/dark brushed streaks (grayscale; the material color tints it)
			var n = FastNoiseLite.new()
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.05
			var nt = NoiseTexture2D.new()
			nt.width = 128
			nt.height = 128
			nt.seamless = true
			nt.noise = n
			var ramp = Gradient.new()
			ramp.set_color(0, Color(0.72, 0.72, 0.72))
			ramp.set_color(1, Color(1, 1, 1))
			nt.color_ramp = ramp
			t = nt
		"dents":	# hammered look: soft round dents
			var n = FastNoiseLite.new()
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.08
			var nt = NoiseTexture2D.new()
			nt.width = 128
			nt.height = 128
			nt.seamless = true
			nt.as_normal_map = true
			nt.bump_strength = 3.0
			nt.noise = n
			t = nt
		"chain", "chain_normal":
			t = _chain_texture(kind == "chain_normal")
		"weave":
			t = _weave_texture()
	_tex[kind] = t
	return t


## Rings in staggered rows. As a normal map, the rings stand up from the surface.
static func _chain_texture(as_normal: bool) -> Texture2D:
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGB8)
	var cell = 16.0
	for y in range(size):
		for x in range(size):
			var best = 99.0
			var dir = Vector2.ZERO
			for row in range(-1, 6):
				var off = cell / 2.0 if row % 2 != 0 else 0.0
				for col in range(-1, 6):
					var c = Vector2(col * cell + off, row * cell * 0.75)
					var d = Vector2(x, y) - c
					var ring = abs(d.length() - cell * 0.42)
					if ring < best:
						best = ring
						dir = d.normalized() * (1.0 if d.length() > cell * 0.42 else -1.0)
			var on = clamp(1.0 - best / 2.2, 0.0, 1.0)
			if as_normal:
				var nx = dir.x * on * 0.8
				var ny = dir.y * on * 0.8
				img.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, 1.0))
			else:
				var v = 0.25 + 0.75 * on
				img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## A simple over-under weave with a little thread-to-thread variation.
static func _weave_texture() -> Texture2D:
	var size = 32
	var img = Image.create(size, size, false, Image.FORMAT_RGB8)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(size):
		for x in range(size):
			var over = ((x / 4) + (y / 4)) % 2 == 0
			var along = (y % 4) if over else (x % 4)
			var v = 0.82 + 0.12 * sin(along / 4.0 * PI) + (0.06 if over else 0.0) + rng.randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
