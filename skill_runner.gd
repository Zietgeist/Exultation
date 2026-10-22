extends Node
## Runs a player's class skills (E, Q, F). One of these sits inside each player.
## Skills are DATA (classes/*.json). This file holds the building blocks ("effects")
## that the data points at. Add a new effect here, list it in ClassManager.EFFECTS,
## and any class file (or mod) can use it.
##
## Party: anything that helps "the party" uses GameState.party(), so it already works
## for one player and will work for more once multiplayer arrives.

var player = null		# the CharacterBody3D that owns this
var class_id := "dps"
var cooldowns := {}		# key -> seconds left

# Ongoing effects
var boost_timers := []	# damage_boost: seconds left for each stack (pressing again refreshes them all)
var shield_hp := 0.0
var shield_time := 0.0
var thorns := {}		# thorns_aura: time, dps, reflect, share, middle, outer
var drain := {}			# drain_aura (toggle): params while on
var whirl := {}			# whirlwind: time, dps, radius
var dash_left := 0.0	# dash: distance still to travel
var dash_dir := Vector3.ZERO
var totems := []		# totem: [{node, time, dps, radius}]
var mending := {}		# a Mending Vow sitting on THIS player: heal, jumps, time, wait
var _custom := {}		# key -> script object from a mod

var _tick := 0.0
var _disc: MeshInstance3D = null		# aura ring under the player
var _thorn_rings := []			# thorns: the fainter middle and outer rings
var _shield_ball: MeshInstance3D = null
var _vow_ball: MeshInstance3D = null

const TICK := 0.5
const THORNS_INNER := 2.0		# thorns damage: inner ring x2, middle ring x1, outer ring x0.5
const THORNS_OUTER := 0.5
const ROOTED_TIME_RATE := 0.5	# standing still: thorns and shield run down at half speed
const DASH_SPEED := 45.0
const VOW_COLOR := Color(1.0, 0.85, 0.35)
const DRAIN_COLOR := Color(0.65, 0.2, 0.9)
const TURN_COLOR := Color(0.35, 1.0, 0.75)
const FEAST_COLOR := Color(0.75, 0.15, 0.35)
var _chain_id := 0		# turn_chain: casting again cancels the chain that's still bouncing


func setup(p, id: String):
	player = p
	class_id = Classes.normalize(id)


## Press E, Q or F. Returns true if the skill went off.
func use(key: String) -> bool:
	var s = Classes.skill(class_id, key)
	if s.is_empty():
		return false
	if s.effect == "drain_aura" and not drain.is_empty():
		_stop_drain()	# toggled off (free)
		return true
	if cooldowns.get(key, 0.0) > 0.0:
		return false
	var cost = float(s.get("cost", 0.0))
	if player.energy < cost:
		return false
	var p = Classes.params_at_rank(class_id, key)
	var worked = _run(key, s, p)
	if not worked:
		return false
	player.energy -= cost
	cooldowns[key] = float(s.get("cooldown", 0.0))
	Classes.record_use(class_id, key)
	return true


