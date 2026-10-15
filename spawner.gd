extends Node3D
## Fills a zone with enemies.
## - 90% of the zone's enemies are placed across the map when you first arrive, in PACKS:
##   one leader (a Thug, or a Master deeper in) with 8-20 Trash around it, gathered at the
##   terrain's camps, valleys and hills (terrain_generator.gd pack_sites). Sweep the small ones,
##   strike the leader. Packs that don't fit at a site roam in the open. The 1st Boss is in the far corner.
## - The other 10% show up near the player a few at a time.
## - The 2nd Boss appears near the player once the minimum number of kills is reached.
## - Leaving and coming back (same play session) restores everything, including live enemies.
## - Speed: only enemies near the player actually exist. The rest wait as simple data
##   ("dormant") and wake up as you get close, then go back to sleep when you're far away.

const ENEMY_SCENE = preload("res://enemy.tscn")
const FOG_SCRIPT = preload("res://fog_of_war.gd")

# Zone 1 numbers. Bigger zones scale these up by floor area (see GameState.zone_area_scale).
const BASE_MIN_CLEAR = 227	# must kill at least this many before the 2nd boss can appear
const BASE_MAX_CLEAR = 400	# the zone never holds more than this many
const MAX_ENEMIES = 60000		# huge zones (9, 10) stop here
const CLEAR_KNEE = 12.0

## Kills needed before the 2nd boss. Grows with the zone up to Zone 3's size, then much more slowly:
## Zone 4 ~3,000, Zone 6 ~4,500, Zone 8 ~6,700, Zone 10 ~10,000. Clearing Zone 10 is a big deal.
static func clear_scale(scale: float) -> float:
	return scale if scale <= CLEAR_KNEE else CLEAR_KNEE * pow(scale / CLEAR_KNEE, 0.35)
const BASE_MASTERS = 5
const MAX_BOSSES = 2		# always 2: beating both unlocks the next zone
const DENSITY = 1.33		# Oct 2026: 33% more enemies than before
const PACK_MIN = 8			# small ones per leader
const PACK_MAX = 20
const PACK_AVG = 14
const SITE_PACKS = {camp = 3, valley = 3, hill = 1}	# how many packs gather at each kind of site

const UPFRONT_SHARE = 0.9	# placed on the map at the start
const SAFE_START_RADIUS = 40.0	# nothing is placed this close to where you walk in (or any way in)
const NEAR_PLAYER_INTERVAL = 10.0	# seconds between "near the player" groups
const NEAR_MIN = 24.0	# past the fog (fog_of_war REVEAL_RADIUS 22), and never on screen (see _offscreen_spot)
const NEAR_MAX = 32.0
const ENEMY_REST_HEIGHT = 1.2	# standing on the floor
const WAKE_RADIUS = 45.0		# dormant enemies closer than this become real
const SLEEP_RADIUS = 60.0		# real, calm enemies farther than this go dormant
const STREAM_EVERY = 0.1		# seconds between wake/sleep checks
const MAX_WAKES_PER_CHECK = 12	# spread the work so there are no hitches
var MAX_AWAKE = 60			# at most this many real enemies at once (big zones pack 150-200 into
								# the wake circle, which lags). Nearest wake first; more wake as you kill.

## Sleeping enemies, sorted into 50 x 50 squares so waking only looks near the party
## (huge zones hold tens of thousands). `dormant` gives them all as one list.
const BUCKET = 50.0
var _buckets := {}	# Vector2i square -> [{t = tier, p = position, h = health (-1 = full), e = element}]
var dormant: Array:
	get:
		var out = []
		for b in _buckets.values():
			out.append_array(b)
		return out


func _sleep(d: Dictionary):
	_buckets.get_or_add(Vector2i(floori(d.p.x / BUCKET), floori(d.p.z / BUCKET)), []).append(d)
var _stream_timer = 0.0

