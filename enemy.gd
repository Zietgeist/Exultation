extends CharacterBody3D
signal enemy_died(tier)
signal defeated(tier)	# ONCE: when it dies, or when it's turned to your side (whichever first). Clear-counts use this.
var _defeated_sent := false

# Tier settings
enum Tier {TRASH, THUG, MASTER, BOSS}
var tier = Tier.TRASH
const TIER_IDS = {Tier.TRASH: "enemy_trash", Tier.THUG: "enemy_thug", Tier.MASTER: "enemy_master", Tier.BOSS: "enemy_boss"}

# Base stats per tier (aggro raised 1.2x in Oct 2026: 8/12/15/20 -> 9.6/14.4/18/24)
# Health raised Oct 2026 so single strikes matter on big foes: Thug 400 -> 600, Master 1200 -> 2400, Boss 5000 -> 10000
# Then lowered (DPS Boost now caps at x2, not x32) so every class kills in fair time: Master 1500, Boss 6000.
# With a basic weapon's strikes (~75 damage a second): Thug ~8s, Master ~20s, Boss ~80s.
const TIER_STATS = {
	Tier.TRASH:  {health = 100,  damage = 5,  speed = 4.0, aggro = 9.6,  color = Color(0.15, 0.9, 0.13)},
	Tier.THUG:   {health = 600,  damage = 15, speed = 3.0, aggro = 14.4, color = Color(0.2,  0.4, 1.0)},
	Tier.MASTER: {health = 1500, damage = 35, speed = 2.5, aggro = 18.0, color = Color(0.6,  0.0, 0.9)},
	Tier.BOSS:   {health = 6000, damage = 60, speed = 2.0, aggro = 24.0, color = Color(1.0,  0.8, 0.0)},
}

# Energy in the blue orb each tier drops (halved twice in Oct 2026: was 1/2/4/8, then 0.5/1/2/4)
const ORB_ENERGY = {Tier.TRASH: 0.25, Tier.THUG: 0.5, Tier.MASTER: 1.0, Tier.BOSS: 2.0}

const ATTACK_RANGE = 1.2
var MAX_HEALTH = 100.0
var health = MAX_HEALTH
var ATTACK_DAMAGE = 5.0
var SPEED = 4.0
var AGGRO_RANGE = 8.0
const GRAVITY = -9.8
const Pathing = preload("res://pathing.gd")
var _path: Array = []		# waypoints around walls (Thug and up only; Trash walks straight)
var _on_hill := false		# climbing a hill: slow
var smart_path := false		# finds its way around buildings even as Trash
var horde = null			# Real Place director: horde enemies follow its route map straight to you
const HORDE_SPEED = 1.6		# horde enemies sprint
# Turned (Healer's F): fights the other enemies for a while, then dies. Leaves the "enemy" group while
# turned, so players, auras and the spawner all ignore it; it lives in the "ally_mob" group.
var ally_time := 0.0
var turning := false		# a Turn bolt has landed on it: can't be hurt until it turns (a split second)
var ally_buff := 1.0		# the turning player's damage buff (Boost stacks x meal), copied when turned
var _ally_target = null
var _ally_retarget := 0.0
const ALLY_POWER = 4.0		# turned enemies hit this much harder than they did against you
const ALLY_SEEK = 25.0		# looks for enemies this far away; otherwise stays near the party
const ALLY_COLOR = Color(0.35, 1.0, 0.75)
var _slow := 1.0			# ditch slow where it stands (refreshed every 0.25 s)
var _slow_t := 0.0
var _path_t := 0.0			# seconds until the next "is my way blocked?" check

var player = null
var attack_cooldown = 0.0
var aggroed = false
var hunter = false	# hunters (the 2nd Boss) never stop chasing you
var difficulty = 1.0

var net_id = 0			# online: same number on every player's screen
var mirror = false		# online, joined player: a copy of the host's enemy (the host runs it)
var net_target = Vector3.ZERO
var _retarget = 0.0
var rooted_time = 0.0	# held in place (Warden's Root Field): can still swing if you're close
var damage_type = "physical"	# radiant, shadow, nature, storm... (armor can resist these)
var rival := {}		# not empty: a Rival (rivals.gd) {id, label, power, hp, dmg, owner}
var no_count := false	# landmark bosses (Wardens, Guardians, Cavern Lords): not one of the zone's two bosses
var _rival_label: Label3D
var _power_t := 6.0		# seconds to its next power
var _power_on := 0.0	# enrage / harden: seconds left
const POWER_EVERY = 9.0
const SLAM_RADIUS = 4.0

