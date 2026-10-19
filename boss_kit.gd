extends Node3D
## Boss flair. Every Boss (not Rivals: they have their own powers) gets one of these as a child.
##   - A name with a title ("Dragon the Ashborn"), a glowing aura and a pulsing ring under it
##   - A ROAR the first time it sees you (shockwave, screen shake, it pauses a moment)
##   - Big, readable moves you can dodge: a red circle fills up, then it hits whoever is still inside
##       Quake    3 circles drop on you one after another: keep moving
##       Rampage  a lane lights up, then it charges down it: step aside
##       Firefall circles rain all around you: find a gap
##       Inferno  (rage phases only) a huge ring around ITSELF: back off
##   - Two rage phases (at 66% and 33% health): calls minions, moves faster, attacks more often
##   - Death: slow motion, a flash and a shockwave
## The host runs the moves and does the damage. Online, it sends every warning circle, charge lane,
## shockwave, roar and rage to the joined players (Net.boss_fx -> net_fx), so they see the same fight.
## Names and move words come from the skin ("boss_epithets", "boss_moves").

const MOVE_EVERY = [7.0, 5.5, 4.0]	# seconds between moves, by phase
const SPEED_UP = [1.0, 1.2, 1.4]	# walk speed, by phase
const PHASE_AT = [0.66, 0.33]		# health left when it enrages
const MINIONS = [5, 8]				# trash it calls per rage (plus one thug)
const QUAKE_RADIUS = 3.5
const CHARGE_LEN = 16.0
const CHARGE_WIDTH = 2.6
const CHARGE_TIME = 0.45
const RAIN_COUNT = 7
const RAIN_RADIUS = 2.2
const NOVA_RADIUS = 7.0
const GOLD = Color(1.0, 0.78, 0.2)
const DANGER = Color(1.0, 0.18, 0.1)
const DEFAULT_MOVES = {quake = "Quake", charge = "Rampage", rain = "Firefall", nova = "Inferno"}

var boss		# the enemy this belongs to
var phase := 0
var display_name := ""
var _move_t := 3.0
var _last_move := ""
var _roared := false
var _color := GOLD
var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _t := 0.0
var _charge_left := 0.0
var _charge_dir := Vector3.ZERO
var _charge_hit := []
var _base_speed := 2.0


func _ready():
	boss = get_parent()
	_base_speed = boss.SPEED
	if boss.damage_type != "physical":
		_color = Crafting.ELEMENT_COLORS.get(boss.damage_type, GOLD)
	_make_aura()
	if boss.mirror:	# joined player: the host knows its name and how angry it is
		Net.ask_boss_info.call_deferred(boss.net_id)
	else:
		_name_it.call_deferred()	# after landmarks set their own title ("Lord of ...")


## "Dragon the Ashborn" (landmark bosses keep the title they were given).
func _name_it():
	if not is_instance_valid(boss):
		return
	if boss._title_label:
		display_name = boss._title_label.text
		return
	var titles = SkinManager.section("boss_epithets")
	if typeof(titles) != TYPE_ARRAY or titles.is_empty():
		ErrorLog.warn("Skin has no boss_epithets list: bosses get no title")
		display_name = SkinManager.name_of("enemy_boss_one")
	else:
		display_name = "%s %s" % [SkinManager.name_of("enemy_boss_one"), titles[randi() % titles.size()]]
	boss.set_title(display_name)


func _make_aura():
	_light = OmniLight3D.new()
	_light.light_color = _color
	_light.omni_range = 7.0
	_light.light_energy = 1.4
	_light.position.y = 0.5
	add_child(_light)
	_ring = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 2.2
	cyl.height = 0.03
	_ring.mesh = cyl
	_ring_mat = _flat_mat(Color(_color.r, _color.g, _color.b, 0.3), true)
	_ring.material_override = _ring_mat
	_ring.position.y = -0.95	# just above the floor (floor top 0.2, enemy center 1.2)
	add_child(_ring)