# Set when the zone loads (random each visit, so no two runs are the same)
var zone_scale = 1.0
var min_clear = BASE_MIN_CLEAR
var target_total = BASE_MAX_CLEAR
var MAX_TRASH = 200
var MAX_THUGS = 20
var MAX_MASTERS = BASE_MASTERS
var targets_ready = false

# Held back to arrive near the player: [trash, thugs, masters]
var reserve = [0, 0, 0]

# Kill tracking
var total_killed = 0
var trash_killed = 0
var thugs_killed = 0
var masters_killed = 0
var bosses_killed = 0

# Spawn tracking
var total_spawned = 0
var trash_spawned = 0
var thugs_spawned = 0
var masters_spawned = 0
var bosses_spawned = 0

var near_timer = 0.0
var player = null
var level_complete = false
var fog = null

# Everything needed to pick up where we left off in this zone
const SAVED_KEYS = ["zone_scale", "min_clear", "target_total", "MAX_TRASH", "MAX_THUGS", "MAX_MASTERS", "reserve", "total_killed", "trash_killed", "thugs_killed", "masters_killed", "bosses_killed", "total_spawned", "trash_spawned", "thugs_spawned", "masters_spawned", "bosses_spawned", "level_complete"]


func _ready():
	add_to_group("zone_spawner")
	if Zones.zone_of(self) == null:
		return	# not inside the World (zone scene opened on its own): the World reloads it properly
	player = Zones.first(self, "party")
	_setup_zone_targets.call_deferred()	# wait for the floor so we know the zone size


func _setup_zone_targets():
	await get_tree().physics_frame	# let the player finish moving to the entry door
	player = Zones.first(self, "party")
	var saved = GameState.saved_zone_part(self, "spawner")

	fog = FOG_SCRIPT.new()
	fog.saved = GameState.saved_zone_part(self, "fog")
	get_parent().add_child(fog)

	if Net.is_client():	# online, joined: the host runs the enemies, I just show them
		targets_ready = false
		return
	_find_safe_spots()

	if saved != null:
		for key in SAVED_KEYS:
			set(key, saved[key])
		for e in saved.alive:
			_place_dormant(e.t, e.p, e.h, e.get("e", ""))
		_stream()
		targets_ready = true
		print("Back in the zone: %d / %d cleared" % [total_killed, min_clear])
		return

	zone_scale = GameState.zone_area_scale(self)
	min_clear = roundi(BASE_MIN_CLEAR * clear_scale(zone_scale))
	target_total = mini(roundi(randi_range(roundi(BASE_MIN_CLEAR * zone_scale), roundi(BASE_MAX_CLEAR * zone_scale)) * DENSITY), MAX_ENEMIES)
	MAX_MASTERS = maxi(1, roundi(BASE_MASTERS * zone_scale * DENSITY))
	# One leader per pack: Masters lead some, Thugs the rest
	var packs = maxi(MAX_MASTERS + 1, roundi(float(target_total - MAX_MASTERS - MAX_BOSSES) / (PACK_AVG + 1)))
	MAX_THUGS = packs - MAX_MASTERS
	MAX_TRASH = target_total - MAX_THUGS - MAX_MASTERS - MAX_BOSSES
	print("Zone size x%.1f: %d enemies this visit (2nd boss after %d kills). Trash %d, Thugs %d, Masters %d, Bosses %d" % [
		zone_scale, target_total, min_clear, MAX_TRASH, MAX_THUGS, MAX_MASTERS, MAX_BOSSES])
	_initial_spawn()
	targets_ready = true
	_stream()


