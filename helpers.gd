extends Node
## Autoload "Helpers": people you rescue, who then help you in town during your rests.
##   Zone 2: the COOK. Takes over the Inn's three treats (damage, energy regen, max health), and refines
##           your stored herbs into tonics like an assistant (Wren takes that over once rescued).
##           Cooking starts when your break starts (you walk into Home) and the meal is served when you
##           leave Home. The longer you let them cook, the better, growing EXPONENTIALLY:
##           1 min ~2%, 2 min ~8%, 3 min ~29%, 4 min = 100% (see cook_power).
##   Zone 3: the SMITH'S ASSISTANT.   When your break starts they take your stored ore / treesilver /
##   Zone 4: the ALCHEMIST'S ASSISTANT.  herbs / orchids and refine ALL of it in 3 minutes, with a bonus
##           (+1 for every 3 made). Results land in your crafting stash.
## Rescue: each one is held at a camp in their zone by a Master and its pack. Clear the guards,
## walk up and press G. They then wait at Home between the Return Portal and the fast-travel stop.
## Saved per character (helpers.cfg). Personal: online, everyone rescues their own.

const HOME = "res://Home.tscn"
const NPC = preload("res://npc.gd")
const ENEMY_SCENE = preload("res://enemy.tscn")
const HELPERS = {
	"cook": {zone = "res://Zone2.tscn", name = "Mara", role = "Camp Cook", shop = "chemist", only = ["herb"], color = Color(0.95, 0.6, 0.35), spot = Vector3(-6, 0, 19)},	# also refines herbs (Wren takes over once rescued)
	"smith_helper": {zone = "res://Zone3.tscn", name = "Pell", role = "Smith's Assistant", shop = "smith", color = Color(0.6, 0.45, 0.35), spot = Vector3(-11, 0, 22)},
	"chemist_helper": {zone = "res://Zone4.tscn", name = "Wren", role = "Alchemist's Assistant", shop = "chemist", color = Color(0.45, 0.75, 0.6), spot = Vector3(-16, 0, 25)},
}
const COOK_FULL_MIN = 4.0	# minutes of cooking for the full meal
const COOK_K = 1.2			# how steep the curve is (bigger = more of the reward at the very end)
const ASSIST_SECONDS = 180.0
const ASSIST_BONUS = 1.0 / 3.0	# +1 refined for every 3
const GUARD_TRASH = 10
const GUARD_CLEAR = 14.0	# no living enemy this close to the captive = guards cleared

var rescued := {}			# helper id -> true
var cook_since := 0.0		# unix time cooking started (0 = not cooking)
var jobs := {}				# helper id -> {done_at = unix time, out = {"ingot:1": n}, made = n}
var _last_path := ""
var _tick := 0.0

var SAVE_PATH: String:
	get:
		return Account.path("helpers.cfg")


func _ready():
	load_character()
	SessionManager.break_started.connect(_on_rest)
	Zones.entered.connect(_on_entered)


func load_character():
	rescued = {}
	cook_since = 0.0
	jobs = {}
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		rescued = cfg.get_value("helpers", "rescued", {})
		cook_since = cfg.get_value("helpers", "cook_since", 0.0)
		jobs = cfg.get_value("helpers", "jobs", {})


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("helpers", "rescued", rescued)
	cfg.set_value("helpers", "cook_since", cook_since)
	cfg.set_value("helpers", "jobs", jobs)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Helpers: could not save " + SAVE_PATH)


func is_rescued(id: String) -> bool:
	return rescued.has(id)


func helper_name(id: String) -> String:
	var n = SkinManager.name_of("helper_" + id)	# a skin can rename them
	return HELPERS[id].name if n == "helper_" + id else n


## 0..1: how good the meal is after cooking this many minutes (exponential: the last minute matters most).
static func cook_power(minutes: float) -> float:
	if minutes <= 0.0:
		return 0.0
	return clampf((exp(COOK_K * minutes) - 1.0) / (exp(COOK_K * COOK_FULL_MIN) - 1.0), 0.0, 1.0)


func _now() -> float:
	return Time.get_unix_time_from_system()


# ---------------- Rest: helpers get to work ----------------

