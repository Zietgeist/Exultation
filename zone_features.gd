extends Node3D
## Regions and encounters in a big zone (Zone 6 and up). Made by spiral_floor.gd, one per zone.
## The data (where things are) comes from Regions (regions.gd); this node brings it to life:
##
##   - Builds region HEARTS (region_heart.gd) and ENCOUNTERS (poi_node.gd) only near players, and
##     drops them again when everyone is far away, so even Zone 10 stays fast.
##   - Says "Entering the Ashen Fells" when you walk into a new region.
##   - Host (or solo) only: wakes each region's BOSS and its guards when someone reaches the heart,
##     wakes CHAMPIONS and springs AMBUSHES, and runs the horde DIRECTOR (zone_director.gd).
##     Beating a region boss frees the region and counts toward the zone's 2nd boss.
##   - What happened (region bosses down, champions beaten, ambushes sprung) lasts this play
##     session, like the zone's enemies (GameState.zone_memory "features"). Joined players get it
##     when they come in (Net._layout_of) and as it happens (Net.feature_event -> net_event).
## Caches and story stones are personal: everyone opens and reads their own (Regions.done).

const ENEMY_SCENE = preload("res://enemy.tscn")
const HEART_SCRIPT = preload("res://region_heart.gd")
const POI_SCRIPT = preload("res://poi_node.gd")
const DIRECTOR_SCRIPT = preload("res://zone_director.gd")

const CHECK_EVERY = 0.5
const HEART_BUILD = 260.0		# build a region's heart when someone is this close
const HEART_DROP = 360.0		# drop it again when everyone is this far
const POI_BUILD = 160.0
const POI_DROP = 240.0
const BOSS_WAKE = 60.0			# a region boss and its guards show up when someone is this close to its heart
const CHAMPION_WAKE = 55.0
const AMBUSH_TRIGGER = 14.0		# step this close to a hidden ambush and it springs
const FOE_DROP = 320.0			# host: a group nobody is fighting, this far from everyone, is put away (comes back later)
const REGION_CREDIT = 0.1		# a region boss counts as this share of the kills needed for the 2nd boss
const BOSS_HEALTH = 2.0			# region boss: a Master this many times tougher
const CHAMPION_HEALTH = 1.6
const GUARDS = Vector2i(6, 9)	# Trash around a region boss (plus one Thug)
const ESCORTS = Vector2i(4, 6)	# Trash around a champion
const AMBUSHERS = Vector2i(8, 12)	# Trash in an ambush (plus one Thug)

var zone_path := ""
var regions := []
var pois := []
var bosses_down := {}	# region id -> true
var pois_done := {}		# encounter id -> true (champions beaten, ambushes sprung)
var director = null		# host only

var _hearts := {}		# region id -> region_heart node
var _poi_nodes := {}	# encounter id -> poi_node
var _foes := {}			# host: region / encounter id -> [enemies it woke]
var _region_id := ""	# the region the local player is in right now
var _t := 0.0


func _ready():
	add_to_group("zone_features")
	regions = Regions.for_zone(zone_path)
	pois = Regions.pois_for_zone(zone_path)
	for id in Regions.freed(zone_path):	# freed in an earlier play session (saved with you / your party)
		bosses_down[id] = true
	var saved = GameState.zone_memory.get(zone_path, {}).get("features", null)
	if saved is Dictionary:
		for id in saved.get("bosses_down", []):
			bosses_down[id] = true
		for id in saved.get("pois_done", []):
			pois_done[id] = true
	if not Net.is_client():
		director = DIRECTOR_SCRIPT.new()
		director.features = self
		director.name = "Director"
		add_child(director)
	print("Zone features: %d regions, %d encounters" % [regions.size(), pois.size()])


## For GameState.remember_zone and for joined players (Net._layout_of).
func save_state() -> Dictionary:
	return {bosses_down = bosses_down.keys(), pois_done = pois_done.keys()}


