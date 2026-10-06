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

# Energy in the blue orb each tier drops
const ORB_ENERGY = {Tier.TRASH: 1.0, Tier.THUG: 2.0, Tier.MASTER: 4.0, Tier.BOSS: 8.0}

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
var hunter = false	# hunters (the 2nd Boss) never stop chasing you
var difficulty = 1.0

var net_id = 0			# online: same number on every player's screen
var mirror = false		# online, joined player: a copy of the host's enemy (the host runs it)
var net_target = Vector3.ZERO
var _retarget = 0.0
var rooted_time = 0.0	# held in place (Warden's Root Field): can still swing if you're close
var damage_type = "physical"	# radiant, shadow, nature, storm... (armor can resist these)

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
	if Net.is_host() and not mirror:
		net_id = Net.register_enemy(self)

func _ready():
	player = get_tree().get_first_node_in_group("player")
	SkinManager.skin_changed.connect(apply_skin)

func apply_skin():
	if damage_type == "physical":
		$MeshInstance3D.material_override = SkinManager.material(TIER_IDS[tier], TIER_STATS[tier].color)
	else:	# glows with its damage type's color
		$MeshInstance3D.material_override = SkinManager.element_material(TIER_IDS[tier], TIER_STATS[tier].color, damage_type, Crafting.ELEMENT_COLORS[damage_type])

func _physics_process(delta):
	if mirror:	# the host moves it; just glide to where the host says it is
		global_position = global_position.lerp(net_target, min(1.0, delta * 12.0))
		return
	# Chase the closest party member (with friends online, that's not always you)
	_retarget -= delta
	if _retarget <= 0.0 or player == null or not is_instance_valid(player) or not player.is_inside_tree():
		_retarget = 0.3
		player = _closest_party_member()
	if player:
		var distance = global_position.distance_to(player.global_position)
		
		if distance <= AGGRO_RANGE:
			aggroed = true

		# Idle enemies stand still and skip physics (zones can hold hundreds of them)
		if hunter:
			aggroed = true
		if not aggroed:
			return
		velocity.y += GRAVITY * delta
		
		if aggroed:
			var direction = (player.global_position - global_position)
			direction.y = 0
			direction = direction.normalized()
			var speed_now = SPEED * GameState.slow_factor_at(global_position)
			if rooted_time > 0.0:
				rooted_time -= delta
				speed_now = 0.0
			velocity.x = direction.x * speed_now
			velocity.z = direction.z * speed_now
			
			attack_cooldown -= delta
			if distance <= ATTACK_RANGE:
				if attack_cooldown <= 0:
					player.take_damage(ATTACK_DAMAGE * get_damage_multiplier(), self)
					attack_cooldown = 1.0
	
	move_and_slide()

func _closest_party_member():
	var best = null
	var best_d = INF
	for m in GameState.party():
		if not is_instance_valid(m) or not m.is_inside_tree():
			continue
		var d = global_position.distance_squared_to(m.global_position)
		if d < best_d:
			best = m
			best_d = d
	return best


func root(seconds: float):
	if mirror:
		Net.root_enemy(net_id, seconds)
		return
	rooted_time = max(rooted_time, seconds)
	aggroed = true


func take_damage(amount):
	if mirror:	# the host decides; show the hit right away
		flash()
		Net.hit_enemy(net_id, amount)
		return
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
	if tier == Tier.BOSS:
		GameState.add_mark("boss", global_position)
	drop_orb()
	drop_gold()
	queue_free()


func die():
	if Net.is_host():
		Net.enemy_died(self)
	if tier == Tier.BOSS:
		GameState.add_mark("boss", global_position)
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
		


## Quick white flash so you can see the hit land.
func flash():
	$MeshInstance3D.material_override = SkinManager.material("hit_flash", Color(1, 1, 1))
	var t = create_tween()
	t.tween_interval(0.08)
	t.tween_callback(apply_skin)
