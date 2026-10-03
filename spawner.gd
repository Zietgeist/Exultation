extends Node3D

const ENEMY_SCENE = preload("res://enemy.tscn")
const SPAWN_INTERVAL = 2.0
const SPAWN_RADIUS = 35.0
const MAX_ENEMIES_ON_MAP = 150
const CLEARED_RADIUS = 20.0

# Level population caps
# Zone 1 numbers. Bigger zones scale these up by floor area (see GameState.zone_area_scale).
const BASE_MIN_CLEAR = 227	# must kill at least this many before the 2nd boss can appear
const BASE_MAX_CLEAR = 400	# the zone never holds more than this many
const BASE_THUGS = 20
const BASE_MASTERS = 5
const MAX_BOSSES = 2		# always 2: beating both unlocks the next zone

# Set when the zone loads (random each visit, so no two runs are the same)
var zone_scale = 1.0
var min_clear = BASE_MIN_CLEAR
var target_total = BASE_MAX_CLEAR	# how many enemies this visit will have
var MAX_TRASH = 200
var MAX_THUGS = BASE_THUGS
var MAX_MASTERS = BASE_MASTERS
var total_killed = 0
var targets_ready = false

# Kill tracking
var trash_killed = 0
var thugs_killed = 0
var masters_killed = 0
var bosses_killed = 0
var total_spawned = 0

# Spawn tracking
var trash_spawned = 0
var thugs_spawned = 0
var masters_spawned = 0
var bosses_spawned = 0

var timer = 0.0
var solo_timer = 0.0
var player = null
var cleared_areas = []  # Each entry: {pos, time}
const CLEARED_EXPIRE_TIME = 150.0  # 2.5 minutes
var level_complete = false

func _ready():
	player = get_tree().get_first_node_in_group("player")
	_setup_zone_targets.call_deferred()	# wait for the floor so we know the zone size

func _setup_zone_targets():
	zone_scale = GameState.zone_area_scale()
	min_clear = roundi(BASE_MIN_CLEAR * zone_scale)
	target_total = randi_range(min_clear, roundi(BASE_MAX_CLEAR * zone_scale))
	MAX_MASTERS = maxi(1, roundi(BASE_MASTERS * zone_scale))
	MAX_THUGS = maxi(1, roundi(BASE_THUGS * zone_scale))
	MAX_TRASH = target_total - MAX_THUGS - MAX_MASTERS - MAX_BOSSES
	targets_ready = true
	print("Zone size x%.1f: %d enemies this visit (2nd boss after %d kills). Trash %d, Thugs %d, Masters %d, Bosses %d" % [
		zone_scale, target_total, min_clear, MAX_TRASH, MAX_THUGS, MAX_MASTERS, MAX_BOSSES])


func _process(delta):
	if level_complete or not targets_ready:
		return

	# Clump spawner
	timer += delta
	if timer >= SPAWN_INTERVAL:
		timer = 0.0
		var current_enemies = get_tree().get_nodes_in_group("enemy").size()
		if current_enemies < MAX_ENEMIES_ON_MAP:
			spawn_clump()

	# Solo/duo mid tier spawner
	solo_timer += delta
	if solo_timer >= 10.0:
		solo_timer = 0.0
		spawn_solo_mid()

	# Force spawn bosses at max total
	# Bring in any missing bosses once the zone is spent and enough enemies are cleared
	if total_spawned >= target_total and bosses_spawned < MAX_BOSSES and total_killed >= min_clear:
		force_spawn_remaining_bosses()

	# Track cleared areas
	if player:
		var already_tracked = false
		for area in cleared_areas:
			if player.global_position.distance_to(area.pos) < CLEARED_RADIUS:
				already_tracked = true
				break
		if not already_tracked:
			cleared_areas.append({pos = player.global_position, time = Time.get_ticks_msec() / 1000.0})

	# Expire old cleared areas
	var now = Time.get_ticks_msec() / 1000.0
	cleared_areas = cleared_areas.filter(func(area):
		return (now - area.time) < CLEARED_EXPIRE_TIME)

func is_cleared(pos):
	for area in cleared_areas:
		if pos.distance_to(area.pos) < CLEARED_RADIUS:
			return true
	return false

func get_spawn_odds():
	if trash_killed < 50 * zone_scale:
		return {trash = 95.0, thug = 4.0, master = 0.5, boss = 0.5}
	elif trash_killed < 100 * zone_scale:
		return {trash = 80.0, thug = 15.0, master = 3.0, boss = 2.0}
	elif trash_killed < 150 * zone_scale:
		return {trash = 60.0, thug = 25.0, master = 12.0, boss = 3.0}
	else:
		return {trash = 35.0, thug = 30.0, master = 25.0, boss = 10.0}