func _run(key: String, s: Dictionary, p: Dictionary) -> bool:
	match s.effect:
		"heal_self":
			if player.health > player.MAX_HEALTH * 0.5:
				Traits.on_early_heal()	# Wary
			player.heal(p.amount * (1.0 + Crafting.gear_stat("self_heal")))	# Sap Rings
			return true
		"damage_boost":	# every press refreshes ALL stacks to full time, and adds one if not at max
			_add_boost(float(p.multiplier), float(p.duration), int(p.max_stacks))
			return true
		"shield":
			shield_hp = p.absorb * (1.0 + Crafting.gear_stat("shield_absorb"))	# Bark Rings
			shield_time = p.duration
			return true
		"blast":
			_blast(player.mouse_world_point, p)
			return true
		"thorns_aura":
			if not p.has("middle_ring") or not p.has("outer_ring"):
				ErrorLog.warn("thorns_aura needs middle_ring and outer_ring params; using 2 and 3")
			thorns = {time = float(p.duration), dps = p.damage_per_second, reflect = p.reflect, share = p.screen_share,
				middle = float(p.get("middle_ring", 2.0)), outer = float(p.get("outer_ring", 3.0))}
			_tick = 0.0
			return true
		"drain_aura":
			drain = p
			_tick = 0.0
			return true
		"mending":
			# Solo at full health there's nobody to heal: the vow stacks damage instead (like Boost).
			if p.has("solo_boost_multiplier") and GameState.party(player).size() <= 1 and player.health >= player.MAX_HEALTH:
				_add_boost(float(p.solo_boost_multiplier), float(p.solo_boost_duration), int(p.solo_boost_max_stacks))
				return true
			var target = _party_member_near(player.mouse_world_point)
			_runner_of(target).receive_vow({heal = p.heal, jumps = int(p.jumps), time = float(p.duration), wait = 0.0})
			if target != player:
				_line(player.global_position, target.global_position, VOW_COLOR)
			return true
		"dash":
			var to = player.mouse_world_point - player.global_position
			to.y = 0
			if to.length() < 0.5:
				to = -player.global_transform.basis.z
			dash_dir = to.normalized()
			dash_left = p.distance
			player.invulnerable_time = max(player.invulnerable_time, p.safe_time)
			return true
		"whirlwind":
			whirl = {time = float(p.duration), dps = p.damage_per_second, radius = p.radius}
			player.skill_haste = p.speed_bonus
			_tick = 0.0
			return true
		"totem":
			_plant_totem(player.mouse_world_point, p)
			return true
		"root_field":
			_root_field(player.mouse_world_point, p)
			return true
		"turn_chain":
			var first = _turnable_near(player.mouse_world_point, float(p.get("aim_radius", 6.0)), [])
			if first == null:	# nothing at the mouse: the closest one around you
				first = _turnable_near(player.global_position, float(p.get("jump_range", 14.0)), [])
			if first == null:
				player._float_text("Nothing close enough to turn (not Bosses)", TURN_COLOR)
				return false	# no energy spent
			_chain_id += 1	# a chain still bouncing stops here (you clipped it)
			_turn_chain(_chain_id, first, p)
			return true
		"feast":
			var near = _enemies_near(player.global_position, player.special_radius(float(p.screen_share)))
			var n = mini(near.size(), int(p.max_enemies))
			if n <= 0:
				player._float_text("Nothing to feast on", FEAST_COLOR)
				return false
			var heal = float(p.heal_per_enemy) * n
			for m in GameState.party(player):
				m.heal(heal)
			player._float_text("+%d (feast x%d)" % [heal, n], FEAST_COLOR)
			for e in near.slice(0, n):
				_line(e.global_position, player.global_position, FEAST_COLOR, 0.4)
			return true
		"script":	# a mod's own skill: script with  func run(player, params) -> bool
			if not _custom.has(key):
				var obj = load(s.script).new()
				if obj is Node:
					add_child(obj)
				_custom[key] = obj
			if not _custom[key].has_method("run"):
				ErrorLog.fail("Mod skill script %s needs a run(player, params) function" % s.script)
				return false
			return _custom[key].run(player, p)
	ErrorLog.fail("Skill effect not handled: " + str(s.effect))
	return false


## Skill bar / character screen info.
func skill_list() -> Array:
	var out = []
	for key in Classes.KEYS:
		var s = Classes.skill(class_id, key)
		if s.is_empty():
			continue
		var note = ""
		if s.effect == "drain_aura" and not drain.is_empty():
			note = "ON (F to stop)"
		elif s.effect == "mending" and not mending.is_empty():
			note = "Vow on you (%d)" % (mending.jumps + 1)
		out.append({key = key, name = Classes.skill_label(class_id, key), cost = float(s.get("cost", 0.0)),
			cooldown = max(cooldowns.get(key, 0.0), 0.0), soon = false, note = note,
			rank = Classes.rank(class_id, key), about = s.get("about", "")})
	return out