## Place 90% of the zone's enemies across the map.
func _initial_spawn():
	var entry = player.global_position if player else Vector3.ZERO
	var far = _farthest_distance(entry)

	var up_trash = roundi(MAX_TRASH * UPFRONT_SHARE)
	var up_thugs = roundi(MAX_THUGS * UPFRONT_SHARE)
	var up_masters = roundi(MAX_MASTERS * UPFRONT_SHARE)
	reserve = [MAX_TRASH - up_trash, MAX_THUGS - up_thugs, MAX_MASTERS - up_masters]

	# Packs: a leader + 8-20 Trash, at camps, valleys and hills (Masters take the far ones)
	var leaders = []
	for i in range(up_masters):
		leaders.append(2)
	for i in range(up_thugs):
		leaders.append(1)
	var sizes = _pack_sizes(leaders.size(), up_trash)
	var slots = _site_slots(entry)
	var far_slots = slots.filter(func(sl): return sl.site.p.distance_to(entry) > far * 0.5)
	var at_sites = 0
	for i in range(leaders.size()):
		var slot = null
		if leaders[i] == 2 and not far_slots.is_empty():
			slot = far_slots.pop_back()
			slots.erase(slot)
		elif not slots.is_empty():
			slot = slots.pop_back()
			far_slots.erase(slot)
		var spot = _pack_spot(slot) if slot else [
			_random_spot(entry, SAFE_START_RADIUS if leaders[i] == 1 else max(SAFE_START_RADIUS, far * 0.55)),
			2.5 + sizes[i] * 0.2]
		if slot:
			at_sites += 1
		_place_pack(leaders[i], sizes[i], spot[0], spot[1])
	print("Packs: %d (%d at camps/valleys/hills, %d roaming)" % [leaders.size(), at_sites, leaders.size() - at_sites])
	# 1st Boss: the farthest of several random spots
	var best = Vector3.ZERO
	for i in range(20):
		var p = _random_spot(entry, 0.0)
		if p.distance_to(entry) > best.distance_to(entry):
			best = p
	_place_dormant(3, best)


## How many Trash in each of n packs: 8-20 each, adding up to total.
func _pack_sizes(n: int, total: int) -> Array:
	if n <= 0:
		if total > 0:
			ErrorLog.fail("Spawner: %d Trash but no pack leaders" % total)
		return []
	var sizes = []
	var sum = 0
	for i in range(n):
		sizes.append(randi_range(PACK_MIN, PACK_MAX))
		sum += sizes[-1]
	var diff = total - sum
	var tries = 0
	while diff != 0:
		tries += 1
		var step = 1 if diff > 0 else -1
		var j = randi() % n
		var size = sizes[j] + step
		var relaxed = tries > n * 40	# can't fit in 8-20: go past the limits rather than lose enemies
		if size >= 1 and (relaxed or (size >= PACK_MIN and size <= PACK_MAX)):
			sizes[j] = size
			diff -= step
	return sizes


## Every place a pack can gather: [{site, k = which pack of the site, of = how many it holds}].
func _site_slots(entry: Vector3) -> Array:
	var terrain = Zones.first(self, "zone_terrain")
	if terrain == null or not terrain.has_method("pack_sites"):
		ErrorLog.warn("Spawner: no terrain with pack sites here, so every pack roams in the open")
		return []
	var slots = []
	for site in terrain.pack_sites():
		if Vector2(site.p.x - entry.x, site.p.z - entry.z).length() < SAFE_START_RADIUS + site.r:
			continue	# not right where you walk in
		if not SITE_PACKS.has(site.kind):
			ErrorLog.fail("Spawner: unknown pack site kind '%s'" % site.kind)
			continue
		var cap = SITE_PACKS[site.kind]
		for k in range(cap):
			slots.append({site = site, k = k, of = cap})
	slots.shuffle()
	return slots


## [center, spread] for one pack at a site: between the huts and the fire, inside the valley,
## or at the foot of a hill. Several packs at one site face different ways.
func _pack_spot(slot: Dictionary) -> Array:
	var site = slot.site
	var a = TAU * slot.k / slot.of + randf_range(-0.4, 0.4)
	var dir = Vector3(cos(a), 0, sin(a))
	match site.kind:
		"camp":
			return [site.p + dir * site.r * 0.35, site.r * 0.45]
		"valley":	# mountains fill the outer ~40% of the ring: stay in the middle
			return [site.p + dir * site.r * 0.25, site.r * 0.3]
		_:
			return [site.p + dir * (site.r + 4.0), 5.0]