func setup(diff, t = Tier.TRASH, element := "physical"):
	difficulty = diff
	tier = t
	damage_type = element
	var stats = TIER_STATS[tier]
	MAX_HEALTH = roundi(stats.health * difficulty)
	health = MAX_HEALTH
	ATTACK_DAMAGE = stats.damage
	SPEED = stats.speed
	AGGRO_RANGE = stats.aggro
	
	# Set color (from the current skin)
	apply_skin()
	if tier == Tier.BOSS and rival.is_empty() and not has_node("BossKit"):	# title, aura, big dodgeable moves (boss_kit.gd)
		var kit = preload("res://boss_kit.gd").new()
		kit.name = "BossKit"
		add_child(kit)
	if Net.is_host() and not mirror:
		net_id = Net.register_enemy(self)

func _ready():
	# Enemies live on physics layer 3 (not 1), so gear can let a player walk through them.
	# They collide with walls/players (layer 1) but NOT each other: hundreds of enemies shoving each
	# other made physics take ~500 ms a frame in raids. They keep apart with _crowd_push() instead.
	collision_layer = 0
	set_collision_layer_value(3, true)
	set_collision_mask_value(1, true)
	player = Zones.first(self, "party")
	SkinManager.skin_changed.connect(apply_skin)

func apply_skin():
	if not rival.is_empty():
		$MeshInstance3D.material_override = SkinManager.material("enemy_rival", Color(0.75, 0.12, 0.1))
		return
	if damage_type == "physical":
		$MeshInstance3D.material_override = SkinManager.material(TIER_IDS[tier], TIER_STATS[tier].color)
	else:	# glows with its damage type's color
		$MeshInstance3D.material_override = SkinManager.element_material(TIER_IDS[tier], TIER_STATS[tier].color, damage_type, Crafting.ELEMENT_COLORS[damage_type])

func _physics_process(delta):
	if mirror:	# the host moves it; just glide to where the host says it is
		global_position = global_position.lerp(net_target, min(1.0, delta * 12.0))
		return
	if ally_time > 0.0:
		_ally_tick(delta)
		return
	# Chase the closest party member (with friends online, that's not always you)
	_retarget -= delta
	if _retarget <= 0.0 or player == null or not is_instance_valid(player) or not player.is_inside_tree():
		_retarget = 0.3
		player = _closest_party_member()
	if player:
		var distance = global_position.distance_to(player.global_position)
		
		_safe_t -= delta
		if _safe_t <= 0.0:	# neutral towns: no fighting inside the walls
			_safe_t = 0.5
			_target_safe = Landmarks.in_safe(player)
		if _target_safe:
			aggroed = false
			hunter = false
			return
		var notice = AGGRO_RANGE * (Traits.aggro_mult() if player == Zones.player else 1.0)	# Wary: notice you later
		if distance <= notice and not aggroed and not player.get("disguised"):	# a disguised player looks like one of us
			aggroed = true
			call_friends(notice * FRIEND_SHARE)

		# Idle enemies stand still and skip physics (zones can hold hundreds of them)
		if hunter:
			aggroed = true
		if not aggroed:
			return
		velocity.y += GRAVITY * delta
		
		if aggroed:
			# Already close enough to hit and standing on the ground: stand still (no physics). In a raid,
			# hundreds of enemies shoving into you every frame was a big part of the lag.
			_hold = distance <= ATTACK_RANGE * 0.9 and is_on_floor() and _push_t > 0 and _push.length() < 0.5
			var direction = (_chase_point(delta) - global_position)
			direction.y = 0
			direction = direction.normalized()
			_slow_t -= delta
			if _slow_t <= 0.0:	# in a ditch? (checked 4 times a second, not every frame)
				_slow_t = 0.25
				_slow = GameState.slow_factor_at(global_position, self)
				if global_position.y > 2.6 and is_on_floor() and _standing_on_water():	# up on a river's invisible lid
					var dry = GameState.dry_spot(global_position, self)
					global_position = Vector3(dry.x, 1.2, dry.z)
			var speed_now = SPEED * _slow * (GameState.HILL_SPEED if _on_hill else 1.0) * (HORDE_SPEED if horde else 1.0)
			if rooted_time > 0.0:
				rooted_time -= delta
				speed_now = 0.0
			velocity.x = direction.x * speed_now
			velocity.z = direction.z * speed_now
			if speed_now > 0.0:
				var push = _crowd_push()
				velocity.x += push.x
				velocity.z += push.y
			
			attack_cooldown -= delta
			if not rival.is_empty():
				_tick_power(delta, distance)
			if distance <= ATTACK_RANGE * (1.4 if not rival.is_empty() else 1.0):
				if attack_cooldown <= 0:
					var hit = ATTACK_DAMAGE * get_damage_multiplier() * (1.6 if _power_on > 0.0 and rival.get("power") == "enrage" else 1.0)
					player.take_damage(hit, self)
					attack_cooldown = 1.0
	
	if _hold:
		_hold = false
		return
	move_and_slide()
	_on_hill = GameState.on_hill(self)

