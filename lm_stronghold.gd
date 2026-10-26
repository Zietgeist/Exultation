extends "res://lm_base.gd"
## Stronghold (Keep / Barricaded Mall / Outpost): a walled square with corner towers, a gate facing
## the middle of the zone, and a keep at the back. Defenders and a named Warden hold it.
## Beat the Warden and it's TAKEN for good (saved with the party): it becomes a forward camp with a
## bank (deposit = a proper rest), a Smith, a campfire and a fast-travel stop.
## A taken stronghold is safe ground (no enemies spawn or fight inside), and a Survivor there asks
## you to recruit guards: press V (Parley) near Trash or Thugs; about half join (landmarks.gd).
## Guards you bring back stand watch on the walls, and SHOOT at enemies that come near the walls
## (hordes at the gates): twice a second, each guard hits the nearest one in reach (host only).

const HALF = 34.0
const GUARD_REACH = 26.0	# a guard on the wall shoots enemies this close to it
const GUARD_DAMAGE = 14.0	# per guard, per shot (two shots a second)
var _camp_built := false
var _guards_shown := 0
var _guard_nodes := []


func title_height() -> float:
	return 16.0


func _style_colors() -> Array:
	match SkinManager.props_style():
		"zombie": return [Color(0.5, 0.48, 0.45), Color(0.45, 0.3, 0.2)]
		"scifi": return [Color(0.42, 0.47, 0.55), Color(0.25, 0.75, 0.9)]
	return [Color(0.5, 0.48, 0.5), Color(0.55, 0.15, 0.15)]


## Which side the gate is on: the side closest to the way it faces.
func _gate_side() -> String:
	var f = facing()
	if abs(f.x) > abs(f.z):
		return "e" if f.x > 0 else "w"
	return "s" if f.z > 0 else "n"


func build():
	var cols = _style_colors()
	var stone = mat("lm_wall", cols[0])
	var accent = mat("lm_banner", cols[1])
	var h = HALF
	var side = _gate_side()
	var gate = [{at = 0.5, width = 10.0}]
	wall(Vector3(-h, 0, -h), Vector3(h, 0, -h), 6.0, 2.0, stone, gate if side == "n" else [])
	wall(Vector3(-h, 0, h), Vector3(h, 0, h), 6.0, 2.0, stone, gate if side == "s" else [])
	wall(Vector3(-h, 0, -h), Vector3(-h, 0, h), 6.0, 2.0, stone, gate if side == "w" else [])
	wall(Vector3(h, 0, -h), Vector3(h, 0, h), 6.0, 2.0, stone, gate if side == "e" else [])
	for x in [-h, h]:
		for z in [-h, h]:
			box(Vector3(7, 12, 7), Vector3(x, 6, z), stone)
			box(Vector3(1.6, 3, 0.2), Vector3(x, 13.5, z), accent, false)	# a banner on each tower
	# The keep, at the back (away from the gate)
	var back = -_side_vec(side) * (h - 10.0)
	box(Vector3(18, 10, 14), back + Vector3(0, 5, 0), stone)
	box(Vector3(19, 1.0, 15), back + Vector3(0, 10.5, 0), accent)
	if state().has("taken"):
		_build_camp()


func _side_vec(side: String) -> Vector3:
	return {"n": Vector3(0, 0, -1), "s": Vector3(0, 0, 1), "e": Vector3(1, 0, 0), "w": Vector3(-1, 0, 0)}[side]


func host_start():
	if state().has("taken"):
		return
	var h = HALF - 6.0
	for i in 10:
		count_for_zone(spawn_enemy(0, Vector3(randf_range(-h, h), 0, randf_range(-h, h))))
	for i in 5:
		count_for_zone(spawn_enemy(1, Vector3(randf_range(-h, h), 0, randf_range(-h, h))))
	for x in [-h, h]:
		for z in [-h, h]:
			count_for_zone(spawn_enemy(2, Vector3(x * 0.8, 0, z * 0.8)))
	var back = -_side_vec(_gate_side()) * (HALF - 20.0)
	var warden = spawn_enemy(3, back, 2.5, "%s of %s" % [Landmarks.word("warden"), info.name])
	if warden:
		warden.no_count = true	# not one of the zone's two bosses
		warden.enemy_died.connect(func(_t): _taken())


func _taken():
	set_state({taken = Time.get_date_string_from_system(), by = Landmarks.who()})
	announce("taken", {by = Landmarks.who()})


