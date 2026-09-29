extends Control
var health_bar = null
var kill_label = null
var speed_label = null
var player = null
var spawner = null
var energy_bar = null
var orb_bar = null
var boost_label = null
var zone_label = null

func _ready():
	zone_label = get_node("VBoxContainer/ZoneLabel")
	health_bar = get_node("VBoxContainer/HealthBar")
	energy_bar = get_node("VBoxContainer/EnergyBar")
	kill_label = get_node("VBoxContainer/KillLabel")
	speed_label = get_node("VBoxContainer/SpeedLabel")
	orb_bar = get_node("VBoxContainer/OrbBar")
	boost_label = get_node("VBoxContainer/BoostLabel")

	player = get_tree().get_first_node_in_group("player")
	spawner = get_tree().get_first_node_in_group("spawner")

func _process(_delta):
	if player:
		health_bar.value = (player.health / player.MAX_HEALTH) * 100
		energy_bar.value = (player.energy / player.MAX_ENERGY) * 100
		speed_label.text = "Attack Speed: %d" % player.speed_level
	if player.dps_boost_stacks > 0:
		var multiplier = pow(2.0, player.dps_boost_stacks)
		boost_label.text = "DMG BOOST: x%.0f (%d stacks)" % [multiplier, player.dps_boost_stacks]
		boost_label.modulate = Color(1.0, 0.3, 0.1)  # Orange-red when active
	else:
		boost_label.text = "DMG BOOST: off"
		boost_label.modulate = Color(0.6, 0.6, 0.6)  # Gray when inactive

	if spawner:
		kill_label.text = "Trash: %d | Thugs: %d | Masters: %d | Bosses: %d" % [
			spawner.trash_killed,
			spawner.thugs_killed,
			spawner.masters_killed,
			spawner.bosses_killed
		]

	orb_bar.max_value = GameState.orb_slots
	orb_bar.value = GameState.orbs_collected
	zone_label.text = GameState.current_zone
	
