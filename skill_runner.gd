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
var boost_timers := []	# damage_boost: seconds left for each stack
var shield_hp := 0.0
var shield_time := 0.0
var thorns := {}		# thorns_aura: time, dps, reflect, share
var drain := {}			# drain_aura (toggle): params while on
var whirl := {}			# whirlwind: time, dps, radius
var dash_left := 0.0	# dash: distance still to travel
var dash_dir := Vector3.ZERO
var totems := []		# totem: [{node, time, dps, radius}]
var mending := {}		# a Mending Vow sitting on THIS player: heal, jumps, time, wait
var _custom := {}		# key -> script object from a mod

var _tick := 0.0
var _disc: MeshInstance3D = null		# aura ring under the player
var _shield_ball: MeshInstance3D = null
var _vow_ball: MeshInstance3D = null

const TICK := 0.5
const DASH_SPEED := 45.0
const VOW_COLOR := Color(1.0, 0.85, 0.35)
const DRAIN_COLOR := Color(0.65, 0.2, 0.9)


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
			player.heal(p.amount)
			return true
		"damage_boost":
			if boost_timers.size() >= int(p.max_stacks):
				player._float_text("Boost at max", Color(1, 0.6, 0.3))
				return false
			boost_timers.append(float(p.duration))
			_set_boost(p.multiplier)
			return true
		"shield":
			shield_hp = p.absorb
			shield_time = p.duration
			return true
		"blast":
			_blast(player.mouse_world_point, p)
			return true
		"thorns_aura":
			thorns = {time = float(p.duration), dps = p.damage_per_second, reflect = p.reflect, share = p.screen_share}
			_tick = 0.0
			return true
		"drain_aura":
			drain = p
			_tick = 0.0
			return true
		"mending":
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
			_set_boost(player.boost_base)

	if shield_time > 0.0:
		shield_time -= delta
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
		thorns.time -= delta
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
		for e in _enemies_near(player.global_position, player.special_radius(thorns.share)):
			e.aggroed = true
			e.take_damage(thorns.dps * TICK)
	if not drain.is_empty():
		_drain_tick()
	if not whirl.is_empty():
		for e in _enemies_near(player.global_position, whirl.radius):
			e.aggroed = true
			e.take_damage(whirl.dps * TICK * player.get_damage_multiplier())


# ---------------- Effects ----------------

func _set_boost(multiplier: float):
	player.boost_base = multiplier
	player.dps_boost_stacks = boost_timers.size()
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


## Life drain: the more total life around you, the bigger the drain.
## Each enemy loses a share of its CURRENT life (big for a boss) but at least a little (so trash melts too).
## A part of everything drained heals every party member.
func _drain_tick():
	var radius = player.special_radius(drain.screen_share)
	var total = 0.0
	var shown = 0
	for e in _enemies_near(player.global_position, radius):
		var amount = max(e.health * drain.share_per_second, drain.min_per_second) * TICK
		amount = min(amount, e.health)
		total += amount
		e.aggroed = true
		e.take_damage(amount)
		if shown < 12:	# a few life streams so you can see it working
			_line(e.global_position, player.global_position, Color(DRAIN_COLOR, 0.6), 0.3)
			shown += 1
	if total <= 0.0:
		return
	var heal = total * drain.heal_share
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
	totems.append({node = node, time = float(p.duration), dps = p.damage_per_second, radius = p.radius, tick = 0.0})


func _tick_totems(delta):
	for t in totems:
		t.time -= delta
		t.tick -= delta
		if t.tick <= 0.0 and is_instance_valid(t.node):
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


func _root_field(center: Vector3, p: Dictionary):
	var radius = player.special_radius(p.screen_share)
	for e in _enemies_near(center, radius):
		e.root(p.duration)
		e.take_damage(p.damage)
	_flash_disc(center, radius, Color(0.35, 0.8, 0.3, 0.35), float(p.duration))


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
		radius = player.special_radius(thorns.share)
	elif not whirl.is_empty():
		color = Color(1, 1, 1, 0.3)
		radius = whirl.radius
	if radius <= 0.0:
		if _disc:
			_disc.queue_free()
			_disc = null
		return
	if _disc == null:
		_disc = player._make_disc(1.0, color)
		player.add_child(_disc)
		_disc.position = Vector3(0, -0.9, 0)
	_disc.material_override.albedo_color = color
	_disc.scale = Vector3(radius, 1, radius)
	if not whirl.is_empty():
		_disc.rotation.y += 0.4


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
