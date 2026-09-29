extends Node

var player_class = 0

# Orb Container
var orb_container: int = 0
var orb_capacity: int = 20
var orb_overfill_timer: float = 0.0
var is_overfilled: bool = false
var orbs_collected = 0
var orb_slots = 10
var current_zone = "Home"


func _process(delta: float) -> void:
	if is_overfilled:
		orb_overfill_timer -= delta
		if orb_overfill_timer <= 0.0:
			orb_container = orb_capacity
			is_overfilled = false
			orb_overfill_timer = 0.0
			
func collect_orb(cost: int) -> void:
	if orbs_collected + cost <= orb_slots:
		orbs_collected += cost
		print("Orbs collected: ", orbs_collected, "/", orb_slots)