## A leader in the middle, its Trash around it.
func _place_pack(leader: int, size: int, center: Vector3, spread: float):
	_place_dormant(leader, center)
	for j in range(size):
		var a = randf() * TAU
		var d = 1.5 + spread * sqrt(randf())
		_place_dormant(0, center + Vector3(cos(a), 0, sin(a)) * d)


func _process(delta):
	if level_complete or not targets_ready:
		return
	if not is_instance_valid(player):
		player = Zones.first(self, "party")
		if player == null:
			return

	_stream_timer += delta
	if _stream_timer >= STREAM_EVERY:
		_stream_timer = 0.0
		_stream()

	# The held-back 10%: a small group near the player every so often
	near_timer += delta
	if near_timer >= NEAR_PLAYER_INTERVAL:
		near_timer = 0.0
		_spawn_near_player()

	# 2nd Boss arrives once enough enemies are cleared (or if the 1st is somehow missing)
	if bosses_spawned < MAX_BOSSES and total_killed >= min_clear:
		_spawn_boss_near_player()


func _spawn_near_player():
	var left = reserve[0] + reserve[1] + reserve[2]
	if left <= 0 or in_safe_spot(player.global_position) or Landmarks.in_safe(player) or Zones.all(self, "enemy").size() >= MAX_AWAKE:
		return
	var center = _offscreen_spot()
	if center == null:	# nowhere out of sight right now: try again next time
		return
	for i in range(mini(randi_range(2, 4), left)):
		var t = _pick_from_reserve()
		reserve[t] -= 1
		_make_enemy(t, center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))


## A spot near the player that's OFF the screen, so new enemies never pop in where you can see.
func _offscreen_spot():
	var cam = get_viewport().get_camera_3d() if player == Zones.player else null	# online: friends' screens we can't check; distance + fog still hide it
	for i in range(8):
		var a = randf() * TAU
		var p = clamp_to_map(player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(NEAR_MIN, NEAR_MAX))
		if cam and cam.is_position_in_frustum(p + Vector3(0, ENEMY_REST_HEIGHT, 0)):
			continue
		return p
	return null


func _pick_from_reserve() -> int:
	var roll = randi_range(1, reserve[0] + reserve[1] + reserve[2])
	for t in range(3):
		roll -= reserve[t]
		if roll <= 0:
			return t
	return 0


## The 2nd Boss arrives just off-screen and comes straight for you.
func _spawn_boss_near_player():
	while bosses_spawned < MAX_BOSSES:
		var angle = randf() * TAU
		var boss = _make_enemy(3, player.global_position + Vector3(cos(angle), 0, sin(angle)) * 25.0)
		boss.hunter = true
		boss.aggroed = true
	if Zones.first(self, "player"):
		GameState.notify("A BOSS IS COMING FOR YOU!")


## Create one real enemy of a tier at a spot (kept inside the walls) and count it.
func _make_enemy(t: int, pos: Vector3):
	_count_spawn(t)
	pos = _out_of_camps(pos)
	return _instantiate(t, pos, -1, _roll_element(t))


## Add an enemy that waits as data until the player comes near, and count it.
## Damage type for a new enemy in this zone.
func _roll_element(t: int) -> String:
	return Crafting.roll_enemy_element(owner.scene_file_path if owner else "", t == 3)


func _place_dormant(t: int, pos: Vector3, h := -1.0, element := ""):
	_count_spawn(t)
	pos = _on_land(pos)
	pos = _away_from_shrines(pos)
	pos = _out_of_safe_spots(pos)
	pos.y = ENEMY_REST_HEIGHT
	if element == "":
		element = _roll_element(t)
	pos = clamp_to_map(pos)
	for i in 6:	# pushed off the map edge and clamped back in? try another way round
		if not in_safe_spot(pos):
			break
		pos = _out_of_safe_spots(clamp_to_map(pos + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))))
		pos = clamp_to_map(pos)
	_sleep({t = t, p = pos, h = h, e = element})


