extends CharacterBody3D

var SPEED = 10.0		# armor can change this
const ENEMY_LAYER = 3	# enemies live on physics layer 3 (enemy.gd); walls and you are on layer 1
const BASE_SPEED = 10.0
const GRAVITY = -9.8
var _on_hill := false	# climbing a hill: slow (GameState.HILL_SPEED)
var MAX_HEALTH = 100.0	# armor vitality can raise this
const BASE_MAX_HEALTH = 100.0

# Class: comes from a file in classes/ (see ClassManager.gd). Skills run in skill_runner.gd.
var player_class := "dps"
var class_def := {}
var skills = null		# this player's SkillRunner
var auto = null			# auto-attack, its style and target choice (auto_fight.gd): Tab / wheel / R
var disguised := false	# recruiting guards: enemies take you for one of their own (Landmarks)
var auto_sweep = 3		# old weapon stat, no longer used: the mouse wheel picks the auto-attack style now

# Energy
const MAX_ENERGY = 10.0
var energy = 5.0
var dps_boost_stacks = 0	# damage boost stacks (any class with a damage_boost skill)
var boost_mult = 1.0		# total damage boost right now (stacks add up to the skill's cap, e.g. x2)
var skill_haste = 0.0		# extra move speed from skills (whirlwind)
var _last_pos = Vector3.ZERO

# Action energy comes from blue orbs (see orb.gd). Each class file sets its own regen,
# energy from being hit (tank) and energy from moving (skirmisher).

# Class specials cover a share of the screen (most use 25%).
const SPECIAL_SCREEN_SHARE = 0.25

var mouse_world_point = Vector3.ZERO

# Attack cooldowns
var st_cooldown = 0.0
var aoe_cooldown = 0.0

# Base attack stats
var ST_RANGE = 20.0		# weapon reach x REACH_MULT (spears reach farther)
const REACH_MULT = 2.0	# single strikes reach twice the weapon's listed reach (they were too short)
const AIM_RADIUS = 6.0	# strikes go to the enemy nearest your mouse pointer (within reach)
const AOE_RANGE = 8.0

# Current weapon stats
var weapon_name = "Fists"
var st_damage = 100.0
var aoe_damage = 50.0
var aoe_cone = 0.3
var aoe_max_targets = 4

# Attack speed modifier
var speed_level = 0
const MAX_SPEED_LEVELS = 5
const BASE_ST_COOLDOWN = 2.0
const BASE_AOE_COOLDOWN = 1.0
var st_cooldown_time = BASE_ST_COOLDOWN
var aoe_cooldown_time = BASE_AOE_COOLDOWN
const SPEED_DAMAGE_MODIFIER = 0.15

var health = MAX_HEALTH

@export var camera: Camera3D

signal died(cause)

# Respawn
const SPAWN_HEIGHT = 1.5	# start a little above the floor and drop onto it
const FALL_LIMIT = -10.0	# below this, we fell out of the world
const BASE_CAMERA_OFFSET = Vector3(0, 8, 5)	# the original, closer camera
const CAMERA_ZOOM = 1.5	# camera is 1.5x farther out than the original (same angle)
var _shake := 0.0	# screen shake left (add_shake)
const CAMERA_OFFSET = BASE_CAMERA_OFFSET * CAMERA_ZOOM
const RESPAWN_SAFE_TIME = 2.0	# seconds you can't be hurt after respawning
var spawn_point = Vector3.ZERO
var invulnerable_time = 0.0


var warded := false	# taking a shrine trial: nothing can hurt you

# Online: a stand-in for another player (their game moves it; mine just shows it)
var is_puppet := false
var pet = null		# your gathering pet (pet.gd); not for other players' stand-ins
var peer_id := 0
var puppet_color := Color(0.3, 0.8, 1)
var _net_pos = null
var _net_rot := 0.0


func _ready():
	add_to_group("party")
	if is_puppet:
		_puppet_ready()
		return
	player_class = Classes.normalize(GameState.player_class)
	class_def = Classes.get_def(player_class)
	skills = load("res://skill_runner.gd").new()
	skills.name = "SkillRunner"
	add_child(skills)
	skills.setup(self, player_class)
	auto = load("res://auto_fight.gd").new()
	auto.name = "AutoFight"
	add_child(auto)
	Crafting.changed.connect(apply_gear)
	GameState.buffs_changed.connect(apply_gear)
	Traits.changed.connect(apply_gear)	# who you're becoming changes your stats a little
	apply_gear()
	health = MAX_HEALTH
	if Net.is_online():	# my color, so friends can tell us apart (matches what they see)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Net.color_of(Net.my_id())
		$MeshInstance3D.material_override = mat
	else:
		_apply_skin()
		SkinManager.skin_changed.connect(_apply_skin)
	print("Playing as class: ", Classes.label(player_class))
	pet = preload("res://pet.gd").new()	# follows you between zones and gathers nearby nodes
	pet.setup(self)
	# Zones.travel() places us (arrive) every time we enter a zone