## Pick an enemy tier using the current odds. Tiers that hit their cap are skipped.
## Returns -1 if every tier is capped.
func pick_tier():
	var odds = get_spawn_odds()
	var weights = [odds.trash, odds.thug, odds.master, odds.boss]
	if trash_spawned >= MAX_TRASH: weights[0] = 0.0
	if thugs_spawned >= MAX_THUGS: weights[1] = 0.0
	if masters_spawned >= MAX_MASTERS: weights[2] = 0.0
	if bosses_spawned >= MAX_BOSSES: weights[3] = 0.0
	if bosses_spawned >= 1 and total_killed < min_clear: weights[3] = 0.0	# 2nd boss waits

	var total = weights[0] + weights[1] + weights[2] + weights[3]
	if total <= 0.0:
		return -1
	var roll = randf() * total
	for t in range(4):
		roll -= weights[t]
		if roll < 0.0:
			return t
	return 0

func spawn_clump():
	if not player:
		return
	if total_spawned >= target_total:
		return

	var attempts = 0
	var center = Vector3.ZERO
	while attempts < 10:
		var angle = randf() * TAU
		center = player.global_position + Vector3(cos(angle), 0, sin(angle)) * SPAWN_RADIUS
		if not is_cleared(center):
			break
		attempts += 1

	if attempts >= 10:
		return

	var clump_size = randi_range(3, 6)
	for i in range(clump_size):
		if total_spawned >= target_total:
			break

		var offset = Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
		var spawn_pos = center + offset

		if spawn_pos.distance_to(player.global_position) < 20.0:
			continue

		var t = pick_tier()
		if t == -1:
			break

		match t:
			0: trash_spawned += 1
			1: thugs_spawned += 1
			2: masters_spawned += 1
			3: bosses_spawned += 1

		total_spawned += 1
		spawn_pos.y = 1.5
		spawn_pos = clamp_to_map(spawn_pos)
		var enemy = ENEMY_SCENE.instantiate()
		enemy.connect("enemy_died", _on_enemy_died)
		get_tree().current_scene.add_child(enemy)  # enemies belong to the zone, so they vanish when we leave
		enemy.global_position = spawn_pos
		enemy.call("setup", 1.0, t)

func spawn_solo_mid():
	if not player:
		return
	if total_spawned >= target_total:
		return

	var angle = randf() * TAU
	var spawn_pos = player.global_position + Vector3(cos(angle), 0, sin(angle)) * SPAWN_RADIUS
	spawn_pos.y = 1.5
	spawn_pos = clamp_to_map(spawn_pos)

	# Mostly Thugs; sometimes a Master. Respect the caps.
	var t = 1
	if masters_spawned < MAX_MASTERS and randf() < 0.15:
		t = 2
	elif thugs_spawned >= MAX_THUGS:
		return
	var room = (MAX_THUGS - thugs_spawned) if t == 1 else (MAX_MASTERS - masters_spawned)
	var count = min(randi_range(1, 2), room)

	for i in range(count):
		var offset = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		var enemy = ENEMY_SCENE.instantiate()
		enemy.connect("enemy_died", _on_enemy_died)
		get_tree().current_scene.add_child(enemy)  # enemies belong to the zone, so they vanish when we leave
		enemy.global_position = clamp_to_map(spawn_pos + offset)
		enemy.call("setup", 1.0, t)
		match t:
			1: thugs_spawned += 1
			2: masters_spawned += 1
		total_spawned += 1

func force_spawn_remaining_bosses():
	var remaining = MAX_BOSSES - bosses_spawned
	for i in range(remaining):
		var angle = randf() * TAU
		var spawn_pos = player.global_position + Vector3(cos(angle), 0, sin(angle)) * 15.0
		spawn_pos.y = 1.5
		spawn_pos = clamp_to_map(spawn_pos)
		var enemy = ENEMY_SCENE.instantiate()
		enemy.connect("enemy_died", _on_enemy_died)
		get_tree().current_scene.add_child(enemy)  # enemies belong to the zone, so they vanish when we leave
		enemy.global_position = spawn_pos
		enemy.call("setup", 1.0, 3)
		bosses_spawned += 1
	print("BOSSES HAVE ARRIVED!")

func _on_enemy_died(tier):
	total_killed += 1
	match tier:
		0: trash_killed += 1
		1: thugs_killed += 1
		2: masters_killed += 1
		3:
			bosses_killed += 1
			GameState.on_boss_killed(bosses_killed)
	var guardian = get_tree().get_first_node_in_group("guardian")
	if guardian:
		guardian.notify_boss_killed(bosses_killed)

func clamp_to_map(pos: Vector3) -> Vector3:
	var half = Vector2(45.0, 45.0)
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		half = floor_node.get_half_size() - Vector2(3.0, 3.0)  # stay a little inside the walls
	else:
		ErrorLog.fail("Spawner: no map floor found (floor must be in group map_floor). Using a guess of 45.")
	pos.x = clamp(pos.x, -half.x, half.x)
	pos.z = clamp(pos.z, -half.y, half.y)
	return pos
		