func _on_rest(_blocks):
	if Zones.local_path() != HOME:
		return
	if is_rescued("cook"):
		cook_since = _now()
		GameState.notify("%s starts cooking. Stay a while: the longer it cooks, the better (best at 4 minutes)." % helper_name("cook"))
	for id in ["smith_helper", "chemist_helper", "cook"]:	# Wren before Mara: with both, Wren gets the herbs
		if is_rescued(id) and not jobs.has(id):
			_start_job(id)
	_save()


func _start_job(id: String):
	var out = {}
	var made = 0
	for o in Crafting.refine_options(HELPERS[id].shop):
		if HELPERS[id].has("only") and not o.raw in HELPERS[id].only:
			continue	# Mara only does herbs
		var batches = int(o.have / o.cost)
		if batches <= 0:
			continue
		if not GameState.take_raw("%s:%d" % [o.raw, o.q], batches * o.cost):
			continue
		var n = batches + int(batches * ASSIST_BONUS)
		var key = "%s:%d" % [o.to, o.q]
		out[key] = out.get(key, 0) + n
		made += n
	if made == 0:
		return	# nothing stored to refine (talk to them to hear what they need)
	jobs[id] = {done_at = _now() + ASSIST_SECONDS, out = out, made = made}
	GameState.save_progress()	# the raw materials left the storehouse
	GameState.notify("%s takes your %s: %d refined in 3 minutes." % [helper_name(id), "ore" if id == "smith_helper" else "herbs", made])	# (Mara's herb job runs beside her cooking)


func _process(delta):
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	for id in jobs.keys():
		if _now() >= float(jobs[id].done_at):
			_finish_job(id)


func _finish_job(id: String):
	var j = jobs[id]
	for key in j.out:
		Crafting.stash[key] = Crafting.stash.get(key, 0) + int(j.out[key])
	Crafting.save()
	Crafting.changed.emit()
	jobs.erase(id)
	_save()
	GameState.notify("%s is done: %d refined, in your stash." % [helper_name(id), int(j.made)])


## Leaving Home: the cook serves whatever is ready.
func _on_entered(zone):
	var path = zone.path if zone else ""
	if _last_path == HOME and path != HOME and cook_since > 0.0:
		_serve()
	_last_path = path


func _serve():
	var p = cook_power((_now() - cook_since) / 60.0)
	cook_since = 0.0
	_save()
	if p < 0.01:
		GameState.notify("You left before %s's meal was ready." % helper_name("cook"))
		return
	for id in GameState.BUFF_MAX:
		GameState.buffs[id] = p
	GameState.save_progress()
	GameState.buffs_changed.emit()
	GameState.notify("%s's meal (%d%%): %s, %s, %s" % [helper_name("cook"), roundi(p * 100), GameState.buff_text("meal"), GameState.buff_text("sleep"), GameState.buff_text("tonic")])


# ---------------- Talking (G) ----------------

## npc.gd calls ui.open(shop, who): here shop is the helper id ("cook"...), or "captive:<id>".
func open(what: String, who):
	if what.begins_with("captive:"):
		_talk_captive(what.substr(8), who)
		return
	var n = helper_name(what)
	if what == "cook":
		if cook_since > 0.0:
			var m = (_now() - cook_since) / 60.0
			var left = maxf(0.0, COOK_FULL_MIN * 60.0 - (_now() - cook_since))
			GameState.notify("%s: \"It's %d%% ready.%s Leave Home whenever you like: I'll serve what's done.\"" % [n, roundi(cook_power(m) * 100), (" Best in %d:%02d." % [int(left) / 60, int(left) % 60]) if left > 0 else " It's perfect!"])
		else:
			GameState.notify("%s: \"Come home from a zone for a break, and I'll start cooking. I'll turn your herbs into tonics too.\"" % n)
		if jobs.has("cook"):
			var left = maxf(0.0, float(jobs.cook.done_at) - _now())
			GameState.notify("%s: \"Your tonics: %d in %d:%02d.\"" % [n, int(jobs.cook.made), int(left) / 60, int(left) % 60])
		return
	if jobs.has(what):
		var left = maxf(0.0, float(jobs[what].done_at) - _now())
		GameState.notify("%s: \"%d refined in %d:%02d.\"" % [n, int(jobs[what].made), int(left) / 60, int(left) % 60])
	else:
		GameState.notify("%s: \"When you come home for a break, I'll refine everything in your storehouse (+1 for every 3). Bring me %s!\"" % [n, "ore and treesilver" if what == "smith_helper" else "herbs and orchids"])


