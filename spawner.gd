extends Node3D
## Fills a zone with enemies.
## - 90% of the zone's enemies are placed across the map when you first arrive
##   (tougher ones farther from the entrance, the 1st Boss in the far corner).
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
const BASE_THUGS = 20
const BASE_MASTERS = 5
const MAX_BOSSES = 2		# always 2: beating both unlocks the next zone

const UPFRONT_SHARE = 0.9	# placed on the map at the start
const SAFE_START_RADIUS = 25.0	# nothing is placed this close to where you walk in
const NEAR_PLAYER_INTERVAL = 10.0	# seconds between "near the player" groups
const NEAR_MIN = 12.0
const NEAR_MAX = 18.0
const ENEMY_REST_HEIGHT = 1.2	# standing on the floor
const WAKE_RADIUS = 45.0		# dormant enemies closer than this become real
const SLEEP_RADIUS = 60.0		# real, calm enemies farther than this go dormant
const STREAM_EVERY = 0.1		# seconds between wake/sleep checks
const MAX_WAKES_PER_CHECK = 40	# spread the work so there are no hitches

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
var MAX_THUGS = BASE_THUGS
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
	min_clear = roundi(BASE_MIN_CLEAR * zone_scale)
	target_total = randi_range(min_clear, roundi(BASE_MAX_CLEAR * zone_scale))
	MAX_MASTERS = maxi(1, roundi(BASE_MASTERS * zone_scale))
	MAX_THUGS = maxi(1, roundi(BASE_THUGS * zone_scale))
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

	# Trash in clumps of 3-6, anywhere past the safe start area
	var placed = 0
	while placed < up_trash:
		var center = _random_spot(entry, SAFE_START_RADIUS)
		for i in range(mini(randi_range(3, 6), up_trash - placed)):
			_place_dormant(0, center + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
			placed += 1
	# Thugs in pairs, a bit farther in
	placed = 0
	while placed < up_thugs:
		var center = _random_spot(entry, max(SAFE_START_RADIUS, far * 0.35))
		for i in range(mini(randi_range(1, 2), up_thugs - placed)):
			_place_dormant(1, center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
			placed += 1
	# Masters alone, deep in the zone
	for i in range(up_masters):
		_place_dormant(2, _random_spot(entry, max(SAFE_START_RADIUS, far * 0.55)))
	# 1st Boss: the farthest of several random spots
	var best = Vector3.ZERO
	for i in range(20):
		var p = _random_spot(entry, 0.0)
		if p.distance_to(entry) > best.distance_to(entry):
			best = p
	_place_dormant(3, best)


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
	if left <= 0:
		return
	var angle = randf() * TAU
	var center = player.global_position + Vector3(cos(angle), 0, sin(angle)) * randf_range(NEAR_MIN, NEAR_MAX)
	for i in range(mini(randi_range(2, 4), left)):
		var t = _pick_from_reserve()
		reserve[t] -= 1
		_make_enemy(t, center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))


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
	return _instantiate(t, pos, -1, _roll_element(t))


## Add an enemy that waits as data until the player comes near, and count it.
## Damage type for a new enemy in this zone.
func _roll_element(t: int) -> String:
	return Crafting.roll_enemy_element(owner.scene_file_path if owner else "", t == 3)


func _place_dormant(t: int, pos: Vector3, h := -1.0, element := ""):
	_count_spawn(t)
	pos = _on_land(pos)
	pos = _away_from_shrines(pos)
	pos.y = ENEMY_REST_HEIGHT
	if element == "":
		element = _roll_element(t)
	_sleep({t = t, p = clamp_to_map(pos), h = h, e = element})


## Keep a little room around shrines, so taking a trial doesn't start in a crowd.
const SHRINE_CLEAR = 9.0

func _away_from_shrines(pos: Vector3) -> Vector3:
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
	var woke = 0
	for s in spots:
		for kx in range(floori((s.x - WAKE_RADIUS) / BUCKET), floori((s.x + WAKE_RADIUS) / BUCKET) + 1):
			for kz in range(floori((s.z - WAKE_RADIUS) / BUCKET), floori((s.z + WAKE_RADIUS) / BUCKET) + 1):
				var b = _buckets.get(Vector2i(kx, kz))
				if b == null:
					continue
				var i = b.size() - 1
				while i >= 0 and woke < MAX_WAKES_PER_CHECK:
					var d = b[i]
					if _nearest(spots, d.p) < WAKE_RADIUS:
						_instantiate(d.t, d.p, d.h, d.get("e", "physical"))
						b.remove_at(i)
						woke += 1
					i -= 1
	for enemy in Zones.all(self, "enemy"):
		if enemy.aggroed or enemy.is_queued_for_deletion() or not enemy.has_meta("from_spawner"):
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
		if enemy.is_queued_for_deletion() or not enemy.rival.is_empty():	# rivals are remembered by Rivals
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
