extends CharacterBody3D
signal enemy_died(tier)

# Tier settings
enum Tier {TRASH, THUG, MASTER, BOSS}
var tier = Tier.TRASH
const TIER_IDS = {Tier.TRASH: "enemy_trash", Tier.THUG: "enemy_thug", Tier.MASTER: "enemy_master", Tier.BOSS: "enemy_boss"}

# Base stats per tier
const TIER_STATS = {
	Tier.TRASH:  {health = 100,  damage = 5,  speed = 4.0, aggro = 8.0,  color = Color(0.15, 0.9, 0.13)},
	Tier.THUG:   {health = 400,  damage = 15, speed = 3.0, aggro = 12.0, color = Color(0.2,  0.4, 1.0)},
	Tier.MASTER: {health = 1200, damage = 35, speed = 2.5, aggro = 15.0, color = Color(0.6,  0.0, 0.9)},
	Tier.BOSS:   {health = 5000, damage = 60, speed = 2.0, aggro = 20.0, color = Color(1.0,  0.8, 0.0)},
}

const ATTACK_RANGE = 1.2
var MAX_HEALTH = 100.0
var health = MAX_HEALTH
var ATTACK_DAMAGE = 5.0
var SPEED = 4.0
var AGGRO_RANGE = 8.0
const GRAVITY = -9.8

var player = null
var attack_cooldown = 0.0
var aggroed = false
var difficulty = 1.0

func setup(diff, t = Tier.TRASH):
	difficulty = diff
	tier = t
	var stats = TIER_STATS[tier]
	MAX_HEALTH = roundi(stats.health * difficulty)
	health = MAX_HEALTH
	ATTACK_DAMAGE = stats.damage
	SPEED = stats.speed
	AGGRO_RANGE = stats.aggro
	
	# Set color (from the current skin)
	$MeshInstance3D.mesh = $MeshInstance3D.mesh.duplicate()
	apply_skin()

func _ready():
	player = get_tree().get_first_node_in_group("player")
	SkinManager.skin_changed.connect(apply_skin)

func apply_skin():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = SkinManager.color(TIER_IDS[tier], TIER_STATS[tier].color)
	$MeshInstance3D.mesh.surface_set_material(0, mat)

func _physics_process(delta):
	velocity.y += GRAVITY * delta
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		player = get_tree().get_first_node_in_group("player")
	if player:
		var distance = global_position.distance_to(player.global_position)
		
		if distance <= AGGRO_RANGE:
			aggroed = true
		
		if aggroed:
			var direction = (player.global_position - global_position)
			direction.y = 0
			direction = direction.normalized()
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
			
			attack_cooldown -= delta
			if distance <= ATTACK_RANGE:
				if attack_cooldown <= 0:
					player.take_damage(ATTACK_DAMAGE * get_damage_multiplier(), self)
					attack_cooldown = 1.0
	
	move_and_slide()

func take_damage(amount):
	health -= amount
	if health <= 0:
		die()

func drop_orb() -> void:
	var orb_scene = preload("res://Orb.tscn")
	var orb = orb_scene.instantiate()
	orb.position = global_position
	if tier == Tier.BOSS:
		orb.slot_cost = 5
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

func die():
	emit_signal("enemy_died", tier)
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
		
