extends Area3D
var slot_cost: int = 1
var player = null
var attract_range = 5.0
var speed = 4.0
var collected = false
var kind = "blue"	# "blue" or "gold"
var value = 1		# gold amount for gold orbs

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
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

func _process(delta) -> void:
	if collected or not player:
		return
	var dist = global_position.distance_to(player.global_position)
	if dist <= attract_range:
		var direction = (player.global_position - global_position).normalized()
		global_position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.name == "Player" and not collected:
		collected = true
		if kind == "gold":
			GameState.add_gold(value)
		else:
			GameState.collect_orb(slot_cost)
		queue_free()