func _physics_process(delta):
	if not is_instance_valid(boss) or not boss.rival.is_empty():	# became a Rival: its own powers take over
		queue_free()
		return
	_t += delta
	# Aura pulses (faster when angry)
	var pulse = 0.5 + 0.5 * sin(_t * (2.0 + phase * 2.0))
	_light.light_energy = 1.0 + 0.8 * pulse + phase * 0.6
	_ring_mat.albedo_color.a = 0.15 + 0.25 * pulse
	_ring.scale = Vector3.ONE * (1.0 + 0.12 * pulse + phase * 0.15)
	if boss.mirror or boss.ally_time > 0.0:
		return
	if _charge_left > 0.0:
		_tick_charge(delta)
		return
	if not boss.aggroed or boss._target_safe or boss.player == null or not is_instance_valid(boss.player):
		return
	if not _roared:
		_roared = true
		_roar("%s awakens!" % display_name)
		_move_t = 2.5
		return
	_check_phase()
	_move_t -= delta
	if _move_t <= 0.0:
		_move_t = MOVE_EVERY[phase] * randf_range(0.85, 1.15)
		_do_move()


# ---------------- Big moments ----------------

func _roar(text: String):
	boss.rooted_time = max(boss.rooted_time, 1.0)	# it stops to roar
	_send("roar", {text = text})
	_roar_fx(text)


func _roar_fx(text: String):
	GameState.notify(text)
	_shockwave(boss.global_position, 14.0, _color)
	_shake_near(boss.global_position, 0.5)


func _check_phase():
	if phase >= PHASE_AT.size() or boss.health > boss.MAX_HEALTH * PHASE_AT[phase]:
		return
	boss.SPEED = _base_speed * SPEED_UP[phase + 1]
	_set_phase(phase + 1)
	_send("phase", {phase = phase})
	_roar("%s is enraged!" % display_name)
	_summon(MINIONS[phase - 1])


## How angry it looks (host and joined players both).
func _set_phase(p: int):
	while phase < p:
		phase += 1
		if phase == 2:	# last stand: bigger, burning red
			boss.get_node("MeshInstance3D").scale *= 1.15
			_color = _color.lerp(DANGER, 0.6)
			_light.light_color = _color
			_ring_mat.albedo_color = Color(_color.r, _color.g, _color.b, _ring_mat.albedo_color.a)


## Minions burst out of the ground around it and come straight for you.
func _summon(count: int):
	var tiers = []
	for i in range(count):
		tiers.append(0)
	tiers.append(1)
	for i in range(tiers.size()):
		var a = TAU * i / tiers.size() + randf() * 0.4
		var p = boss.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, 6.0)
		var e = preload("res://enemy.tscn").instantiate()
		e.set_meta("landmark", "boss_minion")	# not the spawner's: not saved with the zone
		boss.get_parent().add_child(e)
		e.global_position = Vector3(p.x, boss.global_position.y, p.z)
		e.setup(boss.difficulty, tiers[i], boss.damage_type)
		e.aggroed = true
		_wave(e.global_position, 2.5)


func _do_move():
	var moves = ["quake", "charge", "rain"]
	if phase > 0:
		moves.append("nova")
	moves.erase(_last_move)	# never the same twice in a row
	var m = moves[randi() % moves.size()]
	_last_move = m
	_send("shout", {move = m})
	_shout(m)
	match m:
		"quake":
			_quake()
		"charge":
			_charge()
		"rain":
			_rain()
		"nova":
			_telegraph(boss.global_position, NOVA_RADIUS, 1.5, 0.8)
			boss.rooted_time = max(boss.rooted_time, 1.5)


## The move's name flashes over its head.
func _shout(move: String):
	var words = SkinManager.section("boss_moves")
	var word = DEFAULT_MOVES[move]
	if typeof(words) == TYPE_DICTIONARY:
		word = str(words.get(move, word))
	if display_name == "":
		return
	if boss._title_label == null:
		return
	boss._title_label.text = "%s\n%s!" % [display_name, word.to_upper()]
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(boss) and boss._title_label:
			boss._title_label.text = display_name)


func _quake():
	for i in range(3):
		if not is_instance_valid(boss) or not is_instance_valid(boss.player):
			return
		_telegraph(boss.player.global_position, QUAKE_RADIUS, 1.0, 0.6)
		await get_tree().create_timer(0.55).timeout