## Just entered a zone (Zones.travel calls this): start next to the door we came in through,
## or at the portal's spot. That's also where we respawn.
func arrive():
	gather_node = null
	lowest_pct = 100
	_hint_node = null
	velocity = Vector3.ZERO
	var z = Zones.zone_of(self)
	spawn_point = Zones.entry_point(z, GameState.previous_scene, GameState.pending_spawn) if z else global_position
	GameState.pending_spawn = null
	spawn_point.y = SPAWN_HEIGHT	# always above the floor
	global_position = spawn_point
	GameState.spawn_home_portal()	# bag still full? the portal home is waiting


func _input(event):
	# Ability keys fire once per press (holding the key no longer drains energy)
	if is_puppet or GameState.ui_open:
		return	# a shop window is open: keys and clicks go to the window
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: drink_potion()
			KEY_E: skills.use("E")
			KEY_Q: skills.use("Q")
			KEY_F: skills.use("F")
			KEY_SPACE:	# the big ability, same as F
				skills.use("F")
				get_viewport().set_input_as_handled()	# so Space doesn't also press a focused menu button
			KEY_G: start_gathering()
			KEY_TAB: auto.toggle()
			KEY_R: auto.next_mode()
			KEY_V: Landmarks.parley(self)	# only while recruiting guards for a stronghold
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click_talking = event.pressed and _click_talk()
		# Mouse wheel: auto-attack style. Up = single target (Strike), down = multi target (Sweep).
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			auto.set_stance("single")
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			auto.set_stance("multi")
		# Side mouse buttons: the big ability, same as F
		if (event.button_index == MOUSE_BUTTON_XBUTTON1 or event.button_index == MOUSE_BUTTON_XBUTTON2) and event.pressed:
			skills.use("F")

## Disguise look: a greenish cloak over you (and a tag), so you know enemies won't notice you.
var _disguise_tag: Label3D = null

func set_disguise(on: bool):
	if on == disguised:
		return
	disguised = on
	var overlay = null
	if on:
		overlay = StandardMaterial3D.new()
		overlay.albedo_color = Color(0.25, 0.75, 0.25, 0.55)
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for c in get_children():
		if c is MeshInstance3D:
			c.material_overlay = overlay
	if on and _disguise_tag == null:
		_disguise_tag = Label3D.new()
		_disguise_tag.text = "(disguised)"
		_disguise_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_disguise_tag.no_depth_test = true
		_disguise_tag.pixel_size = 0.01
		_disguise_tag.font_size = 32
		_disguise_tag.outline_size = 8
		_disguise_tag.modulate = Color(0.6, 1.0, 0.6)
		_disguise_tag.position.y = 2.9
		add_child(_disguise_tag)
	if _disguise_tag:
		_disguise_tag.visible = on


## Attack speed setting (character window, C): + = faster and lighter, - = slower and harder.
func change_attack_speed(step: int):
	speed_level = clampi(speed_level + step, -MAX_SPEED_LEVELS, MAX_SPEED_LEVELS)
	update_attack_speed()
	auto.save()	# remembered with the other controls


func update_attack_speed():
	_refresh_damage()

