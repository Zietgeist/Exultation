extends CharacterBody3D

const SPEED = 10.0
const GRAVITY = -9.8
const MAX_HEALTH = 100.0

# Class types
enum Class {DPS, TANK, HEALER}
var player_class = Class.DPS

# Energy
const MAX_ENERGY = 10.0
var energy = 5.0
var dps_boost_stacks = 0

# Energy generation rates
# Action energy comes from blue orbs (see orb.gd). Tank also gains a little from being hit.
const TANK_ENERGY_PER_DAMAGE_TAKEN = 0.015
const HEALER_ENERGY_REGEN = 0.5
const BASE_ENERGY_REGEN = 0.15  # slow trickle for DPS and Tank, so skills work in long boss fights

# Skills (names and energy costs). The skill HUD reads these too.
const SKILL_E = {
	Class.DPS: {name = "Boost", cost = 2.0},
	Class.TANK: {name = "Shield", cost = 4.0},
	Class.HEALER: {name = "Big Heal", cost = 5.0},
}
const SKILL_Q = {
	Class.DPS: {name = "Self Heal", cost = 4.0},
	Class.TANK: {name = "Self Heal", cost = 4.0},
	Class.HEALER: {name = "Self Heal", cost = 3.0},
}
const SKILL_F = {
	Class.DPS: {name = "Blast", cost = 8.0},		# 80% of max energy
	Class.TANK: {name = "Thorns Aura", cost = 5.0},
	Class.HEALER: {name = "Energy Transfer", cost = 0.0, soon = true},
}

# Class specials (F). Both cover about 25% of the screen.
const SPECIAL_SCREEN_SHARE = 0.25
const BLAST_DAMAGE = 250.0		# DPS: hits everything in the circle around the mouse
const AURA_DURATION = 8.0		# Tank: seconds the aura lasts
const AURA_DAMAGE_PER_SECOND = 40.0	# Tank: to every enemy inside the aura
const AURA_TICK = 0.5
const THORNS_REFLECT = 0.5		# Tank: while the aura is up, attackers take back 50% of the hit

var mouse_world_point = Vector3.ZERO
var aura_time_left = 0.0
var _aura_tick_timer = 0.0
var _aura_disc: MeshInstance3D = null

# Attack cooldowns
var st_cooldown = 0.0
var aoe_cooldown = 0.0

# Base attack stats
const ST_RANGE = 10.0
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


func _ready():
	player_class = GameState.player_class
	print("Playing as class: ", player_class)
	_place_at_entry.call_deferred()


## Start next to the door we came in through. That spot is also where we respawn.
func _place_at_entry():
	spawn_point = global_position
	if GameState.pending_spawn != null:	# arrived by portal
		spawn_point = GameState.pending_spawn
		GameState.pending_spawn = null
	else:
		_place_at_door()
	spawn_point.y = SPAWN_HEIGHT	# always above the floor
	global_position = spawn_point
	GameState.spawn_home_portal()	# bag still full? the portal home is waiting


func _place_at_door():
	for door in get_tree().get_nodes_in_group("door"):
		if door.target_scene == GameState.previous_scene:
			var inward = -door.global_position
			inward.y = 0
			spawn_point = door.global_position + inward.normalized() * 4.0
			break

func _input(event):
	# Ability keys fire once per press (holding the key no longer drains energy)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: use_energy_ability()
			KEY_Q: use_secondary_ability()
			KEY_F: use_class_ability()
			KEY_G: start_gathering()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			speed_level = min(speed_level + 1, MAX_SPEED_LEVELS)
			update_attack_speed()
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			speed_level = max(speed_level - 1, -MAX_SPEED_LEVELS)
			update_attack_speed()

func update_attack_speed():
	var modifier = speed_level * SPEED_DAMAGE_MODIFIER
	st_cooldown_time = BASE_ST_COOLDOWN * (1.0 - modifier)
	aoe_cooldown_time = BASE_AOE_COOLDOWN * (1.0 - modifier)
	st_damage = 100.0 * (1.0 - modifier)
	aoe_damage = 50.0 * (1.0 - modifier)
	print("Speed level: ", speed_level, " ST damage: ", roundi(st_damage), " Cooldown: ", snapped(st_cooldown_time, 0.01))