func _rain():
	var center = boss.player.global_position
	_telegraph(center, RAIN_RADIUS, 1.3, 0.5)
	for i in range(RAIN_COUNT):
		var a = randf() * TAU
		_telegraph(center + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 8.0), RAIN_RADIUS, 1.3 + randf() * 0.4, 0.5)


## A lane lights up; after a moment it charges down it, hitting everyone in the way.
func _charge():
	var to = boss.player.global_position - boss.global_position
	to.y = 0
	if to.length() < 0.5:
		to = Vector3(1, 0, 0)
	_charge_dir = to.normalized()
	boss.rooted_time = max(boss.rooted_time, 1.0)
	_send("lane", {at = boss.global_position, dir = _charge_dir})
	_lane_fx(boss.global_position, _charge_dir)
	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return
	_charge_hit = []
	_charge_left = CHARGE_TIME


## The red lane it's about to charge down (shows for 0.9 s).
func _lane_fx(start: Vector3, dir: Vector3):
	var lane = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(CHARGE_WIDTH, 0.04, CHARGE_LEN)
	lane.mesh = box
	lane.material_override = _flat_mat(Color(DANGER.r, DANGER.g, DANGER.b, 0.35))
	boss.get_parent().add_child(lane)
	lane.global_position = Vector3(start.x, _ground_y(start), start.z) + dir * CHARGE_LEN * 0.5
	lane.look_at(lane.global_position + dir, Vector3.UP)
	get_tree().create_timer(0.9).timeout.connect(lane.queue_free)


func _tick_charge(delta: float):
	_charge_left -= delta
	boss.rooted_time = max(boss.rooted_time, 0.1)	# its own walking stays off while it charges
	boss.move_and_collide(_charge_dir * (CHARGE_LEN / CHARGE_TIME) * delta)
	for m in _targets():
		if m in _charge_hit:
			continue
		if _flat(m.global_position, boss.global_position) <= CHARGE_WIDTH * 0.5 + 0.8:
			_charge_hit.append(m)
			m.take_damage(boss.ATTACK_DAMAGE * 0.7, boss)
			_shake_near(m.global_position, 0.4)
	if _charge_left <= 0.0:
		_wave(boss.global_position, 4.0)


## A red circle that fills up; when full, everyone still in it is hit.
func _telegraph(at: Vector3, radius: float, delay: float, power: float):
	var spot = Vector3(at.x, _ground_y(at), at.z)
	_send("tele", {at = spot, r = radius, d = delay})
	_tele_fx(spot, radius, delay)
	var dmg = boss.ATTACK_DAMAGE * power
	var who = boss
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(who) or not who.is_inside_tree():
		return
	for m in _targets():
		if _flat(m.global_position, spot) <= radius:
			m.take_damage(dmg, who)


## The circle itself: fills up over `delay`, then bursts (everyone sees this; only the host does damage).
func _tele_fx(spot: Vector3, radius: float, delay: float):
	var root = boss.get_parent()
	var edge = _disc(radius, Color(DANGER.r, DANGER.g, DANGER.b, 0.22))
	var fill = _disc(radius, Color(DANGER.r, DANGER.g, DANGER.b, 0.45))
	root.add_child(edge)
	root.add_child(fill)
	edge.global_position = spot
	fill.global_position = spot + Vector3(0, 0.01, 0)
	fill.scale = Vector3(0.01, 1, 0.01)
	var tw = fill.create_tween()
	tw.tween_property(fill, "scale", Vector3.ONE, delay)
	var who = boss
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(edge):
		edge.queue_free()
	if is_instance_valid(fill):
		fill.queue_free()
	if not is_instance_valid(who) or not who.is_inside_tree():
		return
	_shockwave(spot, radius * 1.2, _color)
	_shake_near(spot, 0.25)


# ---------------- Online ----------------

## Host: show this to the joined players in this zone too.
func _send(kind: String, data: Dictionary):
	if Net.is_online() and Net.is_host():
		Net.boss_fx(boss, kind, data)


## A shockwave everyone sees.
func _wave(at: Vector3, radius: float):
	_send("wave", {at = at, r = radius})
	_shockwave(at, radius, _color)


