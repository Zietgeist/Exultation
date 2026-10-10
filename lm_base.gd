extends Node3D
## Shared parts of every landmark (see landmarks.gd). Each kind (lm_stronghold.gd, lm_town.gd...)
## extends this and builds its own look in build(), and its fights (host only) in host_start().
## Facts that should last (taken, closed, fallen...) go through set_state(): they're saved with the party.

const ENEMY_SCENE = preload("res://enemy.tscn")
const SHOP_UI = preload("res://shop_ui.gd")

var info := {}			# {id, kind, pos, size, name, zone}
var zone_path := ""
var _title: Label3D
var _check := 0.0
var _found := false


func _ready():
	add_to_group("landmark")
	build()
	_title = label(info.name, Vector3(0, title_height(), 0), 46, Color(1.0, 0.9, 0.6))
	_found = state().has("found")
	if not Net.is_client():
		host_start.call_deferred()


## Override: make the landmark's shape.
func build():
	pass

## Override: host (or solo) only. Spawn defenders, start timers...
func host_start():
	pass

## Override: something the host told everyone (Net.landmark_event).
func net_event(_event: String, _data: Dictionary):
	pass

func title_height() -> float:
	return 12.0


func state() -> Dictionary:
	return Landmarks.state(zone_path, info.id)

func set_state(changes: Dictionary):
	Landmarks.set_state(zone_path, info.id, changes)
	Landmarks.refresh_landmark_jobs()

## Host: tell the joined players in this zone (and run it here too).
func announce(event: String, data := {}):
	Net.landmark_event(self, event, data)
	net_event(event, data)


func facing() -> Vector3:
	return Landmarks.facing(info)


func zone_diff() -> float:
	return 1.0 + 0.25 * (info.zone - 1)


func local_player():
	var p = Zones.player
	return p if p and p.is_inside_tree() and Zones.zone_of(p) == Zones.zone_of(self) else null


func player_distance() -> float:
	var p = local_player()
	return INF if p == null else Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()


func _process(delta):
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	if not _found and player_distance() < Landmarks.DISCOVER_RANGE:
		_found = true
		var zone = GameState.ZONE_NAMES.get(zone_path, "")
		Story.once("lm:%s|%s" % [zone_path, info.id], "Came upon %s in %s." % [info.name, zone])
		GameState.notify("Discovered: " + info.name)
		Traits.nudge("roam", -2.0, "found " + info.name)
		if not state().has("found"):
			set_state({found = Time.get_date_string_from_system(), found_by = Story.player_name})
	tick(0.5)


## Override: called twice a second.
func tick(_dt: float):
	pass


# ---------------- Enemies (host only) ----------------

## A foe that belongs to this landmark (not saved with the zone, doesn't sleep).
func spawn_enemy(tier: int, local_pos: Vector3, diff_mult := 1.0, title := ""):
	if Net.is_client():
		return null
	var e = ENEMY_SCENE.instantiate()
	e.set_meta("landmark", info.id)
	Zones.root_of(self).add_child(e)
	var p = to_global(local_pos)
	e.global_position = Vector3(p.x, 1.2, p.z)
	e.setup(zone_diff() * diff_mult, tier, Crafting.roll_enemy_element(zone_path, tier == 3))
	if title != "":
		e.set_title(title)
	return e


## Count the kill toward the zone's clearing too.
func count_for_zone(e):
	var sp = Zones.first(self, "zone_spawner")
	if sp and is_instance_valid(e):
		e.enemy_died.connect(sp._on_enemy_died)


# ---------------- Building blocks ----------------

func mat(id: String, c: Color, glow := false) -> Material:
	if not glow:
		return SkinManager.material(id, c)
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	return m


## A box (solid if `solid`), at a local position, rotated `yaw` radians.
func box(size: Vector3, pos: Vector3, m: Material, solid := true, yaw := 0.0) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	var mi = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	root.add_child(mi)
	if solid:
		var cs = CollisionShape3D.new()
		var sh = BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		root.add_child(cs)
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	return root


## A wall from a to b (local), with optional gaps [{at (0..1 along), width}].
func wall(a: Vector3, b: Vector3, height: float, thick: float, m: Material, gaps := []):
	var d = b - a
	var length = d.length()
	var cuts = []
	for g in gaps:
		cuts.append([g.at * length - g.width / 2.0, g.at * length + g.width / 2.0])
	cuts.sort_custom(func(x, y): return x[0] < y[0])
	var start = 0.0
	for c in cuts + [[length, length]]:
		if c[0] - start > 0.5:
			var mid = a + d.normalized() * (start + c[0]) / 2.0
			box(Vector3(c[0] - start, height, thick), mid + Vector3(0, height / 2.0, 0), m, true, atan2(-d.z, d.x))
		start = c[1]


func house(pos: Vector3, size: Vector3, wall_m: Material, roof_m: Material, yaw := 0.0) -> Node3D:
	var h = box(size, pos + Vector3(0, size.y / 2.0, 0), wall_m, true, yaw)
	var roof = MeshInstance3D.new()
	var pm = PrismMesh.new()
	pm.size = Vector3(size.x + 1.0, 2.2, size.z + 1.0)
	roof.mesh = pm
	roof.material_override = roof_m
	roof.position = Vector3(0, size.y / 2.0 + 1.1, 0)
	h.add_child(roof)
	return h


func label(text: String, pos: Vector3, size := 40, c := Color.WHITE) -> Label3D:
	var l = Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	l.font_size = size
	l.pixel_size = 0.014
	l.outline_size = 12
	l.no_depth_test = true
	l.modulate = c
	add_child(l)
	return l


## A shopkeeper-style NPC (G to talk). ui is a shop window (shop_ui.gd) or anything with open(shop, who).
func npc(pos: Vector3, npc_name: String, role: String, shop: String, ui, color: Color) -> Node3D:
	var n = load("res://npc.gd").new()
	n.npc_name = npc_name
	n.role = role
	n.shop = shop
	n.ui = ui
	n.color = color
	n.position = pos
	add_child(n)
	return n


## Deposit gold here and rest (counts as a rest at Home: Patient, the Chronicle line, Inn treats end).
func bank_spot(pos: Vector3, text: String):
	var a = Area3D.new()
	var cs = CollisionShape3D.new()
	var sh = CylinderShape3D.new()
	sh.radius = 2.0
	sh.height = 3.0
	cs.shape = sh
	cs.position.y = 1.5
	a.add_child(cs)
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 1.8
	cyl.height = 1.0
	mi.mesh = cyl
	mi.position.y = 0.5
	mi.material_override = mat("bank", Color(1.0, 0.8, 0.2), true)
	a.add_child(mi)
	a.position = pos
	add_child(a)
	var l = label(text, pos + Vector3(0, 3.2, 0), 34, Color(1.0, 0.85, 0.3))
	a.body_entered.connect(func(body):
		if body != Zones.player:
			return
		var amount = GameState.deposit_gold()
		var stored = GameState.store_satchel()	# the satchel empties into the storehouse at Home too
		if stored > 0:
			GameState.notify("Stored %d resources (sent Home)" % stored)
		if amount > 0:
			GameState.notify("Banked %d gold at %s. Rest a moment." % [amount, info.name])
			SessionManager.rest_here()
		l.text = "%s\nBanked: %d gold" % [text, GameState.gold_banked])