func _physics_process(delta):
	if is_puppet:
		_puppet_move(delta)
		return
	var direction = Vector3.ZERO

	# Safety net: fell out of the world -> loud warning, back to the gate
	if global_position.y < FALL_LIMIT:
		ErrorLog.fail("Player fell through the floor at %s in %s" % [global_position.round(), GameState.current_zone])
		velocity = Vector3.ZERO
		global_position = spawn_point
		return

	# Blink while safe after respawning
	if invulnerable_time > 0.0:
		invulnerable_time -= delta
		var show_mesh = invulnerable_time <= 0.0 or int(invulnerable_time * 10) % 2 == 0
		for child in get_children():
			if child is MeshInstance3D:
				child.visible = show_mesh
	
	st_cooldown -= delta
	aoe_cooldown -= delta
	fx.tick(delta)
	if stun_time > 0.0:
		stun_time -= delta
	
	var typing = GameState.typing()	# typing a note or a name: don't walk
	if not typing and (Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D)):
		direction.x += 1
	if not typing and (Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A)):
		direction.x -= 1
	if not typing and (Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S)):
		direction.z += 1
	if not typing and (Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W)):
		direction.z -= 1

	if GameState.input_locked or stun_time > 0.0:
		direction = Vector3.ZERO
	if direction.length() > 0:
		direction = direction.normalized()

	var speed_now = SPEED * (1.0 + haste + skill_haste) * fx.speed_mult()	# Gale
	var ditch = GameState.ditch_at(global_position, self)	# slow patches
	if ditch:
		speed_now *= ditch.get_slow_factor()
		ditch.reveal()	# hidden ones show up once you step in
	if _on_hill:	# climbing over a hill / rubble pile
		speed_now *= GameState.HILL_SPEED
	velocity.x = direction.x * speed_now
	velocity.z = direction.z * speed_now
	var dash = skills.dash_velocity()
	if dash != null:
		velocity.x = dash.x
		velocity.z = dash.z
	var wants_to_fly = Input.is_key_pressed(KEY_SHIFT) and not typing and not GameState.ui_open and stun_time <= 0.0
	if not flight.update(self, delta, wants_to_fly):	# flying: it holds you up instead of gravity
		velocity.y += GRAVITY * delta

	var mouse_pos = get_viewport().get_mouse_position()
	var cam = get_viewport().get_camera_3d()
	if cam and abs(cam.project_ray_normal(mouse_pos).y) > 0.001:
		var ray_origin = cam.project_ray_origin(mouse_pos)
		var ray_direction = cam.project_ray_normal(mouse_pos)
		var t = (0.0 - ray_origin.y) / ray_direction.y
		var mouse_world = ray_origin + ray_direction * t
		mouse_world_point = mouse_world
		var look = Vector3(mouse_world.x, global_position.y, mouse_world.z)
		if look.distance_to(global_position) > 0.05:	# mouse right on top of us: keep facing
			look_at(look, Vector3.UP)

	if camera:
		camera.global_position = global_position + CAMERA_OFFSET
		if _shake > 0.0:	# bosses roaring and slamming
			_shake = max(0.0, _shake - delta * 1.5)
			camera.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6

	_tick_gathering(delta)
	_tick_potion(delta)
	if _close_call and health >= MAX_HEALTH * 0.5:	# pulled through
		_close_call = false
		Story.on_saved()
	_update_gather_hint(delta)

	if _click_talking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_click_talking = false	# let go (maybe while a window was open)
	var clicking = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if disguised and clicking and not GameState.ui_open and not _click_talking:	# attacking gives you away
		Landmarks.set_disguise(false, "You attacked: your disguise is off!")
	if auto and not GameState.ui_open and not clicking and not disguised:	# your own clicks always win; no fighting in disguise
		auto.tick()
	if not GameState.ui_open and not _click_talking and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if st_cooldown <= 0:
			single_target_attack()
			st_cooldown = st_cooldown_time

	if not GameState.ui_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if aoe_cooldown <= 0:
			aoe_attack()
			aoe_cooldown = aoe_cooldown_time
	var before_move = global_position
	move_and_slide()
	_on_hill = GameState.on_hill(self)
	_check_stuck(direction, speed_now, delta, before_move)

	# Energy: trickle (per class) + energy for distance moved (skirmisher)
	var e_rules = class_def.get("energy", {})
	var moved = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	if moved > 2.0:
		moved = 0.0	# teleported (respawn, portal), not running
	_last_pos = global_position
	var regen_mult = 1.0 + GameState.buff_bonus("sleep")
	energy = min(energy + e_rules.get("regen", 0.15) * regen_mult * delta + moved * e_rules.get("per_meter_moved", 0.0), MAX_ENERGY)
	

## A single strike. forced = the target auto-attack chose. Your own click: the enemy under
## (or near) the mouse wins; otherwise your main-target rule (R) picks one in reach.
func single_target_attack(forced = null):
	if flight.flying or stun_time > 0.0:
		return	# no attacking from the air, or while stunned
	var closest = forced
	if closest == null:
		var in_reach = []
		var aimed = null
		var aimed_dist = AIM_RADIUS
		for enemy in Zones.all(self, "enemy"):
			if global_position.distance_to(enemy.global_position) > ST_RANGE:
				continue
			in_reach.append(enemy)
			var to_mouse = Vector2(enemy.global_position.x - mouse_world_point.x, enemy.global_position.z - mouse_world_point.z).length()
			if to_mouse < aimed_dist:
				aimed_dist = to_mouse
				aimed = enemy
		if aimed:
			closest = aimed
		elif in_reach.size() > 0:
			closest = auto.pick(in_reach) if auto else in_reach[0]

	if closest:
		var damage = (st_damage * get_damage_multiplier() + _element_damage()) * Traits.damage_mult(health / MAX_HEALTH) * Traits.strike_mult()
		if skills and skills._standing_still():	# planted (classes/*.json "planted_strike", e.g. Tank x3)
			damage *= float(class_def.get("planted_strike", 1.0))
		if randf() < Traits.crit_chance():	# Precision
			damage *= 2.0
			_float_text("Critical!", Color(1, 0.9, 0.3))
		damage *= fx.damage_mult(closest)	# Sunder
		_show_beam(closest.global_position, _beam_color())
		closest.take_damage(damage)
		_on_hit()
		fx.after_hit(self, closest, damage, true)	# Prism, Mace stun
		Traits.on_strike()
		if health < MAX_HEALTH * 0.3:
			Traits.on_hurt_fight()
	else:
		# Miss: a short, faint swing toward where you're facing
		_show_beam(global_position - global_transform.basis.z * 3.0, Color(1.0, 0.9, 0.3, 0.35))