var _hold := false


## Is the thing under my feet a deep-water box? (The physics can push an enemy up onto its lid.)
func _standing_on_water() -> bool:
	for i in range(get_slide_collision_count()):
		var c = get_slide_collision(i).get_collider()
		if c and c.is_in_group("deep_water"):
			return true
	return false

# ---------------- Crowd: keep apart without physics ----------------
# Enemies don't collide with each other (too slow with hundreds). Instead there's one shared grid of how
# many moving enemies are in each small square, rebuilt once per physics frame. Each enemy steps away
# from crowded squares next to it, so a mob spreads into a ring around you instead of one blob.
const CROWD_CELL = 1.5
const CROWD_PUSH = 1.6		# push per neighbor (m/s)
const CROWD_MAX = 5.0		# strongest push (m/s)
const CROWD_EVERY = 2		# physics frames between re-checks
static var _crowd := {}		# Vector3i(world, cell x, cell z) -> Vector3(count, sum x, sum z)
static var _crowd_frame := -1
var _push := Vector2.ZERO
var _push_t := 0


static func _build_crowd(tree: SceneTree):
	_crowd.clear()
	for e in tree.get_nodes_in_group("enemy") + tree.get_nodes_in_group("ally_mob"):
		if not e.aggroed and e.ally_time <= 0.0:
			continue	# idle enemies stand still
		var p = e.global_position
		var key = Vector3i(e.get_world_3d().get_instance_id() % 1000000, floori(p.x / CROWD_CELL), floori(p.z / CROWD_CELL))
		_crowd[key] = _crowd.get(key, Vector3.ZERO) + Vector3(1.0, p.x, p.z)


## A shove away from crowded spots next to it (x, z).
func _crowd_push() -> Vector2:
	_push_t -= 1
	if _push_t > 0:
		return _push
	_push_t = CROWD_EVERY
	var frame = Engine.get_physics_frames()
	if frame != _crowd_frame:
		_crowd_frame = frame
		_build_crowd(get_tree())
	var p = global_position
	var w = get_world_3d().get_instance_id() % 1000000
	var cx = floori(p.x / CROWD_CELL)
	var cz = floori(p.z / CROWD_CELL)
	var out = Vector2.ZERO
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c = _crowd.get(Vector3i(w, cx + dx, cz + dz))
			if c == null:
				continue
			if dx == 0 and dz == 0:	# my own square: leave myself out
				c -= Vector3(1.0, p.x, p.z)
			if c.x < 0.5:
				continue
			var d = Vector2(p.x - c.y / c.x, p.z - c.z / c.x)
			var l = d.length()
			if l < 0.05:	# right in the middle of them: pick a side
				d = Vector2(randf() - 0.5, randf() - 0.5)
				l = d.length() + 0.001
			var near = clampf(1.0 - l / (CROWD_CELL * 1.5), 0.0, 1.0)
			out += d / l * c.x * near * CROWD_PUSH
	_push = out.limit_length(CROWD_MAX)
	return _push


## Can the Healer's F turn this one? Not Bosses, Rivals or landmark bosses.
func can_turn() -> bool:
	return ally_time <= 0.0 and tier != Tier.BOSS and rival.is_empty() and not no_count and health > 0.0


