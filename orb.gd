extends Area3D
var slot_cost: int = 1
var player = null
var attract_range = 5.0
var speed = 4.0
var collected = false
var kind = "blue"	# "blue" or "gold"
var value = 1		# gold amount (gold orbs) or energy amount (blue orbs)
const PICKUP_RANGE = 1.2
const CHASE_FASTER = 1.4	# once locked on, always at least this much faster than you (speed boots too)
const CHASE_ACCEL = 12.0	# and it keeps speeding up while it chases (m/s per second)
var homing = false		# locked on: follows you at any distance until you're full
var _chase_speed = 0.0

func _ready() -> void:
	player = Zones.first(self, "player")	# only the local player in this zone
	body_entered.connect(_on_body_entered)
	if kind == "gold":
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.15)
		mat.emission_enabled = true
		mat.emission = Color(0.6, 0.45, 0.05)
		$MeshInstance3D.material_override = mat
		scale = Vector3.ONE * (0.5 + 0.15 * value)
		attract_range = 8.0
		speed = 8.0
	else:
		scale = Vector3.ONE * (0.4 + 0.12 * value)

func _process(delta) -> void:
	if collected or not is_instance_valid(player):
		return
	if not _wanted():
		homing = false	# full (energy / gold bag): it stops and waits where it is
		_chase_speed = 0.0
		return
	if Zones.zone_of(player) != Zones.zone_of(self):
		return	# you left the zone
	var dist = global_position.distance_to(player.global_position)
	if dist <= PICKUP_RANGE:
		_collect()
		return
	if dist <= attract_range:
		homing = true
	if homing:	# never gives up: faster than you, and faster the longer it chases
		_chase_speed = maxf(_chase_speed + CHASE_ACCEL * delta, maxf(speed, float(player.SPEED) * CHASE_FASTER))
		var direction = (player.global_position - global_position).normalized()
		global_position += direction * minf(_chase_speed * delta, dist)


## Should this orb come to the player right now?
func _wanted() -> bool:
	if kind == "gold":
		return not GameState.is_bag_full()
	return player.energy < player.MAX_ENERGY


func _on_body_entered(body: Node) -> void:
	if body.name == "Player" and not collected and _wanted():
		_collect()


func _collect():
	collected = true
	if kind == "gold":
		GameState.add_gold(roundi(value * Traits.gold_mult()))	# Self: a little more gold
	else:
		player.add_energy(value)
	queue_free()