## Safe ground at every way in: where you arrived, every gate, every fast-travel stop.
## Nothing is placed inside these circles, and no surprise groups appear while you stand in one.
## Big zones: 40 across. Small zones get smaller circles so they don't swallow the map
## (Zone 1: 25 where you walk in, 15 at the other gates).
var _safe_spots := []	# [{p = Vector3, r = radius}]

func _find_safe_spots():
	var side = min(_half().x, _half().y) * 2.0
	var r_entry = clamp(side * 0.4, 25.0, SAFE_START_RADIUS)
	var r_gate = clamp(side * 0.25, 15.0, SAFE_START_RADIUS)
	_safe_spots = [{p = player.global_position if player else Vector3.ZERO, r = r_entry}]
	for d in Zones.all(self, "door"):
		_safe_spots.append({p = d.global_position, r = r_gate})
	for st in Travel.stations_for(Zones.path_of(self)):	# fast-travel stops (built a little later, so use the list)
		_safe_spots.append({p = st.pos, r = r_gate})


func in_safe_spot(p: Vector3) -> bool:
	for c in _safe_spots:
		if Vector2(p.x - c.p.x, p.z - c.p.z).length() < c.r:
			return true
	return false


func _out_of_safe_spots(pos: Vector3) -> Vector3:
	for i in 3:	# pushing out of one circle can land in the next
		var moved = false
		for c in _safe_spots:
			var d = Vector3(pos.x - c.p.x, 0, pos.z - c.p.z)
			if d.length() < c.r:
				if d.length() < 0.1:
					d = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
				pos = Vector3(c.p.x, pos.y, c.p.z) + d.normalized() * (c.r + randf_range(1, 6))
				moved = true
		if not moved:
			break
	return pos


## Taken strongholds and neutral towns: nothing new appears inside their walls.
func _out_of_camps(pos: Vector3) -> Vector3:
	var path = Zones.path_of(self)
	for l in _landmarks:
		if l.kind != "town" and not (l.kind == "stronghold" and Landmarks.state(path, l.id).has("taken")):
			continue
		var d = Vector3(pos.x - l.pos.x, 0, pos.z - l.pos.z)
		if d.length() < l.size + 8.0:
			pos = l.pos + (d.normalized() if d.length() > 0.1 else Vector3(1, 0, 0)) * (l.size + 8.0) + Vector3(0, pos.y, 0)
	return pos


## Keep a little room around shrines, so taking a trial doesn't start in a crowd.
const SHRINE_CLEAR = 9.0
var _landmarks: Array:
	get:
		return Landmarks.for_zone(Zones.path_of(self))

func _away_from_shrines(pos: Vector3) -> Vector3:
	for l in _landmarks:	# landmarks bring their own foes (or none: neutral towns)
		var dl = Vector3(pos.x - l.pos.x, 0, pos.z - l.pos.z)
		if dl.length() < l.size + 6.0:
			pos = l.pos + (dl.normalized() if dl.length() > 0.1 else Vector3(1, 0, 0)) * (l.size + 6.0) + Vector3(0, pos.y, 0)
	for s in Zones.all(self, "shrine"):
		var d = Vector3(pos.x - s.global_position.x, 0, pos.z - s.global_position.z)
		if d.length() < SHRINE_CLEAR:
			if d.length() < 0.1:
				d = Vector3(1, 0, 0)
			pos = s.global_position + d.normalized() * SHRINE_CLEAR + Vector3(0, pos.y, 0)
	return pos


## Island maps: slide a spot toward the middle until it's on land.
func _on_land(pos: Vector3) -> Vector3:
	var terrain = Zones.first(self, "zone_terrain")
	if terrain == null:
		return pos
	for i in range(25):
		if not terrain.is_water(pos):
			return pos
		pos *= 0.9
	ErrorLog.warn("Spawner: couldn't find land near %s" % pos)
	return pos


func _count_spawn(t: int):
	total_spawned += 1
	match t:
		0: trash_spawned += 1
		1: thugs_spawned += 1
		2: masters_spawned += 1
		3: bosses_spawned += 1