func _process(delta):
	_t -= delta
	if _t > 0.0:
		return
	_t = CHECK_EVERY
	var who = _people()
	_stream_hearts(who)
	_stream_pois(who)
	_track_region()
	if not Net.is_client():
		_host_tick(who)


## The players this zone has to come alive around. Host / solo: everyone here. Joined: just me.
func _people() -> Array:
	if Net.is_client():
		var me = Zones.player
		return [me] if me and is_instance_valid(me) and me.is_inside_tree() and Zones.zone_of(me) == Zones.zone_of(self) else []
	return GameState.party(self).filter(func(m): return is_instance_valid(m) and m.is_inside_tree())


func _closest(who: Array, p: Vector3) -> float:
	var best = INF
	for m in who:
		best = minf(best, Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length())
	return best


func _nearest_person(who: Array, p: Vector3):
	var best = null
	var best_d = INF
	for m in who:
		var d = Vector2(m.global_position.x - p.x, m.global_position.z - p.z).length()
		if d < best_d:
			best = m
			best_d = d
	return best


# ---------------- Building things near players ----------------

func _stream_hearts(who: Array):
	for r in regions:
		var d = _closest(who, r.heart)
		if not _hearts.has(r.id) and d < HEART_BUILD:
			var h = HEART_SCRIPT.new()
			h.region = r
			h.zone_path = zone_path
			h.freed = bosses_down.has(r.id)
			h.name = "Heart_" + r.id
			h.position = r.heart
			add_child(h)
			_hearts[r.id] = h
		elif _hearts.has(r.id) and d > HEART_DROP:
			_hearts[r.id].queue_free()
			_hearts.erase(r.id)


func _stream_pois(who: Array):
	for poi in pois:
		if poi.kind == "ambush":
			continue	# nothing to see until it springs
		var d = _closest(who, poi.pos)
		if not _poi_nodes.has(poi.id) and d < POI_BUILD:
			var n = POI_SCRIPT.new()
			n.poi = poi
			n.zone_path = zone_path
			n.features = self
			n.name = "Poi_" + poi.id
			n.position = poi.pos
			add_child(n)
			_poi_nodes[poi.id] = n
		elif _poi_nodes.has(poi.id) and d > POI_DROP:
			_poi_nodes[poi.id].queue_free()
			_poi_nodes.erase(poi.id)


## "Entering the Ashen Fells": the first time this session as a big notice, after that a small one.
func _track_region():
	var me = Zones.player
	if regions.is_empty() or me == null or not is_instance_valid(me) or not me.is_inside_tree() or Zones.zone_of(me) != Zones.zone_of(self):
		return
	var r = Regions.at(zone_path, me.global_position)
	if r.is_empty() or r.id == _region_id:
		return
	var first_check = _region_id == ""	# just arrived in the zone: the zone's own notice is showing
	_region_id = r.id
	var key = zone_path + "|" + r.id
	var what = "%s · %s" % [Regions.template_label(r), SkinManager.element_label(r.element)]
	if not Regions.entered.has(key):
		Regions.mark_entered(zone_path, r.id)
		if not first_check:
			GameState.notify("Entering %s  (%s)" % [Regions.the(r), what])
		Story.once("region:" + key, "Walked into %s in %s." % [Regions.the(r), GameState.ZONE_NAMES.get(zone_path, "")])
		Traits.nudge("roam", -1.0, "explored " + r.name)	# Wanderer
	elif me.has_method("_float_text"):
		me._float_text(r.name, r.color.lightened(0.3))


## The HUD arrow: your region's heart while its boss stands, otherwise the nearest region still to free.
## {pos, text} or {} when there's nothing left.
func compass_target(from: Vector3) -> Dictionary:
	if regions.is_empty():
		return {}
	var here = Regions.at(zone_path, from)
	if not here.is_empty() and not bosses_down.has(here.id):
		return {pos = here.heart, text = "Heart of " + Regions.the(here), color = here.color}
	var best = {}
	var best_d = INF
	for r in regions:
		if bosses_down.has(r.id):
			continue
		var d = Vector2(r.heart.x - from.x, r.heart.z - from.z).length()
		if d < best_d:
			best = r
			best_d = d
	if best.is_empty():
		return {}
	return {pos = best.heart, text = "Heart of " + Regions.the(best), color = best.color}