## A sweep in front of you. aim = a direction to face first (auto-attack aims where it catches the most).
func aoe_attack(aim := Vector3.ZERO):
	if flight.flying or stun_time > 0.0:
		return
	if aim != Vector3.ZERO:
		look_at(global_position + aim, Vector3.UP)
	var enemies = Zones.all(self, "enemy")
	var in_range = []
	
	for enemy in enemies:
		var dist = global_position.distance_to(enemy.global_position)
		if dist <= AOE_RANGE:
			var to_enemy = (enemy.global_position - global_position).normalized()
			var facing = -global_transform.basis.z.normalized()
			var dot = facing.dot(to_enemy)
			if dot > aoe_cone - Traits.sweep_cone_shift():	# Fury: wider sweeps
				in_range.append(enemy)
	
	in_range.sort_custom(func(a, b): 
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	
	var targets = in_range.slice(0, aoe_max_targets + Traits.sweep_extra_targets())
	_show_cone()
	Traits.on_sweep()
	if targets.size() > 0 and health < MAX_HEALTH * 0.3:
		Traits.on_hurt_fight()
	for enemy in targets:
		var damage = (aoe_damage * get_damage_multiplier() + _element_damage() * 0.5) * Traits.damage_mult(health / MAX_HEALTH) * fx.damage_mult(enemy)
		enemy.take_damage(damage)
		_on_hit()
		fx.after_hit(self, enemy, damage, false)

var last_attacker = ""	# who hit us last (for the death message)
var last_attacker_node = null	# the enemy itself (rivals are born from what kills you)
var lowest_pct := 100	# lowest health % since entering this zone (Trial Grounds put it in the story)
var _close_call := false	# dropped under 10%: if we get back to 50%, our gear "saved" us

func take_damage(amount, source = null):
	if is_puppet:	# another player: their game takes the hit
		Net.hurt_player(peer_id, amount, source)
		return
	if invulnerable_time > 0.0 or warded or flight.flying:	# nothing reaches you up in the air
		return
	if disguised:	# something hit you: they know what you are now
		Landmarks.set_disguise(false, "Found out! Fight back, then press V to put your disguise back on.")
	if gather_node != null:
		_stop_gathering("Interrupted!")
	if source and "tier" in source:
		last_attacker = SkinManager.name_of(source.TIER_IDS[source.tier] + "_one")
		last_attacker_node = source
	# Damage types: armor and potion wards soak their element
	var element = source.damage_type if source and "damage_type" in source else "physical"
	if element != "physical" and source and "tier" in source:
		last_attacker = SkinManager.name_of(source.TIER_IDS[source.tier] + "_one") + " (" + SkinManager.element_label(element) + ")"
	var raw = amount
	fx.reflect(source, raw)	# Thornskin
	amount *= 1.0 - resistance(element)
	amount *= Traits.damage_taken_mult()	# Steadfast
	amount = skills.absorb(amount)	# shield
	health -= amount
	lowest_pct = min(lowest_pct, int(max(health, 0.0) / MAX_HEALTH * 100.0))
	if health > 0.0 and health < MAX_HEALTH * Story.SAVED_BELOW:
		_close_call = true

	# Some classes (tank) gain energy from taking damage
	energy = min(energy + amount * class_def.get("energy", {}).get("per_damage_taken", 0.0), MAX_ENERGY)

	if health <= 0:
		die(last_attacker)
		return
	skills.on_hurt(raw, source)	# thorns, mending vow


## Any healing (skills, party heals, potions). Never above max.
func heal(amount: float):
	if is_puppet:	# healing a friend: Kin makes it stronger
		Net.heal_player(peer_id, amount * Traits.heal_others_mult())
		Traits.on_heal_other()
		return
	health = min(health + amount, MAX_HEALTH)


## A Mending Vow lands on me (or, for a stand-in, on that player).
func receive_vow(v: Dictionary):
	if is_puppet:
		Net.vow_player(peer_id, v)
		return
	skills.receive_vow(v)


# ---------------- Online stand-in ----------------

func _puppet_ready():
	remove_from_group("player")	# enemies, orbs, doors and the HUD only care about the real me
	add_to_group("remote_player")
	collision_layer = 0
	collision_mask = 0
	var mat = StandardMaterial3D.new()
	mat.albedo_color = puppet_color
	$MeshInstance3D.material_override = mat
	var tag = Label3D.new()
	tag.text = Classes.label(player_class)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 1.6, 0)
	tag.font_size = 40
	tag.pixel_size = 0.012
	tag.outline_size = 10
	tag.modulate = puppet_color
	tag.no_depth_test = true
	add_child(tag)


func net_state(pos: Vector3, rot: float, hp: float, max_hp: float):
	_net_pos = pos
	_net_rot = rot
	health = hp
	MAX_HEALTH = max_hp


func _puppet_move(delta):
	if _net_pos == null:
		return
	if global_position.distance_to(_net_pos) > 8.0:
		global_position = _net_pos	# respawned or teleported
	global_position = global_position.lerp(_net_pos, min(1.0, delta * 15.0))
	rotation.y = lerp_angle(rotation.y, _net_rot, min(1.0, delta * 15.0))

