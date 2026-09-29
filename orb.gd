extends Area3D
var slot_cost: int = 1
var player = null
var attract_range = 5.0
var speed = 4.0
var collected = false

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	body_entered.connect(_on_body_entered)

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
		GameState.collect_orb(slot_cost)
		queue_free()