# ---------------- Host: bosses, champions, ambushes ----------------

func _host_tick(who: Array):
	if who.is_empty():
		return
	for r in regions:
		if not bosses_down.has(r.id) and not _foes.has(r.id) and _closest(who, r.heart) < BOSS_WAKE:
			_wake_region_boss(r)
	for poi in pois:
		if poi.kind != "champion" and poi.kind != "ambush":
			continue
		if pois_done.has(poi.id) or _foes.has(poi.id):
			continue
		var d = _closest(who, poi.pos)
		if poi.kind == "champion" and d < CHAMPION_WAKE:
			_wake_champion(poi)
		elif poi.kind == "ambush" and d < AMBUSH_TRIGGER:
			_spring_ambush(poi, _nearest_person(who, poi.pos))
	# Groups nobody is fighting, far from everyone: put them away (they come back when someone returns)
	for key in _foes.keys():
		var alive = _foes[key].filter(func(e): return is_instance_valid(e) and not e.is_queued_for_deletion())
		var idle = alive.all(func(e): return not e.aggroed)
		if alive.is_empty() or (idle and alive.all(func(e): return _closest(who, e.global_position) > FOE_DROP)):
			for e in alive:
				e.queue_free()
			_foes.erase(key)
		else:
			_foes[key] = alive


func _spawner():
	return Zones.first(self, "zone_spawner")


func _zone_number() -> int:
	return GameState.ZONE_ORDER.find(zone_path) + 1


## A foe that belongs to the zone's features: not saved with the zone, never put to sleep by the spawner.
func _spawn(tier: int, local_pos: Vector3, diff := 1.0, title := "", element := "", counts := true):
	var e = ENEMY_SCENE.instantiate()
	e.set_meta("landmark", "feature")	# the spawner leaves landmark foes alone
	Zones.root_of(self).add_child(e)
	var p = GameState.dry_spot(to_global(local_pos), self)
	var sp = _spawner()
	if sp:
		p = sp.clamp_to_map(p)
	e.global_position = Vector3(p.x, 1.2, p.z)
	e.setup(diff, tier, element if element != "" else Crafting.roll_enemy_element(zone_path, false, p))
	if title != "":
		e.set_title(title)
	if counts and sp:
		e.enemy_died.connect(sp._on_enemy_died)	# counts toward the 2nd boss like any other kill
	return e


func _ring(center: Vector3, count: int, r_min: float, r_max: float) -> Array:
	var out = []
	for i in count:
		var a = TAU * i / count + randf_range(-0.3, 0.3)
		out.append(center + Vector3(cos(a), 0, sin(a)) * randf_range(r_min, r_max))
	return out


func _wake_region_boss(r: Dictionary):
	var group = []
	var boss = _spawn(2, r.heart + Vector3(0, 0, 5), BOSS_HEALTH, Regions.boss_title(r), r.element, false)
	boss.no_count = true	# not one of the zone's two bosses, and can't be turned
	boss.enemy_died.connect(func(_t): _region_boss_down(r))
	group.append(boss)
	group.append(_spawn(1, r.heart + Vector3(5, 0, -6)))
	for p in _ring(r.heart, randi_range(GUARDS.x, GUARDS.y), 9.0, 15.0):
		group.append(_spawn(0, p))
	_foes[r.id] = group


func _region_boss_down(r: Dictionary):
	if bosses_down.has(r.id):
		return
	var sp = _spawner()
	if sp:
		sp.total_killed += roundi(sp.min_clear * REGION_CREDIT)	# like closing a rift
	Regions.record(zone_path, r.id)	# saved: it stays free next time too
	_announce("region_freed", {id = r.id, by = Landmarks.who()})


