extends CharacterBody3D
signal enemy_died(tier)

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

# Energy in the blue orb each tier drops (halved in Oct 2026: was 1/2/4/8)
const ORB_ENERGY = {Tier.TRASH: 0.5, Tier.THUG: 1.0, Tier.MASTER: 2.0, Tier.BOSS: 4.0}

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
	if Net.is_host() and not mirror:
		net_id = Net.register_enemy(self)

func _ready():
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
			var direction = (player.global_position - global_position)
			direction.y = 0
			direction = direction.normalized()
			var speed_now = SPEED * GameState.slow_factor_at(global_position, self)
			if rooted_time > 0.0:
				rooted_time -= delta
				speed_now = 0.0
			velocity.x = direction.x * speed_now
			velocity.z = direction.z * speed_now
			
			attack_cooldown -= delta
			if not rival.is_empty():
				_tick_power(delta, distance)
			if distance <= ATTACK_RANGE * (1.4 if not rival.is_empty() else 1.0):
				if attack_cooldown <= 0:
					var hit = ATTACK_DAMAGE * get_damage_multiplier() * (1.6 if _power_on > 0.0 and rival.get("power") == "enrage" else 1.0)
					player.take_damage(hit, self)
					attack_cooldown = 1.0
	
	move_and_slide()

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
		GameState.add_mark("boss", global_position, self)
	drop_orb()
	drop_gold()
	queue_free()


func die():
	if Net.is_host():
		Net.enemy_died(self)
	if not rival.is_empty():
		Rivals.rival_died(self)
	if tier == Tier.BOSS:
		GameState.add_mark("boss", global_position, self)
	emit_signal("enemy_died", tier)
	if Zones.first(self, "player") and not has_meta("recruited"):	# loot is personal: the host only drops its own if it's here (none for a recruit: it's leaving, not dying)
		Story.on_kill(self)	# my worn gear remembers it
		if is_instance_valid(player) and player.is_in_group("pet"):	# it was going after my pet
			Traits.on_guarded_pet()
			player.guarded()	# it bonds with you a little
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
	ring.global_position = Vector3(at.x, 0.06, at.z)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(ring):
		ring.queue_free()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	for m in GameState.party(self) + Zones.all(self, "pet"):
		if is_instance_valid(m) and Vector2(m.global_position.x - at.x, m.global_position.z - at.z).length() <= SLAM_RADIUS:
			m.take_damage(ATTACK_DAMAGE * 1.5, self)


func _say(text: String):
	if _rival_label == null or text == "":
		return
	_rival_label.text = "%s\n%s!" % [rival.label, text]
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(self) and _rival_label:
			_rival_label.text = rival.label)