## Healer's F: fight for the player for `seconds`, then die (loot and kill count as normal).
## buff = the player's damage buff right now; the turned enemy keeps it for its whole time.
func turn_ally(seconds: float, buff := 1.0):
	if not can_turn():
		return
	if mirror:	# the host runs enemies: ask it
		flash()
		_turn_loot()	# the caster gets the loot now, on their own screen
		Net.turn_enemy(net_id, seconds, buff)
		return
	ally_time = seconds
	ally_buff = buff
	_send_defeated()	# turned counts as beaten (a Trial Ground's last foe drops the Sigil now)
	if Zones.first(self, "player"):	# loot is personal: drops for the player here (the caster when solo)
		_turn_loot()
	aggroed = false
	hunter = false
	rooted_time = 0.0
	_path = []
	remove_from_group("enemy")
	add_to_group("ally_mob")
	var m = StandardMaterial3D.new()
	m.albedo_color = ALLY_COLOR
	m.emission_enabled = true
	m.emission = ALLY_COLOR
	m.emission_energy_multiplier = 0.6
	$MeshInstance3D.material_override = m


func _send_defeated():
	if _defeated_sent:
		return
	_defeated_sent = true
	defeated.emit(tier)


## Turned: its blue orb and gold drop right away (not when it dies 20 s later).
func _turn_loot():
	if has_meta("looted"):
		return
	set_meta("looted", true)
	drop_orb()
	drop_gold()


## Turned: chase the closest real enemy and hit it; nothing near -> stay close to the party.
func _ally_tick(delta: float):
	ally_time -= delta
	if ally_time <= 0.0:
		remove_from_group("ally_mob")
		add_to_group("enemy")	# counted like any other kill
		die()
		return
	_ally_retarget -= delta
	if _ally_retarget <= 0.0 or _ally_target == null or not is_instance_valid(_ally_target) or not _ally_target.is_in_group("enemy"):
		_ally_retarget = 0.3
		_ally_target = null
		var best = ALLY_SEEK
		for e in Zones.all(self, "enemy"):
			if not is_instance_valid(e) or e.is_queued_for_deletion() or e.health <= 0:
				continue
			var d = global_position.distance_to(e.global_position)
			if d < best:
				best = d
				_ally_target = e
	var goal = null
	var close_enough = ATTACK_RANGE * 1.5
	if _ally_target:
		goal = _ally_target.global_position
	else:
		var friend = _closest_party_member()
		if friend:
			goal = friend.global_position
			close_enough = 4.0
	velocity.y += GRAVITY * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if goal != null:
		var to = goal - global_position
		to.y = 0.0
		if to.length() > close_enough:
			var dir = to.normalized() * SPEED * (GameState.HILL_SPEED if _on_hill else 1.0)
			var push = _crowd_push()
			velocity.x = dir.x + push.x
			velocity.z = dir.z + push.y
	attack_cooldown -= delta
	if _ally_target and global_position.distance_to(_ally_target.global_position) <= close_enough and attack_cooldown <= 0.0:
		_ally_target.aggroed = true
		_ally_target.take_damage(ATTACK_DAMAGE * get_damage_multiplier() * ALLY_POWER * ally_buff)
		attack_cooldown = 1.0
	move_and_slide()
	_on_hill = GameState.on_hill(self)


## Where to walk next. Trash: straight at the target. Thug, Master, Boss: around walls when blocked.
func _chase_point(delta: float) -> Vector3:
	var goal = player.global_position
	if horde and is_instance_valid(horde):
		return horde.next_point(global_position, goal)
	if tier == Tier.TRASH and not smart_path:
		return goal
	_path_t -= delta
	if _path_t <= 0.0:
		_path_t = randf_range(0.4, 0.6)	# spread the checks out so not every enemy plans on the same frame
		var world = get_world_3d()
		if Pathing.clear_line(world.direct_space_state, global_position, goal):
			_path = []
		else:
			_path = Pathing.find(world, global_position, goal)
	while not _path.is_empty() and Vector2(_path[0].x - global_position.x, _path[0].z - global_position.z).length() < 1.0:
		_path.pop_front()
	return goal if _path.is_empty() else _path[0]


func _closest_party_member():
	var best = null
	var best_d = INF
	for m in GameState.party(self) + Zones.all(self, "pet"):	# pets can be picked on too
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		if m.is_in_group("pet") and not m.alive():
			continue
		# A pet that isn't out gathering doesn't pull enemies (unless this one is already after it)
		if m.is_in_group("pet") and m.has_method("draws_aggro") and not m.draws_aggro() and not (aggroed and m == player):
			continue
		var d = global_position.distance_squared_to(m.global_position)
		if d < best_d:
			best = m
			best_d = d
	return best