func net_event(event: String, data: Dictionary):
	if event != "taken":
		return
	GameState.notify("%s is yours! It's now a %s." % [info.name, Landmarks.word("camp")])
	Story.add("Took %s with %s." % [info.name, ", ".join(data.get("by", [Story.player_name]))])
	Traits.nudge("pace", 6.0, "took " + info.name)
	_build_camp()
	# a fast-travel stop, right away
	var w = Area3D.new()
	w.set_script(load("res://waystation.gd"))
	w.station_id = "lm:" + info.id
	w.label_text = "%s, %s" % [GameState.ZONE_NAMES.get(zone_path, ""), Landmarks.station_label(info)]
	w.zone_path = zone_path
	get_parent().add_child(w)
	w.global_position = global_position + facing() * 14.0


## The forward camp: bank (rest), Smith, campfire.
func _build_camp():
	if _camp_built:
		return
	_camp_built = true
	var f = facing()
	var right = Vector3(f.z, 0, -f.x)
	bank_spot(right * 10.0, "%s bank\n(step in: bank gold and rest)" % Landmarks.word("camp"))
	var ui = SHOP_UI.new()
	add_child(ui)
	npc(-right * 10.0, "Quartermaster", "the camp Smith", "smith", ui, Color(0.55, 0.4, 0.3))
	var fire = box(Vector3(1.6, 0.8, 1.6), f * 2.0 + Vector3(0, 0.4, 0), mat("campfire", Color(1.0, 0.55, 0.15), true), false)
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 18.0
	light.position.y = 2.0
	fire.add_child(light)
	label(Landmarks.word("camp"), Vector3(0, 9, 0) + f * 2.0, 40, Color(0.7, 1.0, 0.7))
	# Safe ground: enemies don't spawn here or fight inside the walls any more
	Landmarks.add_safe(Zones.key_of(self), global_position, HALF + 2.0)
	# The survivor, who wants guards
	var rui = load("res://recruit_ui.gd").new()
	rui.lm = self
	add_child(rui)
	npc(-f * 8.0, "Survivor", "needs guards", "recruit", rui, Color(0.75, 0.65, 0.5))
	_show_guards()


## Guards stand along the walls, one per recruit (up to 24 shown).
func _show_guards():
	var n = mini(int(state().get("guards", 0)), 24)
	if n == _guards_shown:
		return
	for g in _guard_nodes:
		g.queue_free()
	_guard_nodes.clear()
	_guards_shown = n
	var gm = mat("lm_guard", Color(0.45, 0.6, 0.85))
	for i in n:
		var side = i % 4
		var t = (float(i / 4) + 0.5) / 6.0 * 2.0 - 1.0	# spread along the wall
		var h = HALF - 3.0
		var pos = [Vector3(t * h, 0, -h), Vector3(h, 0, t * h), Vector3(-t * h, 0, h), Vector3(-h, 0, -t * h)][side]
		var g = box(Vector3(0.9, 1.9, 0.9), pos + Vector3(0, 0.95, 0), gm, false)
		var head = box(Vector3(0.6, 0.6, 0.6), pos + Vector3(0, 2.2, 0), gm, false)
		_guard_nodes.append(g)
		_guard_nodes.append(head)


func tick(_dt: float):
	if _camp_built:
		_show_guards()
		_guards_fight()


## Each guard shoots the nearest enemy that comes within reach of the walls.
func _guards_fight():
	if Net.is_client() or _guards_shown <= 0:
		return
	var foes = Zones.all(self, "enemy").filter(func(e): return is_instance_valid(e) and e.health > 0 and not e.is_queued_for_deletion() and global_position.distance_to(e.global_position) < HALF + GUARD_REACH)
	if foes.is_empty():
		return
	for i in range(0, _guard_nodes.size(), 2):	# bodies (heads in between)
		var from = _guard_nodes[i].global_position + Vector3(0, 1.4, 0)
		var best = null
		var best_d = GUARD_REACH
		for e in foes:
			var d = from.distance_to(e.global_position)
			if d < best_d and e.health > 0:
				best = e
				best_d = d
		if best:
			_shot(from, best.global_position + Vector3(0, 1.0, 0))
			best.take_damage(GUARD_DAMAGE)


func _shot(a: Vector3, b: Vector3):
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, a.distance_to(b))
	mi.mesh = bm
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 1.0, 0.9)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.8, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	Zones.root_of(self).add_child(mi)
	mi.global_position = (a + b) / 2.0
	mi.look_at_from_position(mi.global_position, b, Vector3.UP)
	var tw = mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)
