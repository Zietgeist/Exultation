extends Area3D
var slot_cost: int = 1
var player = null
var attract_range = 5.0
var speed = 4.0
var collected = false
var kind = "blue"	# "blue" or "gold"
var value = 1		# gold amount (gold orbs) or energy amount (blue orbs)
const PICKUP_RANGE = 1.2

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
		return	# blue orbs wait on the ground while your energy is full
	var dist = global_position.distance_to(player.global_position)
	if dist <= PICKUP_RANGE:
		_collect()
	elif dist <= attract_range:
		var direction = (player.global_position - global_position).normalized()
		global_position += direction * speed * delta


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