## Short lines about what's running right now (character screen).
func status_lines() -> Array:
	var out = []
	if shield_hp > 0.0:
		out.append("Shield: %d left (%ds)" % [shield_hp, shield_time])
	if not thorns.is_empty():
		out.append("Thorns aura: %ds" % thorns.time)
	if not drain.is_empty():
		out.append("Life drain: on")
	if not whirl.is_empty():
		out.append("Whirlwind: %.1fs" % whirl.time)
	if totems.size() > 0:
		out.append("Totems: %d" % totems.size())
	if not mending.is_empty():
		out.append("Vow on you: heals %d, %d jump(s) left" % [mending.heal, mending.jumps])
	return out


# ---------------- Called by the player ----------------

## Shield soaks damage first. Returns what gets through.
func absorb(amount: float) -> float:
	if shield_hp <= 0.0:
		return amount
	var soaked = min(shield_hp, amount)
	shield_hp -= soaked
	return amount - soaked


## After the player takes a hit.
func on_hurt(amount: float, source):
	if not thorns.is_empty() and source and is_instance_valid(source) and source.has_method("take_damage"):
		source.take_damage(amount * thorns.reflect)
	if not mending.is_empty() and mending.wait <= 0.0:
		_trigger_vow()


## Dash overrides walking while it lasts. Returns null when not dashing.
func dash_velocity():
	if dash_left <= 0.0:
		return null
	return dash_dir * DASH_SPEED


func receive_vow(v: Dictionary):
	mending = v


# ---------------- Every frame ----------------

func _physics_process(delta):
	if player == null:
		return
	for k in cooldowns:
		cooldowns[k] -= delta

	# damage boost stacks run out one by one
	if boost_timers.size() > 0:
		var before = boost_timers.size()
		for i in range(boost_timers.size()):
			boost_timers[i] -= delta
		boost_timers = boost_timers.filter(func(t): return t > 0.0)
		if boost_timers.size() != before:
			_set_boost()

	# Planted (standing still): shield and thorns last twice as long
	var slow_delta = delta * (ROOTED_TIME_RATE if _standing_still() else 1.0)
	if shield_time > 0.0:
		shield_time -= slow_delta
		if shield_time <= 0.0:
			shield_hp = 0.0
	_show_ball("_shield_ball", shield_hp > 0.0, Color(0.4, 0.7, 1.0, 0.25), 1.3, Vector3.ZERO)

	if dash_left > 0.0:	# the player moves at DASH_SPEED while this runs (see dash_velocity)
		dash_left -= DASH_SPEED * delta

	if not mending.is_empty():
		mending.time -= delta
		mending.wait -= delta
		if mending.time <= 0.0:
			mending = {}
	_show_ball("_vow_ball", not mending.is_empty(), Color(VOW_COLOR, 0.9), 0.25, Vector3(0, 1.6, 0))
	if _vow_ball and _vow_ball.visible:
		var a = Time.get_ticks_msec() / 300.0
		_vow_ball.position = Vector3(cos(a) * 0.6, 1.6, sin(a) * 0.6)

	if not whirl.is_empty():
		whirl.time -= delta
		if whirl.time <= 0.0:
			whirl = {}
			player.skill_haste = 0.0

	if not thorns.is_empty():
		thorns.time -= slow_delta
		if thorns.time <= 0.0:
			thorns = {}

	if not drain.is_empty():
		player.energy -= drain.energy_per_second * delta
		if player.energy <= 0.0:
			player.energy = 0.0
			_stop_drain()
			player._float_text("Out of energy", DRAIN_COLOR)

	_tick_totems(delta)
	_update_disc()

	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	if not thorns.is_empty():
		_thorns_tick()
	if not drain.is_empty():
		_drain_tick()
	if not whirl.is_empty():
		for e in _enemies_near(player.global_position, whirl.radius):
			e.aggroed = true
			e.take_damage(whirl.dps * TICK * player.get_damage_multiplier())