## Secondary aggro: when you pull this one, its friends close by come too.
## One jump only: friends pulled this way don't call their own friends.
const FRIEND_SHARE = 0.5	# friends within half this enemy's aggro range

func call_friends(radius: float):
	if radius <= 0.0:
		return
	for e in Zones.all(self, "enemy"):
		if e == self or e.aggroed or e.mirror or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(global_position) <= radius:
			e.aggroed = true	# set directly, so it doesn't call anyone else


## Taunt: chase THIS one (not whoever is closest, like a pet) for a while. Thorns calls this every tick.
func taunt(by, seconds: float):
	if mirror or ally_time > 0.0 or by == null or not is_instance_valid(by):
		return
	player = by
	_retarget = maxf(_retarget, seconds)
	aggroed = true


func root(seconds: float):
	_rooted_until = maxf(_rooted_until, Time.get_ticks_msec() / 1000.0 + seconds)	# (a joined player's copy knows too)
	if mirror:
		Net.root_enemy(net_id, seconds)
		return
	rooted_time = max(rooted_time, seconds)
	aggroed = true


## Held in a Root Field / Stasis Field right now? (totems hit these harder)
func is_rooted() -> bool:
	return rooted_time > 0.0 or Time.get_ticks_msec() / 1000.0 < _rooted_until

var _rooted_until := 0.0


func take_damage(amount):
	if ally_time > 0.0 or turning:	# turned (on your side), or being turned right now: can't be hurt
		return
	if mirror:	# the host decides; show the hit right away
		flash()
		Net.hit_enemy(net_id, amount)
		return
	if not aggroed and not _target_safe:	# hit from afar: it comes for you, and so do its friends
		aggroed = true
		call_friends(AGGRO_RANGE * FRIEND_SHARE)
	if _power_on > 0.0 and rival.get("power") == "harden":
		amount *= 0.5
	health -= amount
	flash()
	if health <= 0:
		die()

func drop_orb() -> void:
	var orb_scene = preload("res://Orb.tscn")
	var orb = orb_scene.instantiate()
	orb.position = global_position
	orb.value = ORB_ENERGY[tier]	# bigger enemies drop more energy
	get_parent().add_child(orb)

func drop_gold() -> void:
	var amount = GameState.take_gold_drop()
	if amount <= 0:
		return
	var orb = preload("res://Orb.tscn").instantiate()
	orb.kind = "gold"
	orb.value = amount
	orb.position = global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	get_parent().add_child(orb)

## Joined player: the host says this enemy died. My own orb and gold drop here.
func mirror_died():
	if Zones.first(self, "player"):
		Story.on_kill(self)
	if tier == Tier.BOSS:
		GameState.add_mark("boss", global_position, self, _mark_name())
		if has_node("BossKit"):
			$BossKit.on_death()
	if not has_meta("looted"):	# a turned enemy already dropped its loot
		drop_orb()
		drop_gold()
	queue_free()


func die():
	if Net.is_host():
		Net.enemy_died(self)
	if not rival.is_empty():
		Rivals.rival_died(self)
	if tier == Tier.BOSS:
		GameState.add_mark("boss", global_position, self, _mark_name())
		if has_node("BossKit"):
			$BossKit.on_death()
	emit_signal("enemy_died", tier)
	_send_defeated()
	if Zones.first(self, "player") and not has_meta("recruited"):	# loot is personal: the host only drops its own if it's here (none for a recruit: it's leaving, not dying)
		Story.on_kill(self)	# my worn gear remembers it
		if is_instance_valid(player) and player.is_in_group("pet"):	# it was going after my pet
			Traits.on_guarded_pet()
			player.guarded()	# it bonds with you a little
		if not has_meta("looted"):	# a turned enemy already dropped its loot when it was turned
			drop_orb()
			drop_gold()
	queue_free()

func get_damage_multiplier():
	var pct = health / MAX_HEALTH * 100
	if pct >= 66:
		return 1.0
	elif pct >= 33:
		return 0.75
	else:
		return 0.5
		


## Quick white flash so you can see the hit land.
func flash():
	$MeshInstance3D.material_override = SkinManager.material("hit_flash", Color(1, 1, 1))
	var t = create_tween()
	t.tween_interval(0.08)
	t.tween_callback(apply_skin)


# ---------------- Rivals (see rivals.gd) ----------------