## Token death: back to the entry door with full health. Nothing is lost (for now).
func die(cause := ""):
	GameState.deaths += 1
	_close_call = false
	var killer = last_attacker_node if is_instance_valid(last_attacker_node) else null
	Story.on_death(killer.tier if killer and "tier" in killer else null)
	Rivals.on_player_killed(killer)	# a small enemy that kills you becomes your Rival
	if killer and "tier" in killer and killer.tier == 3 and killer.rival.is_empty():
		GameState.notify("The %s waits where you fell (%d%% health left). It's on your map (M)." % [
			SkinManager.name_of("enemy_boss_one"), roundi(100.0 * killer.health / killer.MAX_HEALTH)])
	GameState.add_mark("death", global_position, self, last_attacker if last_attacker != "" else cause)
	print("DEFEATED by ", cause, ". Respawning at the entry door. Deaths: ", GameState.deaths)
	health = MAX_HEALTH
	velocity = Vector3.ZERO
	global_position = spawn_point
	invulnerable_time = RESPAWN_SAFE_TIME
	# Enemies lose track of you
	for enemy in Zones.all(self, "enemy"):
		enemy.aggroed = false
	died.emit(cause)

## Stunned for a while (Daddy's tickles). On another player's stand-in: their game does it.
func stun(seconds: float, text := "Stunned!"):
	if is_puppet:
		Net.stun_player(peer_id, seconds, text)
		return
	if flight.flying:
		return
	stun_time = maxf(stun_time, seconds)
	_float_text(text, Color(1.0, 0.55, 0.7))


func get_damage_multiplier():
	var pct = health / MAX_HEALTH * 100
	if pct >= 66:
		return 1.0
	elif pct >= 33:
		return 0.75
	else:
		return 0.5

func equip_weapon(weapon: Dictionary):
	weapon_name = weapon.name
	st_damage = weapon.st_damage
	aoe_damage = weapon.aoe_damage
	aoe_cone = weapon.aoe_cone
	aoe_max_targets = weapon.aoe_max_targets
	st_cooldown_time = weapon.st_cooldown_time
	aoe_cooldown_time = weapon.aoe_cooldown_time
	print("Equipped: ", weapon_name)



## Radius of a circle that covers a share of what's on screen (default 25%).
## Measured from the camera each time, so it stays right if the window or camera changes.
func special_radius(share := SPECIAL_SCREEN_SHARE) -> float:
	var cam = get_viewport().get_camera_3d()
	var size = get_viewport().get_visible_rect().size
	var corners = [Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]
	var pts = []
	for c in corners:
		# Measure from where the ORIGINAL (closer) camera would be, so zooming out doesn't grow the specials
		var o = cam.project_ray_origin(c) - (CAMERA_OFFSET - BASE_CAMERA_OFFSET)
		var d = cam.project_ray_normal(c)
		if d.y >= -0.01:
			ErrorLog.warn("special_radius: a screen corner doesn't hit the ground; using 10")
			return 10.0
		var t = -o.y / d.y
		pts.append(Vector2(o.x + d.x * t, o.z + d.z * t))
	var area = 0.0	# shoelace formula for the visible ground area
	for i in range(4):
		var p1 = pts[i]
		var p2 = pts[(i + 1) % 4]
		area += p1.x * p2.y - p2.x * p1.y
	area = abs(area) / 2.0
	return sqrt(area * share / PI)


func _make_disc(radius: float, color: Color) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.05
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## List of skills for the skill HUD: key to press, name, energy cost, cooldown left.
func get_skills() -> Array:
	var list = [
		{key = "LMB", name = "Strike", cost = 0.0, cooldown = max(st_cooldown, 0.0), soon = false},
		{key = "RMB", name = "Sweep", cost = 0.0, cooldown = max(aoe_cooldown, 0.0), soon = false},
	]
	var class_skills = skills.skill_list() if skills else []
	for s in class_skills:
		if s.key != "F":
			list.append(s)
	list.append({key = "1", name = "Potion x%d" % Crafting.potions().size(), cost = 0.0, cooldown = 0.0, soon = false, note = "Make at Chemist" if Crafting.potions().is_empty() else "Drink"})
	for s in class_skills:
		if s.key == "F":
			list.append(s)
	return list


## Blue orbs call this. Returns false if energy is already full (orb stays on the ground).
func add_energy(amount: float) -> bool:
	if energy >= MAX_ENERGY:
		return false
	energy = min(energy + amount, MAX_ENERGY)
	return true


# ---------------- Attack visuals ----------------

## Single target (left click): a bright bolt from you to the target.
func _show_beam(to: Vector3, color: Color):
	var from = global_position
	from.y = 1.2
	to.y = 1.2
	var length = from.distance_to(to)
	if length < 0.1:
		return
	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.18, 0.18, length)
	var beam = MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = _fx_material(color)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Zones.root_of(self).add_child(beam)
	beam.global_position = (from + to) / 2.0
	beam.look_at(to, Vector3.UP)
	_fade_and_free(beam, 0.15)


## Multi target (right click): flash the cone that the attack covers.
var _cone_mesh: ArrayMesh = null
var _cone_built_for = Vector2.ZERO	# (range, cone) the mesh was built for