## Thorns: three rings. Inner (the old size) x2 damage, middle x1, outer x0.5. All of them taunt,
## so enemies across a huge area walk in and get hurt more the closer they come.
func _thorns_tick():
	var inner = _thorns_inner()
	var center = player.global_position
	# Thorn Rings always, Deep Root Rings while planted
	var boost = 1.0 + Crafting.gear_stat("thorns_damage") + (Crafting.gear_stat("planted_damage") if _standing_still() else 0.0)
	for e in _enemies_near(center, inner * thorns.outer):
		if e.has_method("taunt"):
			e.taunt(player, TICK + 0.2)	# come for me, not my pet
		else:
			e.aggroed = true
		var d = Vector2(e.global_position.x - center.x, e.global_position.z - center.z).length()
		var mult = 1.0
		if d <= inner:
			mult = THORNS_INNER
		elif d > inner * thorns.middle:
			mult = THORNS_OUTER
		e.take_damage(thorns.dps * TICK * mult * boost)


## Inner Thorns ring radius (the old size), grown by Bramble Rings.
func _thorns_inner() -> float:
	return player.special_radius(thorns.share) * (1.0 + Crafting.gear_stat("thorns_reach"))


## True when the player isn't moving (and isn't dashing).
func _standing_still() -> bool:
	return dash_left <= 0.0 and Vector2(player.velocity.x, player.velocity.z).length() < 0.1


# ---------------- Effects ----------------

## Boost stacks ADD up: "multiplier" is the most it can reach with every stack (x2 = 5 stacks of +20%).
var _boost_cap := 1.0
var _boost_max_stacks := 1

## Add a damage stack (or refresh them all when full).
func _add_boost(multiplier: float, duration: float, max_stacks: int):
	for i in range(boost_timers.size()):
		boost_timers[i] = duration
	if boost_timers.size() < max_stacks:
		boost_timers.append(duration)
	else:
		player._float_text("Boost refreshed", Color(1, 0.6, 0.3))
	_boost_cap = multiplier
	_boost_max_stacks = max_stacks
	_set_boost()


func _set_boost():
	player.dps_boost_stacks = boost_timers.size()
	player.boost_mult = 1.0 + (_boost_cap - 1.0) * float(player.dps_boost_stacks) / float(max(_boost_max_stacks, 1))
	player._refresh_damage()


## Big hit on everything in a circle around the mouse.
func _blast(center: Vector3, p: Dictionary):
	var radius = player.special_radius(p.screen_share)
	var hit = 0
	for e in _enemies_near(center, radius):
		e.take_damage(p.damage * player.get_damage_multiplier())
		hit += 1
	print("Blast! radius %.1f, hit %d" % [radius, hit])
	_flash_disc(center, radius, Color(1.0, 0.45, 0.1, 0.45), 0.35)


## Life drain: the bigger the crowd, the faster it drains.
## Every enemy in range loses 1% of its MAX life per second for EACH enemy in range
## (10 enemies = 10% a second each), up to max_share_per_second, but at least a little (so trash melts too).
## A part of everything drained heals every party member.
## Gear: Swiftness drains faster (+4% per point, like weapon swings), Vitality heals more (+0.5% share per point).
const DRAIN_SWIFT = 0.04
const DRAIN_VITAL = 0.005

func _drain_tick():
	var faster = 1.0 + Crafting.gear_attr("swiftness") * DRAIN_SWIFT
	var radius = player.special_radius(drain.screen_share)
	var total = 0.0
	var shown = 0
	var near = _enemies_near(player.global_position, radius)
	var share = min(drain.share_per_enemy * near.size(), drain.max_share_per_second)
	for e in near:
		var amount = max(e.MAX_HEALTH * share, drain.min_per_second) * TICK * faster
		amount = min(amount, e.health)
		total += amount
		e.aggroed = true
		e.take_damage(amount)
		if shown < 12:	# a few life streams so you can see it working
			_line(e.global_position, player.global_position, Color(DRAIN_COLOR, 0.6), 0.3)
			shown += 1
	if total <= 0.0:
		return
	var heal = total * (drain.heal_share + Crafting.gear_attr("vitality") * DRAIN_VITAL)
	for m in GameState.party(player):
		m.heal(heal)