## This enemy (usually the one that just killed you) becomes a named Rival.
## s = {id, label, power, hp, dmg, owner} from Rivals.stats_for().
var _safe_t := 0.0
var _target_safe := false
var _title_label: Label3D = null

## A name over its head (landmark bosses).
func set_title(text: String):
	if _title_label == null:
		_title_label = Label3D.new()
		_title_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_title_label.position.y = 3.0
		_title_label.font_size = 38
		_title_label.pixel_size = 0.011
		_title_label.outline_size = 10
		_title_label.no_depth_test = true
		_title_label.modulate = Color(1.0, 0.75, 0.35)
		add_child(_title_label)
	_title_label.text = text
	$MeshInstance3D.scale = Vector3.ONE * 1.3


func become_rival(s: Dictionary):
	rival = s
	if has_meta("from_spawner"):	# no longer the spawner's: not saved with the zone, not counted
		remove_meta("from_spawner")
	for c in enemy_died.get_connections():
		if c.callable.get_object() and c.callable.get_object().is_in_group("zone_spawner"):
			enemy_died.disconnect(c.callable)
	tier = Tier.BOSS
	MAX_HEALTH = s.hp
	health = MAX_HEALTH
	ATTACK_DAMAGE = s.dmg
	SPEED = 3.4
	AGGRO_RANGE = TIER_STATS[Tier.BOSS].aggro
	rival_look(s)
	if Net.is_host():
		Net.rival_look_all(self)


## Looks only (mirrors online use this too): big, dark red, with its name over its head.
func rival_look(s: Dictionary):
	rival = s
	$MeshInstance3D.scale = Vector3.ONE * 1.5
	apply_skin()
	if _rival_label == null:
		_rival_label = Label3D.new()
		_rival_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_rival_label.position.y = 3.0
		_rival_label.font_size = 40
		_rival_label.pixel_size = 0.011
		_rival_label.outline_size = 10
		_rival_label.no_depth_test = true
		_rival_label.modulate = Color(1.0, 0.45, 0.35)
		add_child(_rival_label)
	_rival_label.text = s.label


## Its copy of your best skill, every POWER_EVERY seconds while it's fighting.
func _tick_power(delta: float, distance: float):
	_power_on = max(0.0, _power_on - delta)
	_power_t -= delta
	if _power_t > 0.0:
		return
	_power_t = POWER_EVERY
	match rival.power:
		"enrage":
			_power_on = 5.0
		"harden":
			_power_on = 4.0
		"mend":
			health = min(MAX_HEALTH, health + MAX_HEALTH * 0.12)
		"lunge":
			if distance > 3.0 and distance < 14.0:
				var to = player.global_position - global_position
				to.y = 0
				global_position += to.normalized() * (to.length() - 1.5)
		"slam":
			_slam(player.global_position)
	_say(Rivals.POWER_WORDS.get(rival.power, ""))


## Red circle on the ground, then a big hit on everyone still in it a second later. Step out!
func _slam(at: Vector3):
	if Net.is_online() and Net.is_host():	# joined players see the circle too
		Net.boss_fx(self, "slam", {at = at})
	slam_fx(at)
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	for m in GameState.party(self) + Zones.all(self, "pet"):
		if is_instance_valid(m) and Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length() <= SLAM_RADIUS:
			m.take_damage(ATTACK_DAMAGE * 1.5, self)


## Just the red circle (host and joined players).
func slam_fx(at: Vector3):
	var ring = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = SLAM_RADIUS
	cyl.bottom_radius = SLAM_RADIUS
	cyl.height = 0.05
	ring.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.15, 0.1, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	get_parent().add_child(ring)
	ring.global_position = Vector3(at.x, 0.25, at.z)	# floor top is 0.2 (was 0.06: hidden under the floor)
	get_tree().create_timer(1.0).timeout.connect(ring.queue_free)


func _say(text: String):
	if _rival_label == null or text == "":
		return
	_rival_label.text = "%s\n%s!" % [rival.label, text]
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(self) and _rival_label:
			_rival_label.text = rival.label)


## The name the map shows when you hover this boss's mark (its title, or "Dragon" etc.).
func _mark_name() -> String:
	if not rival.is_empty():
		return str(rival.get("label", SkinManager.name_of("enemy_boss_one")))
	if _title_label:
		return _title_label.text
	return SkinManager.name_of(TIER_IDS[tier] + "_one")
