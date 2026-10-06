extends CharacterBody3D

var SPEED = 10.0		# armor can change this
const BASE_SPEED = 10.0
const GRAVITY = -9.8
var MAX_HEALTH = 100.0	# armor vitality can raise this
const BASE_MAX_HEALTH = 100.0

# Class: comes from a file in classes/ (see ClassManager.gd). Skills run in skill_runner.gd.
var player_class := "dps"
var class_def := {}
var skills = null		# this player's SkillRunner

# Energy
const MAX_ENERGY = 10.0
var energy = 5.0
var dps_boost_stacks = 0	# damage boost stacks (any class with a damage_boost skill)
var boost_base = 2.0		# each stack multiplies damage by this
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
var ST_RANGE = 10.0		# weapon reach (spears reach farther)
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
const CAMERA_OFFSET = BASE_CAMERA_OFFSET * CAMERA_ZOOM
const RESPAWN_SAFE_TIME = 2.0	# seconds you can't be hurt after respawning
var spawn_point = Vector3.ZERO
var invulnerable_time = 0.0


var warded := false	# taking a shrine trial: nothing can hurt you

# Online: a stand-in for another player (their game moves it; mine just shows it)
var is_puppet := false
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
	Crafting.changed.connect(apply_gear)
	apply_gear()
	health = MAX_HEALTH
	if Net.is_online():	# my color, so friends can tell us apart (matches what they see)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Net.color_of(Net.my_id())
		$MeshInstance3D.material_override = mat
	print("Playing as class: ", Classes.label(player_class))
	# Zones.travel() places us (arrive) every time we enter a zone


## Just entered a zone (Zones.travel calls this): start next to the door we came in through,
## or at the portal's spot. That's also where we respawn.
func arrive():
	gather_node = null
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
			KEY_G: start_gathering()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			speed_level = min(speed_level + 1, MAX_SPEED_LEVELS)
			update_attack_speed()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			speed_level = max(speed_level - 1, -MAX_SPEED_LEVELS)
			update_attack_speed()

func update_attack_speed():
	_refresh_damage()
	print("Speed level: ", speed_level, " ST damage: ", roundi(st_damage), " Cooldown: ", snapped(st_cooldown_time, 0.01))

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
	
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		direction.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		direction.z += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		direction.z -= 1

	if GameState.input_locked:
		direction = Vector3.ZERO
	if direction.length() > 0:
		direction = direction.normalized()

	var speed_now = SPEED * (1.0 + haste + skill_haste)
	var ditch = GameState.ditch_at(global_position, self)	# slow patches
	if ditch:
		speed_now *= ditch.get_slow_factor()
		ditch.reveal()	# hidden ones show up once you step in
	velocity.x = direction.x * speed_now
	velocity.z = direction.z * speed_now
	var dash = skills.dash_velocity()
	if dash != null:
		velocity.x = dash.x
		velocity.z = dash.z
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

	_tick_gathering(delta)
	_tick_potion(delta)
	_update_gather_hint(delta)

	if not GameState.ui_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if st_cooldown <= 0:
			single_target_attack()
			st_cooldown = st_cooldown_time

	if not GameState.ui_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if aoe_cooldown <= 0:
			aoe_attack()
			aoe_cooldown = aoe_cooldown_time
	move_and_slide()

	# Energy: trickle (per class) + energy for distance moved (skirmisher)
	var e_rules = class_def.get("energy", {})
	var moved = Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	if moved > 2.0:
		moved = 0.0	# teleported (respawn, portal), not running
	_last_pos = global_position
	energy = min(energy + e_rules.get("regen", 0.15) * delta + moved * e_rules.get("per_meter_moved", 0.0), MAX_ENERGY)
	

func single_target_attack():
	var enemies = Zones.all(self, "enemy")
	var closest = null
	var closest_dist = ST_RANGE
	
	for enemy in enemies:
		var dist = global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	
	if closest:
		var damage = st_damage * get_damage_multiplier() + _element_damage()
		_show_beam(closest.global_position, _beam_color())
		closest.take_damage(damage)
		_on_hit()
	else:
		# Miss: a short, faint swing toward where you're facing
		_show_beam(global_position - global_transform.basis.z * 3.0, Color(1.0, 0.9, 0.3, 0.35))