## Mending Vow went off: heal whoever carries it, then jump to another party member.
func _trigger_vow():
	var v = mending
	player.heal(v.heal)
	player._float_text("+%d (vow)" % v.heal, VOW_COLOR)
	mending = {}
	if v.jumps <= 0:
		return
	v.jumps -= 1
	v.time = max(v.time, 10.0)
	var others = GameState.party(player).filter(func(m): return m != player and is_instance_valid(m))
	if others.is_empty():
		v.wait = 1.0	# alone: it settles back on you after a moment
		mending = v
		return
	var next = others.pick_random()
	_line(player.global_position, next.global_position, VOW_COLOR)
	_runner_of(next).receive_vow(v)


func _stop_drain():
	drain = {}


func _plant_totem(at: Vector3, p: Dictionary):
	while totems.size() >= int(p.max):
		var old = totems.pop_front()
		if is_instance_valid(old.node):
			old.node.queue_free()
	var node = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.25
	mesh.bottom_radius = 0.5
	mesh.height = 2.5
	node.mesh = mesh
	node.material_override = player._fx_material(Color(0.4, 1.0, 0.6, 0.9))
	Zones.root_of(player).add_child(node)
	node.global_position = Vector3(at.x, 1.25, at.z)
	totems.append({node = node, time = float(p.duration), dps = p.get("damage_per_second", 0.0), radius = p.radius, tick = 0.0, cd = 0.0, p = p})


func _tick_totems(delta):
	for t in totems:
		t.time -= delta
		t.tick -= delta
		if t.p.has("strike_power"):	# fights with YOUR weapon: Strike or Sweep, its own choice
			t.cd -= delta
			if t.cd <= 0.0 and is_instance_valid(t.node):
				t.cd = _totem_attack(t)
			continue
		if t.tick <= 0.0 and is_instance_valid(t.node):	# old style: zaps the 3 closest ("damage_per_second")
			t.tick = TICK
			var near = _enemies_near(t.node.global_position, t.radius)
			near.sort_custom(func(a, b): return a.global_position.distance_to(t.node.global_position) < b.global_position.distance_to(t.node.global_position))
			for e in near.slice(0, 3):	# zaps the 3 closest
				e.take_damage(t.dps * TICK)
				_line(t.node.global_position, e.global_position, Color(0.4, 1.0, 0.6, 0.8), 0.15)
	for t in totems.filter(func(t): return t.time <= 0.0):
		if is_instance_valid(t.node):
			t.node.queue_free()
	totems = totems.filter(func(t): return t.time > 0.0)


## One totem attack, copying the player's weapon. Returns seconds until its next attack.
##   Several enemies close (sweep_when or more): a Sweep on all of them (as many as your Sweep hits).
##   Otherwise: a Strike on the toughest one in reach (bosses first), so big fights end sooner.
func _totem_attack(t: Dictionary) -> float:
	var at = t.node.global_position
	var near = _enemies_near(at, t.radius)
	if near.is_empty():
		return 0.2	# nothing to hit: look again soon
	var mult = 1.0	# totems hit at full strength, even when you're hurt
	var held = 1.0 + float(t.p.get("rooted_bonus", 0.0))	# enemies in your Root / Stasis Field take more from totems
	var speed = maxf(0.1, float(t.p.get("speed", 1.0)))	# attacks this many times faster than you
	if near.size() >= int(t.p.get("sweep_when", 3)):
		near.sort_custom(func(a, b): return a.global_position.distance_to(at) < b.global_position.distance_to(at))
		for e in near.slice(0, player.aoe_max_targets):
			e.take_damage(player.aoe_damage * mult * float(t.p.get("sweep_power", 0.75)) * (held if e.is_rooted() else 1.0))
			_line(at, e.global_position, Color(0.4, 1.0, 0.6, 0.8), 0.2)
		return player.aoe_cooldown_time / speed
	near.sort_custom(func(a, b): return a.tier > b.tier or (a.tier == b.tier and a.health > b.health))
	var target = near[0]
	target.take_damage(player.st_damage * mult * float(t.p.strike_power) * (held if target.is_rooted() else 1.0))
	_line(at + Vector3(0, 0.8, 0), target.global_position, Color(0.7, 1.0, 0.8, 1.0), 0.3)
	return player.st_cooldown_time / speed