func _show_cone():
	var key = Vector2(AOE_RANGE, aoe_cone)
	if _cone_mesh == null or _cone_built_for != key:
		_cone_mesh = _build_cone_mesh(AOE_RANGE, acos(clamp(aoe_cone, -1.0, 1.0)))
		_cone_built_for = key
	var cone = MeshInstance3D.new()
	cone.mesh = _cone_mesh
	cone.material_override = _fx_material(Color(0.3, 0.85, 1.0, 0.45))
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Zones.root_of(self).add_child(cone)
	cone.global_position = Vector3(global_position.x, 0.3, global_position.z)
	cone.rotation.y = rotation.y	# face the same way as the player
	_fade_and_free(cone, 0.2)


## A flat fan shape pointing forward (-Z): radius = reach, half_angle in radians.
func _build_cone_mesh(radius: float, half_angle: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps = 18
	for i in range(steps):
		var a0 = -half_angle + 2.0 * half_angle * i / steps
		var a1 = -half_angle + 2.0 * half_angle * (i + 1) / steps
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0) * radius, 0, -cos(a0) * radius))
		st.add_vertex(Vector3(sin(a1) * radius, 0, -cos(a1) * radius))
	return st.commit()


func _fx_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


func _fade_and_free(node: MeshInstance3D, seconds: float):
	var t = node.create_tween()
	t.tween_property(node.material_override, "albedo_color:a", 0.0, seconds)
	t.tween_callback(node.queue_free)


# ---------------- Gathering (G) ----------------
const GATHER_RANGE = 2.5
const GATHER_TIME = 1.5		# seconds; getting hit or walking away interrupts it

var gather_node = null
var gather_left = 0.0
var _gather_start = Vector3.ZERO
var _gather_label: Label3D = null
var _label_tween: Tween = null


## The node G would gather from here (closest one in reach), or null.
## What G would use: a shrine or shopkeeper in reach always comes first (so a tree or ore
## right next to a shrine can't steal the key); otherwise the nearest resource.
func _nearest_gatherable():
	var talk = _nearest_in(Zones.all(self, "npc"))
	if talk != null:
		return talk
	return _nearest_in(Zones.all(self, "resource_node"))


func _nearest_in(nodes: Array):
	var best = null
	var best_d = INF
	for n in nodes:
		var d = n.horizontal_distance(global_position)
		var score = d - n.reach	# nodes up on a hill or trunk count as a bit closer
		if d <= GATHER_RANGE + n.reach and score < best_d:
			best = n
			best_d = score
	return best


const CLICK_PICK = 2.0		# how close to a shrine / shopkeeper the click has to land
const CLICK_TALK_RANGE = 6.0	# how close you have to be for a click to use it
var _click_talking := false	# this left click went to a shrine / shopkeeper: no attack until released


## Left click on a shrine or shopkeeper: use it (same as G). Returns true if the click was used.
func _click_talk() -> bool:
	var best = null
	var best_d = CLICK_PICK
	for n in Zones.all(self, "npc"):
		var d = n.horizontal_distance(mouse_world_point)
		if d < best_d:
			best = n
			best_d = d
	if best == null:
		return false
	if best.horizontal_distance(global_position) > CLICK_TALK_RANGE + best.reach:
		_float_text("Walk closer", Color(0.85, 0.85, 0.85))
		return true
	if gather_node != null:
		_stop_gathering("Stopped")
	best.talk()
	return true


var _hint_node = null
var _hint_timer = 0.0

## Show "G: <name>" over just the one node G would pick.
func _update_gather_hint(delta):
	_hint_timer -= delta
	if _hint_timer > 0.0:
		return
	_hint_timer = 0.1
	var n = _nearest_gatherable()
	if n == _hint_node:
		return
	if is_instance_valid(_hint_node):
		_hint_node.set_highlight(false)
	_hint_node = n
	if n:
		n.set_highlight(true)


func start_gathering():
	if gather_node != null:
		return
	if GameState.ui_open:
		return
	var best = _nearest_gatherable()
	if best != null and best.is_in_group("npc"):
		best.talk()
		return
	if best != null and GameState.satchel_count() >= GameState.satchel_capacity():
		_float_text("Satchel full (%d)" % GameState.satchel_capacity(), Color(1, 0.6, 0.4))
		return
	if best == null:
		var gate = Zones.local_root().get_node_or_null("PomodoroGate") if Zones.local_root() else null
		if gate and gate.shrine and gate.shrine.global_position.distance_to(global_position) < 6.0:
			_float_text("Walk into the shrine to bank your gold", Color(1, 0.85, 0.3))
		else:
			_float_text("Nothing to gather here", Color(0.8, 0.8, 0.8))
		return
	gather_node = best
	gather_left = GATHER_TIME
	_gather_start = global_position