# ---------------- Town: rescued helpers wait at Home ----------------

## spiral_floor.gd calls this when Home is built.
func build_town(home_floor: Node3D):
	for id in HELPERS:
		if not is_rescued(id):
			continue
		var h = HELPERS[id]
		var npc = NPC.new()
		npc.npc_name = helper_name(id)
		npc.role = h.role
		npc.shop = id
		npc.color = h.color
		npc.ui = self
		home_floor.add_child(npc)
		npc.position = h.spot


# ---------------- Captives out in the zones ----------------

## spiral_floor.gd calls this once a zone's terrain is up.
func place_captives(floor_node: Node3D, path: String):
	for id in HELPERS:
		if HELPERS[id].zone == path and not is_rescued(id):
			_place_captive.call_deferred(floor_node, id)


func _place_captive(floor_node: Node3D, id: String):
	if not is_instance_valid(floor_node):
		return
	var terrain = Zones.first(floor_node, "zone_terrain")
	var spot = null
	if terrain:
		var camps = terrain.pack_sites().filter(func(s): return s.kind == "camp")
		if camps.size() > 0:
			var c = camps.pick_random()
			spot = c.p + Vector3(1.5, 0, 1.5)	# beside the fire
		else:
			spot = terrain.get_clear_pos(3.0)
	if spot == null:
		var half = floor_node.get_half_size()
		spot = Vector3(randf_range(-half.x, half.x) * 0.6, 0, randf_range(-half.y, half.y) * 0.6)
	var zroot = Zones.root_of(floor_node)
	if zroot == null:	# the zone scene was opened on its own before the World took it in: it gets built again
		return
	var h = HELPERS[id]
	var npc = NPC.new()
	npc.npc_name = helper_name(id)
	npc.role = "Captive! Free them (G)"
	npc.shop = "captive:" + id
	npc.color = h.color
	npc.ui = self
	zroot.add_child(npc)
	npc.global_position = Vector3(spot.x, 0, spot.z)
	_cage(npc)
	if not Net.is_client():	# the host runs enemies
		var guards = [2]	# a Master
		for i in range(GUARD_TRASH):
			guards.append(0)
		for t in guards:
			var e = ENEMY_SCENE.instantiate()
			zroot.add_child(e)
			var a = randf() * TAU
			e.global_position = npc.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 7.0) + Vector3(0, 1.2, 0)
			e.setup(1.0, t, Crafting.roll_enemy_element(h.zone, false))
			e.set_meta("captive_guard", id)
	if Zones.local_zone() == Zones.zone_of(floor_node):
		GameState.notify("Someone is held captive in this zone, at a camp. Free them!")


func _cage(npc: Node3D):
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.27, 0.25)
	for i in range(6):
		var a = TAU * i / 6.0
		var bar = MeshInstance3D.new()
		var mesh = CylinderMesh.new()
		mesh.top_radius = 0.06
		mesh.bottom_radius = 0.06
		mesh.height = 2.6
		bar.mesh = mesh
		bar.material_override = m
		bar.position = Vector3(cos(a) * 1.1, 1.3, sin(a) * 1.1)
		bar.name = "CageBar"
		npc.add_child(bar)


func _talk_captive(id: String, who):
	var left = 0
	for e in Zones.all(who, "enemy"):
		if is_instance_valid(e) and e.health > 0 and e.global_position.distance_to(who.global_position) <= GUARD_CLEAR:
			left += 1
	if left > 0:
		GameState.notify("%s: \"Get me out of here! Deal with the guards first (%d left).\"" % [helper_name(id), left])
		return
	rescued[id] = true
	_save()
	var what = {"cook": "I'll cook for you while you rest.", "smith_helper": "I'll help at the forge.", "chemist_helper": "I'll help with the potions."}[id]
	GameState.notify("%s is free! \"Thank you! I'll wait at Home, by the Return Portal. %s\"" % [helper_name(id), what])
	who.queue_free()