func _root_field(center: Vector3, p: Dictionary):
	var radius = player.special_radius(p.screen_share)
	for e in _enemies_near(center, radius):
		e.root(p.duration)
		e.take_damage(p.damage)
	_flash_disc(center, radius, Color(0.35, 0.8, 0.3, 0.35), float(p.duration))


## Healer's F: a bolt lands on an enemy, waits a moment, turns a group there, then jumps on.
## Every jump turns MORE (per_bounce, then +grow each jump), so recasting early wastes the best part.
func _turn_chain(id: int, first, p: Dictionary):
	var at = first
	var from = player.global_position
	var count = int(p.per_bounce)
	var done = []	# already turned (joined players' copies stay "enemies" on their screen for a moment)
	for j in range(int(p.jumps) + 1):
		if id != _chain_id or not is_instance_valid(at):
			return
		var spot = at.global_position
		_line(from, spot, TURN_COLOR, 0.35)
		at.flash()
		at.turning = true	# the bolt has it: it can't be killed while it turns
		await get_tree().create_timer(randf_range(float(p.delay_min), float(p.delay_max))).timeout
		if is_instance_valid(at):
			at.turning = false
			spot = at.global_position
		if id != _chain_id or not is_instance_valid(player):
			return
		if not is_instance_valid(at) or not at.can_turn():	# gone anyway (a friend's hit online): take the nearest one there
			at = _turnable_near(spot, float(p.group_radius), done)
		var group = [at] if at != null else []
		var others = _enemies_near(spot, float(p.group_radius)).filter(func(e): return e != at and e.can_turn() and not e in done)	# (they can't die mid-chain either: they turn at once)
		others.sort_custom(func(a, b): return a.global_position.distance_to(spot) < b.global_position.distance_to(spot))
		group.append_array(others.slice(0, maxi(0, count - group.size())))
		for e in group:
			done.append(e)
			e.turn_ally(float(p.duration), _damage_buff())	# turned enemies inherit your damage buff, as it is right now
			_line(spot, e.global_position, TURN_COLOR, 0.25)
		if j == 0 or group.size() > 0:
			player._float_text("Turned %d" % group.size(), TURN_COLOR)
		count += int(p.grow)
		from = spot
		at = _turnable_near(spot, float(p.jump_range), done)
		if at == null:
			return	# nobody left in reach


## Your damage buff right now: Boost stacks (Battle Cry, solo Mending Vow...) x the meal.
func _damage_buff() -> float:
	return player.boost_mult * (1.0 + GameState.buff_bonus("meal"))


## The turnable enemy closest to a spot (within radius), skipping `skip`.
func _turnable_near(spot: Vector3, radius: float, skip: Array):
	var best = null
	var best_d = radius
	for e in _enemies_near(spot, radius):
		if e in skip or not e.has_method("can_turn") or not e.can_turn():
			continue
		var d = Vector2(e.global_position.x - spot.x, e.global_position.z - spot.z).length()
		if d <= best_d:
			best = e
			best_d = d
	return best


# ---------------- Helpers ----------------

func _enemies_near(center: Vector3, radius: float) -> Array:
	var out = []
	for e in Zones.all(player, "enemy"):
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if Vector2(e.global_position.x - center.x, e.global_position.z - center.z).length() <= radius:
			out.append(e)
	return out