func _instantiate(t: int, pos: Vector3, h: float, element := "physical"):
	var enemy = ENEMY_SCENE.instantiate()
	enemy.connect("enemy_died", _on_enemy_died)
	enemy.set_meta("from_spawner", true)
	Zones.root_of(self).add_child(enemy)  # enemies belong to the zone, so they vanish when it unloads
	pos.y = ENEMY_REST_HEIGHT
	enemy.global_position = _clear_spot(clamp_to_map(pos))
	enemy.call("setup", 1.0, t, element)
	if h > 0.0:
		enemy.health = h
	return enemy


## Wake dormant enemies near the player; put calm, far-away ones back to sleep.
func _stream():
	if not is_instance_valid(player):
		return
	var spots = []	# everyone in the party keeps enemies awake around them
	for m in GameState.party(self):
		if is_instance_valid(m) and m.is_inside_tree():
			spots.append(m.global_position)
	var awake = Zones.all(self, "enemy")
	var room = MAX_AWAKE - awake.size()
	# Too many awake (e.g. after a party spread out): calm ones farthest from everyone go back to sleep
	if room < 0:
		var calm = awake.filter(func(e): return not e.aggroed and not e.is_queued_for_deletion() and e.has_meta("from_spawner") and e.tier != 3)	# bosses never go back to sleep
		calm.sort_custom(func(a, b): return _nearest(spots, a.global_position) > _nearest(spots, b.global_position))
		for e in calm.slice(0, -room):
			_sleep({t = e.tier, p = e.global_position, h = e.health, e = e.damage_type})
			e.queue_free()
		room = 0
	# Bosses wake whenever you're near, even past the cap (only 2 per zone; a boss must never hide)
	for sp in spots:
		for kx in range(floori((sp.x - WAKE_RADIUS) / BUCKET), floori((sp.x + WAKE_RADIUS) / BUCKET) + 1):
			for kz in range(floori((sp.z - WAKE_RADIUS) / BUCKET), floori((sp.z + WAKE_RADIUS) / BUCKET) + 1):
				var b = _buckets.get(Vector2i(kx, kz))
				if b == null:
					continue
				for d in b.filter(func(d): return d.t == 3 and _nearest(spots, d.p) < WAKE_RADIUS):
					b.erase(d)
					_instantiate(d.t, d.p, d.h, d.get("e", "physical"))
	# Wake the NEAREST sleeping ones, up to the cap
	if room > 0:
		var near = []	# [distance, bucket, entry]
		for sp in spots:
			for kx in range(floori((sp.x - WAKE_RADIUS) / BUCKET), floori((sp.x + WAKE_RADIUS) / BUCKET) + 1):
				for kz in range(floori((sp.z - WAKE_RADIUS) / BUCKET), floori((sp.z + WAKE_RADIUS) / BUCKET) + 1):
					var b = _buckets.get(Vector2i(kx, kz))
					if b == null:
						continue
					for d in b:
						var dist = _nearest(spots, d.p)
						if dist < WAKE_RADIUS:
							near.append([dist, b, d])
		near.sort_custom(func(a, b): return a[0] < b[0])
		var woke = 0
		for n in near:
			if woke >= mini(room, MAX_WAKES_PER_CHECK):
				break
			var d = n[2]
			var i = n[1].find(d)
			if i == -1:
				continue
			n[1].remove_at(i)
			_instantiate(d.t, d.p, d.h, d.get("e", "physical"))
			woke += 1
	for enemy in awake:
		if not is_instance_valid(enemy) or enemy.aggroed or enemy.is_queued_for_deletion() or not enemy.has_meta("from_spawner"):
			continue
		if enemy.tier == 3:	# an awake boss stays awake (after it kills you, it waits where you fell)
			continue
		var ep = enemy.global_position
		if _nearest(spots, ep) > SLEEP_RADIUS:
			_sleep({t = enemy.tier, p = ep, h = enemy.health, e = enemy.damage_type})
			enemy.queue_free()