func _physics_process(delta):
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

	if direction.length() > 0:
		direction = direction.normalized()

	var speed_now = SPEED
	var ditch = GameState.ditch_at(global_position)	# slow patches
	if ditch:
		speed_now *= ditch.get_slow_factor()
		ditch.reveal()	# hidden ones show up once you step in
	velocity.x = direction.x * speed_now
	velocity.z = direction.z * speed_now
	velocity.y += GRAVITY * delta

	var mouse_pos = get_viewport().get_mouse_position()
	var cam = get_viewport().get_camera_3d()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_direction = cam.project_ray_normal(mouse_pos)
	var t = (0.0 - ray_origin.y) / ray_direction.y
	var mouse_world = ray_origin + ray_direction * t
	mouse_world_point = mouse_world
	look_at(Vector3(mouse_world.x, global_position.y, mouse_world.z), Vector3.UP)

	if camera:
		camera.global_position = global_position + CAMERA_OFFSET

	_tick_aura(delta)
	_tick_gathering(delta)
	_update_gather_hint(delta)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if st_cooldown <= 0:
			single_target_attack()
			st_cooldown = st_cooldown_time

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if aoe_cooldown <= 0:
			aoe_attack()
			aoe_cooldown = aoe_cooldown_time
	# Energy regen: Healer fast, everyone else a slow trickle
	var regen = HEALER_ENERGY_REGEN if player_class == Class.HEALER else BASE_ENERGY_REGEN
	energy = min(energy + regen * delta, MAX_ENERGY)
		
	move_and_slide()
	

func single_target_attack():
	var enemies = get_tree().get_nodes_in_group("enemy")
	var closest = null
	var closest_dist = ST_RANGE
	
	for enemy in enemies:
		var dist = global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	
	if closest:
		var damage = st_damage * get_damage_multiplier()
		_show_beam(closest.global_position, Color(1.0, 0.9, 0.3))
		closest.take_damage(damage)
	else:
		# Miss: a short, faint swing toward where you're facing
		_show_beam(global_position - global_transform.basis.z * 3.0, Color(1.0, 0.9, 0.3, 0.35))

func aoe_attack():
	var enemies = get_tree().get_nodes_in_group("enemy")
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
		var damage = aoe_damage * get_damage_multiplier()
		enemy.take_damage(damage)

var last_attacker = ""	# who hit us last (for the death message)

func take_damage(amount, source = null):
	if invulnerable_time > 0.0:
		return
	if gather_node != null:
		_stop_gathering("Interrupted!")
	if source and "tier" in source:
		last_attacker = SkinManager.name_of(source.TIER_IDS[source.tier] + "_one")
		if aura_time_left > 0.0 and is_instance_valid(source):
			source.take_damage(amount * THORNS_REFLECT)	# thorns
	health -= amount
	print("Player health: ", roundi(health))
	
	# Tank gains energy from taking damage
	if player_class == Class.TANK:
		energy = min(energy + amount * TANK_ENERGY_PER_DAMAGE_TAKEN, MAX_ENERGY)
	
	if health <= 0:
		die(last_attacker)

## Token death: back to the entry door with full health. Nothing is lost (for now).
func die(cause := ""):
	GameState.deaths += 1
	GameState.add_mark("death", global_position)
	print("DEFEATED by ", cause, ". Respawning at the entry door. Deaths: ", GameState.deaths)
	health = MAX_HEALTH
	velocity = Vector3.ZERO
	global_position = spawn_point
	invulnerable_time = RESPAWN_SAFE_TIME
	# Enemies lose track of you
	for enemy in get_tree().get_nodes_in_group("enemy"):
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



func spend_energy(amount):
	if energy >= amount:
		energy -= amount
		return true
	return false



func use_energy_ability():
	match player_class:
		Class.DPS:
			if dps_boost_stacks >= 5:
				print("Boost at max stacks!")
				return
			if spend_energy(SKILL_E[Class.DPS].cost):
				dps_boost_stacks += 1
				var multiplier = pow(2.0, dps_boost_stacks)
				# Recalculate from base each time
				st_damage = 100.0 * multiplier
				aoe_damage = 50.0 * multiplier
				print("DPS boost x", dps_boost_stacks, " — damage multiplier: ", multiplier)
				await get_tree().create_timer(10.0).timeout
				dps_boost_stacks -= 1
				if dps_boost_stacks > 0:
					var remaining = pow(2.0, dps_boost_stacks)
					st_damage = 100.0 * remaining
					aoe_damage = 50.0 * remaining
				else:
					st_damage = 100.0
					aoe_damage = 50.0
				print("Boost stack expired — stacks remaining: ", dps_boost_stacks)
		Class.TANK:
			if spend_energy(SKILL_E[Class.TANK].cost):
				print("Tank shield activated!")
		Class.HEALER:
			if spend_energy(SKILL_E[Class.HEALER].cost):
				health = min(health + 50.0, MAX_HEALTH)
				print("Healer self heal!")
				

				
