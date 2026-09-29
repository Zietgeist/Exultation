extends Node3D

@export var next_zone: String = ""
@export var bosses_required: int = 2

const WARN_RANGE = 10.0
const KILL_RANGE = 5.0

var bosses_cleared = false
var player_warned = false

func _ready():
	add_to_group("guardian")

func _process(_delta):
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var player_dist = global_position.distance_to(player.global_position)

	if bosses_cleared:
		if player_dist < WARN_RANGE and not player_warned:
			player_warned = true
			print("Guardian: 'The bosses have fallen. You have earned passage.'")
			open_door()
		return

	# Warn player
	if player_dist < WARN_RANGE and not player_warned:
		player_warned = true
		print("Guardian: 'WARNING. Turn back.'")
	if player_dist >= WARN_RANGE:
		player_warned = false

	# Kill player
	if player_dist < KILL_RANGE:
		print("Guardian: 'LETHAL FORCE AUTHORIZED.'")
		player.die()

	# Handle mobs
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var dist = global_position.distance_to(enemy.global_position)
		if dist < KILL_RANGE:
			if enemy.tier == 0:
				enemy.queue_free()
			else:
				var away = (enemy.global_position - global_position).normalized()
				enemy.global_position += away * 6.0

func open_door():
	if next_zone != "":
		get_tree().call_deferred("change_scene_to_file", next_zone)

func notify_boss_killed(total_bosses_killed):
	if total_bosses_killed >= bosses_required:
		bosses_cleared = true
		player_warned = false
		print("Guardian stirs... the way is open.")