func _tick_gathering(delta):
	if gather_node == null:
		return
	if not is_instance_valid(gather_node) or global_position.distance_to(_gather_start) > 1.0:
		_stop_gathering("Stopped")
		return
	gather_left -= delta
	var dots = ".".repeat(int((GATHER_TIME - gather_left) * 2) % 4)
	_show_gather_label("Gathering" + dots, Color(1, 1, 1))
	if gather_left <= 0.0:
		var n = gather_node
		gather_node = null
		if not GameState.add_resource(n.type, n.quality, n.amount):
			_float_text("Satchel full! Refine at Home (or buy a bigger one at the Inn)", Color(1, 0.6, 0.4))
			return
		_float_text("+%d " % n.amount + GameState.resource_name(n.type, n.quality), GameState.RESOURCE_INFO[n.type].color.lightened(0.3))
		n.queue_free()


func _stop_gathering(reason: String):
	gather_node = null
	_float_text(reason, Color(1, 0.5, 0.4))


func _show_gather_label(text: String, color: Color):
	if _gather_label == null:
		_gather_label = Label3D.new()
		_gather_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_gather_label.position.y = 2.2
		_gather_label.font_size = 40
		_gather_label.pixel_size = 0.012
		_gather_label.outline_size = 10
		_gather_label.no_depth_test = true
		add_child(_gather_label)
	if _label_tween:
		_label_tween.kill()
		_label_tween = null
	_gather_label.text = text
	_gather_label.modulate = color
	_gather_label.modulate.a = 1.0
	_gather_label.visible = true


## Short message above your head that fades away.
func _float_text(text: String, color: Color):
	_show_gather_label(text, color)
	_label_tween = _gather_label.create_tween()
	_label_tween.tween_interval(0.8)
	_label_tween.tween_property(_gather_label, "modulate:a", 0.0, 0.5)
	_label_tween.tween_callback(func(): _gather_label.text = "")	# the outline doesn't fade with it: clear it


# ---------------- Gear, damage types and potions ----------------
var weapon_st_base = 100.0
var weapon_aoe_base = 50.0
var gear_st_cd = BASE_ST_COOLDOWN
var gear_aoe_cd = BASE_AOE_COOLDOWN
var element_bonus = {}		# weapon: extra damage per hit, by type
var lifesteal = 0.0
var armor_resist = {}		# armor: share of each damage type it soaks (0..1)
var ward = {}				# potion: short extra resistances
var ward_time = 0.0
var haste = 0.0
const MAX_RESIST = 0.8
var fx = preload("res://gear_fx.gd").new()	# special effects from special materials (Sunder, Bloom, Prism...)
var flight = preload("res://wings_flight.gd").new()	# wings: hold Shift to fly
var stun_time := 0.0	# stunned (Daddy's tickles): can't move, attack or use skills


## Read what's equipped (Crafting) and set up the character to match.
## Armor can come from many slots (and many rings), so it's added up across everything worn.
func apply_gear():
	var w = Crafting.equipped_weapon()
	if w:
		var e = Crafting.effects(w)
		weapon_name = w.name
		weapon_st_base = e.st
		weapon_aoe_base = e.aoe
		aoe_cone = e.cone
		aoe_max_targets = e.targets
		ST_RANGE = e.reach * REACH_MULT
		auto_sweep = e.auto_sweep
		gear_st_cd = e.st_cd
		gear_aoe_cd = e.aoe_cd
		element_bonus = e.element_bonus
		lifesteal = e.lifesteal
	var weapon_fx = Crafting.effects(w).fx if w else {}
	var weapon_stun = Crafting.effects(w).stun_chance if w else 0.0
	if w == null:	# bare hands
		weapon_name = "Fists"
		weapon_st_base = 100.0 * Crafting.ST_MULT
		weapon_aoe_base = 50.0 * Crafting.AOE_MULT
		aoe_cone = 0.3
		aoe_max_targets = 4
		ST_RANGE = 10.0 * REACH_MULT
		auto_sweep = 3
		gear_st_cd = BASE_ST_COOLDOWN
		gear_aoe_cd = BASE_AOE_COOLDOWN
		element_bonus = {}
		lifesteal = 0.0
	var t = Crafting.armor_totals()
	armor_resist = t.resist
	var all_fx = t.fx.duplicate()
	for k in weapon_fx:
		all_fx[k] = all_fx.get(k, 0.0) + weapon_fx[k]
	fx.set_gear(all_fx, weapon_stun)
	if not is_puppet:
		flight.set_wings(self, t.flight)
	var old_max = MAX_HEALTH
	var stats = class_def.get("stats", {})
	MAX_HEALTH = (BASE_MAX_HEALTH * stats.get("health", 1.0) + t.max_health) * (1.0 + GameState.buff_bonus("tonic")) * Traits.health_mult()
	health = clamp(health + (MAX_HEALTH - old_max), 1.0, MAX_HEALTH)
	SPEED = BASE_SPEED * stats.get("speed", 1.0) * (1.0 + t.move) * Traits.move_mult()
	if not is_puppet and not flight.flying:	# gear that walks through enemies (physics layer 3); flying does too
		set_collision_mask_value(ENEMY_LAYER, not t.phase_mobs)
	_refresh_damage()