## Joined player: the host says this boss just did something. Show it (no damage here: the host does that).
func net_fx(kind: String, data: Dictionary):
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		return
	if kind in ["tele", "lane", "wave"] and typeof(data.get("at")) != TYPE_VECTOR3:
		ErrorLog.warn("Boss effect '%s' from the host had no spot" % kind)
		return
	match kind:
		"info":
			display_name = str(data.get("name", ""))
			if display_name != "":
				boss.set_title(display_name)
			_set_phase(clampi(int(data.get("phase", 0)), 0, PHASE_AT.size()))
		"roar":
			_roar_fx(str(data.get("text", "")))
		"phase":
			_set_phase(clampi(int(data.get("phase", 0)), 0, PHASE_AT.size()))
		"shout":
			if DEFAULT_MOVES.has(data.get("move")):
				_shout(data.move)
		"tele":
			_tele_fx(data.at, clampf(float(data.get("r", 1.0)), 0.5, 12.0), clampf(float(data.get("d", 1.0)), 0.1, 3.0))
		"lane":
			if typeof(data.get("dir")) == TYPE_VECTOR3:
				_lane_fx(data.at, Vector3(data.dir).normalized())
		"wave":
			_shockwave(data.at, clampf(float(data.get("r", 1.0)), 0.5, 25.0), _color)
		_:
			ErrorLog.warn("Boss effect from the host I don't know: %s" % kind)


# ---------------- Death (enemy.gd calls this) ----------------

## Called just before the boss is freed: slow motion (solo), a flash, a big shockwave.
func on_death():
	if is_instance_valid(boss) and display_name != "":
		GameState.notify("%s has fallen!" % display_name)
	var pos = boss.global_position
	var root = boss.get_parent()
	var flash = OmniLight3D.new()
	flash.light_color = _color
	flash.omni_range = 18.0
	flash.light_energy = 6.0
	root.add_child(flash)
	flash.global_position = pos + Vector3(0, 1.5, 0)
	var tw = flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.2)
	tw.tween_callback(flash.queue_free)
	_shockwave(pos, 20.0, _color, root)
	_shockwave(pos, 10.0, Color(1, 1, 1), root)
	_shake_near(pos, 0.8)
	if not Net.is_online():	# slow motion would slow everyone's game online
		Engine.time_scale = 0.3
		get_tree().create_timer(0.9, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


# ---------------- Helpers ----------------

func _targets() -> Array:
	return (GameState.party(boss) + Zones.all(boss, "pet")).filter(func(m): return is_instance_valid(m) and m.is_inside_tree())


## Height of the ground at this spot (so warnings sit on top of floors and hills, not under them).
func _ground_y(at: Vector3) -> float:
	if not is_inside_tree():
		return 0.25
	var q = PhysicsRayQueryParameters3D.create(Vector3(at.x, at.y + 6.0, at.z), Vector3(at.x, at.y - 8.0, at.z), 1)
	var skip = [boss.get_rid()]
	for m in _targets():
		if m is CollisionObject3D:
			skip.append(m.get_rid())
	q.exclude = skip
	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return 0.25
	return hit.position.y + 0.05


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Screen shake for the player here, if they're close enough to feel it.
func _shake_near(at: Vector3, amount: float):
	var p = Zones.player
	if p and is_instance_valid(p) and p.has_method("add_shake") and _flat(p.global_position, at) < 30.0:
		p.add_shake(amount)


## A ring of light that races outward and fades.
func _shockwave(at: Vector3, radius: float, color: Color, root = null):
	if root == null:
		root = boss.get_parent()
	var w = _disc(1.0, Color(color.r, color.g, color.b, 0.6), true)
	root.add_child(w)
	w.global_position = Vector3(at.x, _ground_y(at) + 0.02, at.z)
	w.scale = Vector3(0.2, 1, 0.2)
	var tw = w.create_tween().set_parallel()
	tw.tween_property(w, "scale", Vector3(radius, 1, radius), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(w.material_override, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(w.queue_free)


func _disc(radius: float, color: Color, glow := false) -> MeshInstance3D:
	var m = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.03
	cyl.radial_segments = 40
	m.mesh = cyl
	m.material_override = _flat_mat(color, glow)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _flat_mat(color: Color, glow := false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat
