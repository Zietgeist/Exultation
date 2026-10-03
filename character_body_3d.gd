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
const DPS_ENERGY_PER_DAMAGE = 0.01
const TANK_ENERGY_PER_DAMAGE_DEALT = 0.008
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
	Class.DPS: {name = "Class Skill", cost = 0.0, soon = true},
	Class.TANK: {name = "Taunt", cost = 2.0},
	Class.HEALER: {name = "Energy Transfer", cost = 0.0, soon = true},
}

const TAUNT_RANGE = 15.0

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

signal died

# Respawn
const SPAWN_HEIGHT = 1.5	# start a little above the floor and drop onto it
const FALL_LIMIT = -10.0	# below this, we fell out of the world
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
	for door in get_tree().get_nodes_in_group("door"):
		if door.target_scene == GameState.previous_scene:
			var inward = -door.global_position
			inward.y = 0
			spawn_point = door.global_position + inward.normalized() * 4.0
			break
	spawn_point.y = SPAWN_HEIGHT	# always above the floor
	global_position = spawn_point

func _input(event):
	# Ability keys fire once per press (holding the key no longer drains energy)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: use_energy_ability()
			KEY_Q: use_secondary_ability()
			KEY_F: use_class_ability()
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

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	velocity.y += GRAVITY * delta

	var mouse_pos = get_viewport().get_mouse_position()
	var cam = get_viewport().get_camera_3d()
	var ray_origin = cam.project_ray_origin(mouse_pos)
	var ray_direction = cam.project_ray_normal(mouse_pos)
	var t = (0.0 - ray_origin.y) / ray_direction.y
	var mouse_world = ray_origin + ray_direction * t
	look_at(Vector3(mouse_world.x, global_position.y, mouse_world.z), Vector3.UP)

	if camera:
		camera.global_position = global_position + Vector3(0, 8, 5)

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
		closest.take_damage(damage)
		
		# Generate energy from dealing damage
		match player_class:
			Class.DPS:
				energy = min(energy + damage * DPS_ENERGY_PER_DAMAGE, MAX_ENERGY)
			Class.TANK:
				energy = min(energy + damage * TANK_ENERGY_PER_DAMAGE_DEALT, MAX_ENERGY)

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
	for enemy in targets:
		var damage = aoe_damage * get_damage_multiplier()
		enemy.take_damage(damage)
		
		# Generate energy from dealing damage
		match player_class:
			Class.DPS:
				energy = min(energy + damage * DPS_ENERGY_PER_DAMAGE, MAX_ENERGY)
			Class.TANK:
				energy = min(energy + damage * TANK_ENERGY_PER_DAMAGE_DEALT, MAX_ENERGY)

func take_damage(amount):
	if invulnerable_time > 0.0:
		return
	health -= amount
	print("Player health: ", roundi(health))
	
	# Tank gains energy from taking damage
	if player_class == Class.TANK:
		energy = min(energy + amount * TANK_ENERGY_PER_DAMAGE_TAKEN, MAX_ENERGY)
	
	if health <= 0:
		die()

## Token death: back to the entry door with full health. Nothing is lost (for now).
func die():
	GameState.deaths += 1
	print("You fell! Respawning at the entry door. Deaths: ", GameState.deaths)
	health = MAX_HEALTH
	velocity = Vector3.ZERO
	global_position = spawn_point
	invulnerable_time = RESPAWN_SAFE_TIME
	# Enemies lose track of you
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.aggroed = false
	died.emit()

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
			print("DPS class ability - TBD")
		Class.TANK:
			if spend_energy(SKILL_F[Class.TANK].cost):
				# Pull every enemy within range onto the tank
				var pulled = 0
				for enemy in get_tree().get_nodes_in_group("enemy"):
					if global_position.distance_to(enemy.global_position) <= TAUNT_RANGE:
						enemy.aggroed = true
						pulled += 1
				print("Taunt! Pulled ", pulled, " enemies")
		Class.HEALER:
			print("Energy transfer - TBD")


## List of skills for the skill HUD: key to press, name, energy cost, cooldown left.
func get_skills() -> Array:
	return [
		{key = "LMB", name = "Strike", cost = 0.0, cooldown = max(st_cooldown, 0.0), soon = false},
		{key = "RMB", name = "Sweep", cost = 0.0, cooldown = max(aoe_cooldown, 0.0), soon = false},
		{key = "E", name = SKILL_E[player_class].name, cost = SKILL_E[player_class].cost, cooldown = 0.0, soon = false},
		{key = "Q", name = SKILL_Q[player_class].name, cost = SKILL_Q[player_class].cost, cooldown = 0.0, soon = false},
		{key = "F", name = SKILL_F[player_class].name, cost = SKILL_F[player_class].cost, cooldown = 0.0, soon = SKILL_F[player_class].get("soon", false)},
	]