## Damage and attack times = weapon x attack-speed setting x DPS boost.
func _refresh_damage():
	var modifier = speed_level * SPEED_DAMAGE_MODIFIER
	var boost = boost_mult * (1.0 + GameState.buff_bonus("meal"))
	st_damage = weapon_st_base * (1.0 - modifier) * boost
	aoe_damage = weapon_aoe_base * (1.0 - modifier) * boost
	st_cooldown_time = gear_st_cd * (1.0 - modifier)
	aoe_cooldown_time = gear_aoe_cd * (1.0 - modifier)


func _element_damage() -> float:
	var total = 0.0
	for el in element_bonus:
		total += element_bonus[el]
	return total


func _on_hit():
	if lifesteal > 0.0:
		health = min(health + lifesteal, MAX_HEALTH)


## Bolt color follows your weapon's strongest element.
func _beam_color() -> Color:
	var best = "physical"
	var best_v = 0.0
	for el in element_bonus:
		if element_bonus[el] > best_v:
			best = el
			best_v = element_bonus[el]
	return Color(1.0, 0.9, 0.3) if best == "physical" else Crafting.ELEMENT_COLORS[best]


## How much of a damage type you shrug off right now (armor + potion ward), capped at 80%.
func resistance(element: String) -> float:
	var r = armor_resist.get(element, 0.0)
	if ward_time > 0.0:
		r += ward.get(element, 0.0)
	return min(r, MAX_RESIST)


func drink_potion():
	var e = Crafting.drink_potion()
	if e == null:
		_float_text("No potions", Color(0.8, 0.8, 0.8))
		return
	if health > MAX_HEALTH * 0.5:
		Traits.on_early_heal()	# Wary
	heal(e.heal * Traits.potion_mult())
	ward = e.ward
	haste = e.haste
	ward_time = 30.0
	_float_text("+%d health" % (e.heal * Traits.potion_mult()), Color(0.5, 1.0, 0.5))


func _tick_potion(delta):
	if ward_time > 0.0:
		ward_time -= delta
		if ward_time <= 0.0:
			ward = {}
			haste = 0.0


## Your look comes from the world skin: a body model ("player_model", e.g. a knight) or the
## plain capsule in the skin's "player" color. Online you keep your player color.
var _capsule_mesh: Mesh = null
var _model: Node3D = null

func _apply_skin():
	if Net.is_online():
		return
	$MeshInstance3D.material_override = SkinManager.material("player", Color(1, 0.486, 1))
	if _capsule_mesh == null:
		_capsule_mesh = $MeshInstance3D.mesh
	if _model:
		_model.queue_free()
		_model = null
	var look = SkinManager.section("player_model")
	if look is Dictionary and look.get("type", "") == "knight":
		_model = preload("res://knight_model.gd").build(look)
		$MeshInstance3D.add_child(_model)	# a child, so blinking and scaling still work
		$MeshInstance3D.mesh = null
	else:
		if look is Dictionary:
			ErrorLog.warn("Skin: unknown player_model type '%s', using the capsule" % look.get("type", ""))
		$MeshInstance3D.mesh = _capsule_mesh


# ---------------- Stuck safety net ----------------
## Holding a move key but not moving at all, wedged inside a hill or prop (seen in Zone 4
## next to a rubble pile, Oct 2026): after a second, warn loudly with what we're touching
## and step back to the last spot where walking worked. Pushing into a plain wall is fine:
## if any direction is open, nothing happens. Crowds of enemies don't count either.
const STUCK_TIME = 1.0
var _stuck_for := 0.0
var _free_pos = null	# last spot where walking worked (refreshed every half second)
var _free_timer := 0.0

func _check_stuck(direction: Vector3, speed_now: float, delta: float, before: Vector3):
	if direction == Vector3.ZERO or speed_now <= 0.1 or skills.dash_velocity() != null:
		_stuck_for = 0.0
		return
	var moved = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if moved > speed_now * delta * 0.1:
		_stuck_for = 0.0
		_free_timer -= delta
		if _free_timer <= 0.0:
			_free_timer = 0.5
			_free_pos = global_position
		return
	_stuck_for += delta
	if _stuck_for < STUCK_TIME:
		return
	_stuck_for = 0.0
	var touching = []
	var on_static = false
	for i in range(get_slide_collision_count()):
		var c = get_slide_collision(i).get_collider()
		if c == null:
			continue
		if c is StaticBody3D:
			on_static = true
		touching.append(str(c.get_meta("kind", c.name)))
	if not on_static:
		return	# held in by enemies: that's the fight, not a bug
	var lifted = global_transform.translated(Vector3(0, 0.1, 0))
	for i in range(8):
		var a = TAU * i / 8.0
		if not test_move(lifted, Vector3(cos(a), 0, sin(a)) * 0.3):
			return	# there's a way out: just pushing into a wall
	ErrorLog.warn("Player stuck at %s in %s, touching %s. Moved back to the last free spot." % [global_position.round(), GameState.current_zone, touching])
	global_position = _free_pos if _free_pos != null else spawn_point
	velocity = Vector3.ZERO


## Shake the screen a bit (boss roars, slams). Stacks up to a limit.
func add_shake(amount: float):
	_shake = min(1.0, _shake + amount)
