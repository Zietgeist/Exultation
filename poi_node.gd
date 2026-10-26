extends Node3D
## One encounter in a big zone (regions.gd lists them, zone_features.gd builds them near players).
##   cache     a supply cache: walk up to it and it opens. Personal: everyone opens their own
##             (some gold in your bag and a few resources from this zone).
##   stone     a story stone: walk up to read it. The words go in your Chronicle.
##   champion  a camp with a banner. The champion and its escorts wake when someone comes close
##             (the host runs that in zone_features.gd); this is just the camp you see.
## Ambushes have no node: they're hidden until they spring.

const PROPS = preload("res://props.gd")
const OPEN_RANGE = 2.8
const READ_RANGE = 4.5
const CACHE_GOLD = Vector2i(3, 6)
const CACHE_RESOURCES = Vector2i(2, 4)

var poi := {}
var zone_path := ""
var features = null
var _label: Label3D
var _lid: MeshInstance3D
var _check := 0.0


func _ready():
	add_to_group("encounter")
	var style = SkinManager.props_style()
	match poi.kind:
		"cache": _build_cache(style)
		"stone": _build_stone(style)
		"champion": _build_camp(style)
		_:
			ErrorLog.warn("Encounter: unknown kind '%s' (%s)" % [poi.kind, poi.id])
	_refresh()


func done() -> bool:
	if poi.kind == "champion":
		return features != null and features.pois_done.has(poi.id)
	return Regions.is_done(zone_path, poi.id)


func _process(delta):
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.2
	if poi.kind == "champion":
		_refresh()
		return
	if done():
		return
	var me = Zones.player
	if me == null or not is_instance_valid(me) or Zones.zone_of(me) != Zones.zone_of(self):
		return
	var d = Vector2(me.global_position.x - global_position.x, me.global_position.z - global_position.z).length()
	if poi.kind == "cache" and d < OPEN_RANGE:
		_open_cache()
	elif poi.kind == "stone" and d < READ_RANGE:
		_read_stone()


# ---------------- Cache ----------------

func _build_cache(style: String):
	var c = {"scifi": Color(0.4, 0.45, 0.55), "zombie": Color(0.35, 0.4, 0.3), "darkfantasy": Color(0.25, 0.2, 0.22)}.get(style, Color(0.5, 0.33, 0.18))
	var body = StaticBody3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.4, 0.9, 1.0)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.45
	body.add_child(col)
	var box = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(1.4, 0.8, 1.0)
	box.mesh = bm
	box.position.y = 0.4
	box.material_override = SkinManager.material("cache_box", c)
	body.add_child(box)
	add_child(body)
	_lid = MeshInstance3D.new()
	var lm = BoxMesh.new()
	lm.size = Vector3(1.5, 0.2, 1.1)
	_lid.mesh = lm
	_lid.position.y = 0.9
	add_child(_lid)
	_label = _make_label("Supply cache", 2.2)


func _open_cache():
	Regions.mark_done(zone_path, poi.id)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(zone_path + poi.id + "loot")
	var gold = rng.randi_range(CACHE_GOLD.x, CACHE_GOLD.y)
	GameState.add_gold(gold)
	var got = "+%d gold" % gold
	var q = GameState.zone_quality(zone_path)
	if q > 0:
		var type = ["ore", "herb", "treesilver", "orchid"][rng.randi() % 4]
		var n = rng.randi_range(CACHE_RESOURCES.x, CACHE_RESOURCES.y)
		if GameState.add_resource(type, q, n):
			got += ", +%d %s" % [n, GameState.resource_name(type, q)]
		else:
			got += " (your satchel is full)"
	GameState.notify("Found a cache: " + got)
	Traits.nudge("roam", -0.5, "found a cache")	# Wanderer
	_refresh()


# ---------------- Story stone ----------------

func _build_stone(style: String):
	var c = {"scifi": Color(0.35, 0.4, 0.5), "zombie": Color(0.45, 0.44, 0.42), "darkfantasy": Color(0.2, 0.19, 0.22)}.get(style, Color(0.5, 0.5, 0.48))
	var body = StaticBody3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(1.2, 2.6, 0.6)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.3
	body.add_child(col)
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(1.2, 2.6, 0.6)
	mi.mesh = bm
	mi.position.y = 1.3
	mi.rotation.z = 0.06
	mi.material_override = SkinManager.material("story_stone", c)
	body.add_child(mi)
	var rune = MeshInstance3D.new()
	var rm = BoxMesh.new()
	rm.size = Vector3(0.7, 1.2, 0.05)
	rune.mesh = rm
	rune.position = Vector3(0, 1.4, 0.31)
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.85, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.85, 1.0)
	m.emission_energy_multiplier = 1.4
	rune.material_override = m
	body.add_child(rune)
	add_child(body)
	_label = _make_label("Story stone", 3.4)


func _read_stone():
	Regions.mark_done(zone_path, poi.id)
	var text = Regions.lore(zone_path, poi)
	GameState.notify(text)
	Story.once("stone:%s|%s" % [zone_path, poi.id], "Read a stone in %s: %s" % [GameState.ZONE_NAMES.get(zone_path, ""), text])
	Traits.nudge("roam", -0.5, "read a story stone")	# Wanderer
	_refresh()


# ---------------- Champion's camp ----------------

func _build_camp(style: String):
	add_child(PROPS.campfire(style))
	var pole = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.1
	cm.height = 4.5
	pole.mesh = cm
	pole.position = Vector3(2.0, 2.25, 0)
	pole.material_override = SkinManager.material("banner_pole", Color(0.3, 0.25, 0.2))
	add_child(pole)
	var flag = MeshInstance3D.new()
	var fm = BoxMesh.new()
	fm.size = Vector3(1.4, 0.9, 0.05)
	flag.mesh = fm
	flag.position = Vector3(2.75, 3.9, 0)
	flag.material_override = SkinManager.material("champion_banner", Color(0.75, 0.15, 0.12))
	add_child(flag)
	_label = _make_label("Champion's camp", 5.2)


# ---------------- Looks ----------------

func _make_label(text: String, height: float) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 34
	l.pixel_size = 0.012
	l.outline_size = 10
	l.position.y = height
	add_child(l)
	return l


func _refresh():
	var is_done = done()
	match poi.kind:
		"cache":
			var m = StandardMaterial3D.new()
			m.albedo_color = Color(0.4, 0.4, 0.4) if is_done else Color(1.0, 0.8, 0.25)
			m.emission_enabled = not is_done
			m.emission = Color(1.0, 0.75, 0.2)
			m.emission_energy_multiplier = 1.2
			_lid.material_override = m
			_lid.rotation.x = -1.1 if is_done else 0.0
			_lid.position = Vector3(0, 1.2, -0.45) if is_done else Vector3(0, 0.9, 0)
			_label.modulate = Color(0.6, 0.6, 0.6) if is_done else Color(1.0, 0.85, 0.4)
			if is_done:
				_label.text = "(empty)"
		"stone":
			_label.modulate = Color(0.75, 0.85, 0.95) if is_done else Color(0.6, 0.85, 1.0)
			if is_done:	# read: its words stay over it
				_label.text = Regions.lore(zone_path, poi)
				_label.width = 600
				_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_label.font_size = 30
		"champion":
			_label.text = "Champion's camp (beaten)" if is_done else "Champion's camp"
			_label.modulate = Color(0.6, 0.6, 0.6) if is_done else Color(1.0, 0.5, 0.4)