## The party member closest to a spot (yourself if nobody else is near).
func _party_member_near(spot: Vector3):
	var best = player
	var best_d = 3.0	# must point fairly close to someone else
	for m in GameState.party(player):
		if m == player:
			continue
		var d = Vector2(m.global_position.x - spot.x, m.global_position.z - spot.z).length()
		if d < best_d:
			best = m
			best_d = d
	return best


## Vows go through the player (online, that sends it to the right person).
func _runner_of(member):
	return member


## Ring under the player for auras (thorns = green, drain = purple, whirlwind = white).
func _update_disc():
	var color = Color(0, 0, 0, 0)
	var radius = 0.0
	if not drain.is_empty():
		color = Color(DRAIN_COLOR, 0.22)
		radius = player.special_radius(drain.screen_share)
	elif not thorns.is_empty():
		color = Color(0.3, 0.9, 0.3, 0.25)
		radius = _thorns_inner()
	elif not whirl.is_empty():
		color = Color(1, 1, 1, 0.3)
		radius = whirl.radius
	if radius <= 0.0:
		if _disc:
			_disc.queue_free()
			_disc = null
		_update_thorn_rings(0.0)
		return
	if _disc == null:
		_disc = player._make_disc(1.0, color)
		player.add_child(_disc)
		_disc.position = Vector3(0, -0.9, 0)
	_disc.material_override.albedo_color = color
	_disc.scale = Vector3(radius, 1, radius)
	if not whirl.is_empty():
		_disc.rotation.y += 0.4
	_update_thorn_rings(radius)


## Thorns' middle and outer rings: fainter green discs under the main one.
func _update_thorn_rings(inner: float):
	var on = inner > 0.0 and drain.is_empty() and not thorns.is_empty()
	if not on:
		for r in _thorn_rings:
			r.queue_free()
		_thorn_rings = []
		return
	if _thorn_rings.is_empty():
		for i in range(2):
			var ring = player._make_disc(1.0, Color(0.3, 0.9, 0.3, 0.12 if i == 0 else 0.07))
			player.add_child(ring)
			ring.position = Vector3(0, -0.92 - 0.01 * i, 0)
			_thorn_rings.append(ring)
	var sizes = [inner * thorns.middle, inner * thorns.outer]
	for i in range(2):
		_thorn_rings[i].scale = Vector3(sizes[i], 1, sizes[i])


func _show_ball(var_name: String, on: bool, color: Color, radius: float, offset: Vector3):
	var ball = get(var_name)
	if not on:
		if ball:
			ball.visible = false
		return
	if ball == null:
		ball = MeshInstance3D.new()
		var mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = radius * 2.0
		ball.mesh = mesh
		ball.material_override = player._fx_material(color)
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.add_child(ball)
		ball.position = offset
		set(var_name, ball)
	ball.visible = true


func _flash_disc(center: Vector3, radius: float, color: Color, seconds: float):
	var disc = player._make_disc(radius, color)
	Zones.root_of(player).add_child(disc)
	disc.global_position = Vector3(center.x, 0.25, center.z)
	var tween = disc.create_tween()
	tween.tween_property(disc, "scale", Vector3(1.05, 1, 1.05), min(seconds, 0.35))
	tween.parallel().tween_property(disc.material_override, "albedo_color:a", 0.0, seconds)
	tween.tween_callback(disc.queue_free)


## A thin glowing line between two spots that fades out.
func _line(from: Vector3, to: Vector3, color: Color, seconds := 0.25):
	from.y = 1.2
	to.y = 1.2
	var length = from.distance_to(to)
	if length < 0.1:
		return
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, length)
	var line = MeshInstance3D.new()
	line.mesh = mesh
	line.material_override = player._fx_material(color)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Zones.root_of(player).add_child(line)
	line.global_position = (from + to) / 2.0
	line.look_at(to, Vector3.UP)
	player._fade_and_free(line, seconds)