func aoe_attack():
	var enemies = Zones.all(self, "enemy")
	var in_range = []
	
	for enemy in enemies:
		var dist = global_position.distance_to(enemy.global_position)
		if dist <= AOE_RANGE:
			var to_enemy = (enemy.global_position - global_position).normalized()
			var facing = -global_transform.basis.z.normalized()
			var dot = facing.dot(to_enemy)
			if dot > aoe_cone:
				in_range.append(enemy)
	
	in_range.sort_custom(func(a, b): 
		return global_position.distance_to(a.global_position) < global_position.distance_to(b.global_position))
	
	var targets = in_range.slice(0, aoe_max_targets)
	_show_cone()
	for enemy in targets:
		var damage = aoe_damage * get_damage_multiplier() + _element_damage() * 0.5
		enemy.take_damage(damage)
		_on_hit()

var last_attacker = ""	# who hit us last (for the death message)

func take_damage(amount, source = null):
	if is_puppet:	# another player: their game takes the hit
		Net.hurt_player(peer_id, amount, source)
		return
	if invulnerable_time > 0.0 or warded:
		return
	if gather_node != null:
		_stop_gathering("Interrupted!")
	if source and "tier" in source:
		last_attacker = SkinManager.name_of(source.TIER_IDS[source.tier] + "_one")
	# Damage types: armor and potion wards soak their element
	var element = source.damage_type if source and "damage_type" in source else "physical"
	if element != "physical" and source and "tier" in source:
		last_attacker = SkinManager.name_of(source.TIER_IDS[source.tier] + "_one") + " (" + SkinManager.element_label(element) + ")"
	var raw = amount
	amount *= 1.0 - resistance(element)
	amount = skills.absorb(amount)	# shield
	health -= amount

	# Some classes (tank) gain energy from taking damage
	energy = min(energy + amount * class_def.get("energy", {}).get("per_damage_taken", 0.0), MAX_ENERGY)

	if health <= 0:
		die(last_attacker)
		return
	skills.on_hurt(raw, source)	# thorns, mending vow


## Any healing (skills, party heals, potions). Never above max.
func heal(amount: float):
	if is_puppet:
		Net.heal_player(peer_id, amount)
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
	GameState.add_mark("death", global_position, self)
	print("DEFEATED by ", cause, ". Respawning at the entry door. Deaths: ", GameState.deaths)
	health = MAX_HEALTH
	velocity = Vector3.ZERO
	global_position = spawn_point
	invulnerable_time = RESPAWN_SAFE_TIME
	# Enemies lose track of you
	for enemy in Zones.all(self, "enemy"):
		enemy.aggroed = false
	died.emit(cause)

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
func _nearest_gatherable():
	var best = null
	var best_d = INF
	for n in Zones.all(self, "resource_node") + Zones.all(self, "npc"):
		var d = n.horizontal_distance(global_position)
		var score = d - n.reach	# nodes up on a hill or trunk count as a bit closer
		if d <= GATHER_RANGE + n.reach and score < best_d:
			best = n
			best_d = score
	return best


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
	if best == null:
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
		GameState.add_resource(n.type, n.quality)
		_float_text("+1 " + GameState.resource_name(n.type, n.quality), GameState.RESOURCE_INFO[n.type].color.lightened(0.3))
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
		ST_RANGE = e.reach
		gear_st_cd = e.st_cd
		gear_aoe_cd = e.aoe_cd
		element_bonus = e.element_bonus
		lifesteal = e.lifesteal
	else:	# bare hands
		weapon_name = "Fists"
		weapon_st_base = 100.0
		weapon_aoe_base = 50.0
		aoe_cone = 0.3
		aoe_max_targets = 4
		ST_RANGE = 10.0
		gear_st_cd = BASE_ST_COOLDOWN
		gear_aoe_cd = BASE_AOE_COOLDOWN
		element_bonus = {}
		lifesteal = 0.0
	var t = Crafting.armor_totals()
	armor_resist = t.resist
	var old_max = MAX_HEALTH
	var stats = class_def.get("stats", {})
	MAX_HEALTH = BASE_MAX_HEALTH * stats.get("health", 1.0) + t.max_health
	health = clamp(health + (MAX_HEALTH - old_max), 1.0, MAX_HEALTH)
	SPEED = BASE_SPEED * stats.get("speed", 1.0) * (1.0 + t.move)
	_refresh_damage()


## Damage and attack times = weapon x attack-speed wheel x DPS boost.
func _refresh_damage():
	var modifier = speed_level * SPEED_DAMAGE_MODIFIER
	var boost = pow(boost_base, dps_boost_stacks)
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
	heal(e.heal)
	ward = e.ward
	haste = e.haste
	ward_time = 30.0
	_float_text("+%d health" % e.heal, Color(0.5, 1.0, 0.5))


func _tick_potion(delta):
	if ward_time > 0.0:
		ward_time -= delta
		if ward_time <= 0.0:
			ward = {}
			haste = 0.0