func _wake_champion(poi: Dictionary):
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(zone_path + poi.id + "tier")
	var tier = 2 if rng.randf() < 0.35 else 1
	var title = Regions.champion_title(zone_path, poi, tier)
	var group = []
	var champ = _spawn(tier, poi.pos, CHAMPION_HEALTH, title)
	champ.enemy_died.connect(func(_t): _champion_down(poi, title))
	group.append(champ)
	for p in _ring(poi.pos, randi_range(ESCORTS.x, ESCORTS.y), 4.0, 8.0):
		group.append(_spawn(0, p))
	_foes[poi.id] = group


func _champion_down(poi: Dictionary, title: String):
	if pois_done.has(poi.id):
		return
	_announce("champion_down", {id = poi.id, title = title})


func _spring_ambush(poi: Dictionary, target):
	var at = target.global_position if target else to_global(poi.pos)
	var group = []
	for p in _ring(to_local(at), randi_range(AMBUSHERS.x, AMBUSHERS.y), 9.0, 13.0):
		group.append(_spawn(0, p))
	group.append(_spawn(1, to_local(at) + Vector3(randf_range(-12, 12), 0, 12)))
	for e in group:
		e.aggroed = true
		if target:
			e.player = target
	_foes[poi.id] = group
	_announce("ambush", {id = poi.id, x = at.x, z = at.z})


# ---------------- Telling everyone ----------------

func _announce(event: String, data: Dictionary):
	Net.feature_event(self, event, data)
	net_event(event, data)


## Something happened (host and joined players). Personal rewards land here, for each player.
func net_event(event: String, data: Dictionary):
	var here = _local_here()
	match event:
		"region_freed":
			var r = Regions.by_id(zone_path, str(data.get("id", "")))
			if r.is_empty():
				ErrorLog.warn("Zone features: unknown region %s freed in %s" % [data.get("id", ""), zone_path])
				return
			bosses_down[r.id] = true
			if _hearts.has(r.id):
				_hearts[r.id].set_freed(true)
			if here:
				var got = _reward(8, 3)
				GameState.notify("%s is free!  (counts toward the 2nd boss)  %s" % [_cap(Regions.the(r)), got])
				var with = data.get("by", [Story.player_name])
				Story.add("Freed %s in %s%s." % [Regions.the(r), GameState.ZONE_NAMES.get(zone_path, ""),
					(" with " + ", ".join(with.filter(func(n): return n != Story.player_name))) if with.size() > 1 else ""])
				Traits.nudge("pace", 3.0, "freed " + r.name)	# Steadfast
		"champion_down":
			pois_done[str(data.get("id", ""))] = true
			if here:
				GameState.notify("Champion down: %s  %s" % [data.get("title", ""), _reward(5, 2)])
				Story.add("Beat %s in %s." % [data.get("title", "a champion"), GameState.ZONE_NAMES.get(zone_path, "")])
		"ambush":
			pois_done[str(data.get("id", ""))] = true
			var me = Zones.player
			if here and me and Vector2(me.global_position.x - float(data.get("x", 0.0)), me.global_position.z - float(data.get("z", 0.0))).length() < 80.0:
				GameState.notify("AMBUSH!")
		"horde", "calm":
			if here:
				GameState.notify(str(data.get("text", "")))


func _local_here() -> bool:
	var me = Zones.player
	return me != null and is_instance_valid(me) and me.is_inside_tree() and Zones.zone_of(me) == Zones.zone_of(self)


## A personal reward: some gold in your bag and a few resources from this zone. Returns what you got.
func _reward(gold: int, resources: int) -> String:
	GameState.add_gold(gold)
	var q = GameState.zone_quality(zone_path)
	if q <= 0 or resources <= 0:
		return "+%d gold" % gold
	var type = ["ore", "herb", "treesilver", "orchid"].pick_random()
	if GameState.add_resource(type, q, resources):
		return "+%d gold, +%d %s" % [gold, resources, GameState.resource_name(type, q)]
	return "+%d gold (your satchel is full)" % gold


func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)