func use_secondary_ability():
	match player_class:
		Class.DPS:
			if spend_energy(SKILL_Q[Class.DPS].cost):
				health = min(health + 40.0, MAX_HEALTH)
				print("DPS self heal!")
		Class.TANK:
			if spend_energy(SKILL_Q[Class.TANK].cost):
				health = min(health + 40.0, MAX_HEALTH)
				print("Tank self heal!")
		Class.HEALER:
			if spend_energy(SKILL_Q[Class.HEALER].cost):
				health = min(health + 60.0, MAX_HEALTH)
				print("Healer self heal!")
				
func use_class_ability():
	match player_class:
		Class.DPS:
			if spend_energy(SKILL_F[Class.DPS].cost):
				_blast(mouse_world_point)
		Class.TANK:
			if spend_energy(SKILL_F[Class.TANK].cost):
				aura_time_left = AURA_DURATION
				_aura_tick_timer = 0.0
				print("Thorns Aura up for ", AURA_DURATION, "s")
		Class.HEALER:
			print("Energy transfer - TBD")


## Radius of a circle that covers about 25% of what's on screen.
## Measured from the camera each time, so it stays right if the window or camera changes.
func special_radius() -> float:
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
	return sqrt(area * SPECIAL_SCREEN_SHARE / PI)


## DPS Blast: big damage to every enemy in a circle around the mouse.
func _blast(center: Vector3):
	var radius = special_radius()
	var hit = 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var d = Vector2(enemy.global_position.x - center.x, enemy.global_position.z - center.z).length()
		if d <= radius:
			enemy.take_damage(BLAST_DAMAGE * get_damage_multiplier())
			hit += 1
	print("Blast! radius %.1f, hit %d" % [radius, hit])
	var disc = _make_disc(radius, Color(1.0, 0.45, 0.1, 0.45))
	get_tree().current_scene.add_child(disc)
	disc.global_position = Vector3(center.x, 0.25, center.z)
	var tween = disc.create_tween()
	tween.tween_property(disc, "scale", Vector3(1.05, 1, 1.05), 0.35)
	tween.parallel().tween_property(disc.material_override, "albedo_color:a", 0.0, 0.35)
	tween.tween_callback(disc.queue_free)


## Tank Thorns Aura: damages and pulls every enemy near the tank while it lasts.
func _tick_aura(delta):
	if aura_time_left <= 0.0:
		if _aura_disc:
			_aura_disc.queue_free()
			_aura_disc = null
		return
	aura_time_left -= delta
	var radius = special_radius()
	if _aura_disc == null:
		_aura_disc = _make_disc(1.0, Color(0.3, 0.9, 0.3, 0.25))
		add_child(_aura_disc)
		_aura_disc.position = Vector3(0, -0.9, 0)
	_aura_disc.scale = Vector3(radius, 1, radius)
	_aura_tick_timer -= delta
	if _aura_tick_timer > 0.0:
		return
	_aura_tick_timer = AURA_TICK
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var d = Vector2(enemy.global_position.x - global_position.x, enemy.global_position.z - global_position.z).length()
		if d <= radius:
			enemy.aggroed = true
			enemy.take_damage(AURA_DAMAGE_PER_SECOND * AURA_TICK)


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
	return [
		{key = "LMB", name = "Strike", cost = 0.0, cooldown = max(st_cooldown, 0.0), soon = false},
		{key = "RMB", name = "Sweep", cost = 0.0, cooldown = max(aoe_cooldown, 0.0), soon = false},
		{key = "E", name = SKILL_E[player_class].name, cost = SKILL_E[player_class].cost, cooldown = 0.0, soon = false},
		{key = "Q", name = SKILL_Q[player_class].name, cost = SKILL_Q[player_class].cost, cooldown = 0.0, soon = false},
		{key = "F", name = SKILL_F[player_class].name, cost = SKILL_F[player_class].cost, cooldown = 0.0, soon = SKILL_F[player_class].get("soon", false)},
	]


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
	get_tree().current_scene.add_child(beam)
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
	get_tree().current_scene.add_child(cone)
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
	for n in get_tree().get_nodes_in_group("resource_node"):
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
	var best = _nearest_gatherable()
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