## Flat distance from a spot to the closest of several spots.
func _nearest(spots: Array, p: Vector3) -> float:
	var best = INF
	for s in spots:
		best = min(best, Vector2(p.x - s.x, p.z - s.z).length())
	return best


func _random_spot(entry: Vector3, min_dist: float) -> Vector3:
	var half = _half()
	var p = Vector3.ZERO
	for attempt in range(30):
		p = Vector3(randf_range(-half.x, half.x), 0, randf_range(-half.y, half.y))
		if p.distance_to(Vector3(entry.x, 0, entry.z)) >= min_dist:
			return p
	return p


func _farthest_distance(from: Vector3) -> float:
	var half = _half()
	var best = 0.0
	for c in [Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, -half.y)]:
		best = max(best, c.distance_to(Vector3(from.x, 0, from.z)))
	return best


## Snapshot of progress, including every live enemy (tier, spot, health).
func save_state() -> Dictionary:
	var out = {}
	for key in SAVED_KEYS:
		out[key] = get(key)
	out.reserve = reserve.duplicate()
	var alive = []
	for enemy in Zones.all(self, "enemy"):
		if enemy.is_queued_for_deletion() or not enemy.rival.is_empty() or enemy.has_meta("landmark"):	# rivals / landmark foes bring themselves
			continue
		alive.append({t = enemy.tier, p = enemy.global_position, h = enemy.health, e = enemy.damage_type})
	for d in dormant:
		alive.append(d.duplicate())
	out.alive = alive
	# Live enemies get re-created on return, so don't count them twice
	out.total_spawned -= alive.size()
	for e in alive:
		match e.t:
			0: out.trash_spawned -= 1
			1: out.thugs_spawned -= 1
			2: out.masters_spawned -= 1
			3: out.bosses_spawned -= 1
	return out


func _on_enemy_died(tier):
	total_killed += 1
	if total_killed >= ceili(target_total * 0.99) and Zones.first(self, "player"):	# 99% cleared: Steadfast
		var z = Zones.zone_of(self)
		Traits.on_zone_cleared(Zones.path_of(self), z.zone_name if z else "this zone")
	match tier:
		0: trash_killed += 1
		1: thugs_killed += 1
		2: masters_killed += 1
		3:
			bosses_killed += 1
			if Zones.first(self, "player"):	# credit for players who are here (online, each counts their own)
				GameState.on_boss_killed(bosses_killed, Zones.path_of(self))
			if bosses_killed == MAX_BOSSES and Zones.first(self, "player"):
				GameState.notify("ZONE CLEARED!  Map unlocked (press M)")
	var guardian = Zones.first(self, "guardian")
	if guardian:
		guardian.notify_boss_killed(bosses_killed)


func _half() -> Vector2:
	var floor_node = Zones.first(self, "map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		return floor_node.get_half_size() - Vector2(3.0, 3.0)  # stay a little inside the walls
	ErrorLog.fail("Spawner: no map floor found (floor must be in group map_floor). Using a guess of 45.")
	return Vector2(45.0, 45.0)


func clamp_to_map(pos: Vector3) -> Vector3:
	var half = _half()
	pos.x = clamp(pos.x, -half.x, half.x)
	pos.z = clamp(pos.z, -half.y, half.y)
	return pos


## Nudge a spawn spot so the enemy isn't stuck inside a wall or block.
var _probe: SphereShape3D = null

func _clear_spot(pos: Vector3) -> Vector3:
	if _probe == null:
		_probe = SphereShape3D.new()
		_probe.radius = 0.9
	var space = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	for attempt in range(12):
		var test = pos if attempt == 0 else clamp_to_map(pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
		test.y = ENEMY_REST_HEIGHT
		query.transform = Transform3D(Basis(), test)
		var blocked = false
		for hit in space.intersect_shape(query, 8):
			if hit.collider is StaticBody3D:
				blocked = true
				break
		if not blocked:
			return test
	return pos
