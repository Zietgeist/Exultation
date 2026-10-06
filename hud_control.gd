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
var flow_label = null
var death_label = null
var death_timer = 0.0
var notice_label = null
var notice_timer = 0.0
var gold_bar = null
var gold_label = null
var satchel_label = null

func _ready():
	zone_label = get_node("VBoxContainer/ZoneLabel")
	flow_label = get_node("VBoxContainer/FlowLabel")
	health_bar = get_node("VBoxContainer/HealthBar")
	energy_bar = get_node("VBoxContainer/EnergyBar")
	kill_label = get_node("VBoxContainer/KillLabel")
	speed_label = get_node("VBoxContainer/SpeedLabel")
	orb_bar = get_node("VBoxContainer/OrbBar")
	orb_bar.visible = false	# old orb slots bar; blue orbs now go straight to energy
	boost_label = get_node("VBoxContainer/BoostLabel")

	# Gold bag (Pomodoro) bar
	gold_label = Label.new()
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	$VBoxContainer.add_child(gold_label)
	gold_bar = ProgressBar.new()
	gold_bar.custom_minimum_size = Vector2(220, 14)
	gold_bar.show_percentage = false
	gold_bar.max_value = GameState.GOLD_CAPACITY
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.15)
	gold_bar.add_theme_stylebox_override("fill", fill)
	$VBoxContainer.add_child(gold_bar)
	satchel_label = Label.new()
	$VBoxContainer.add_child(satchel_label)

	# The player is made by the World after the HUD, so it's picked up in _process

	# Big message in the middle of the screen when you fall
	death_label = Label.new()
	death_label.set_anchors_preset(Control.PRESET_CENTER)
	death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.add_theme_font_size_override("font_size", 40)
	death_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))  # warm gold: a game event, not an error
	death_label.add_theme_color_override("font_outline_color", Color.BLACK)
	death_label.add_theme_constant_override("outline_size", 8)
	death_label.visible = false
	get_parent().add_child.call_deferred(death_label)

	# Gold notices near the top (boss coming, zone cleared...)
	notice_label = Label.new()
	notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notice_label.offset_top = 70
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.add_theme_font_size_override("font_size", 30)
	notice_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	notice_label.add_theme_color_override("font_outline_color", Color.BLACK)
	notice_label.add_theme_constant_override("outline_size", 8)
	notice_label.visible = false
	get_parent().add_child.call_deferred(notice_label)
	GameState.notice.connect(_on_notice)

	# The map (press M)
	get_parent().add_child.call_deferred(load("res://map_overlay.gd").new())
	# The character screen (press C)
	get_parent().add_child.call_deferred(load("res://character_screen.gd").new())
	# Online party: who's where, Follow / Stay, P to rejoin
	get_parent().add_child.call_deferred(load("res://party_ui.gd").new())

func _on_notice(text: String):
	notice_label.text = text
	notice_label.visible = true
	notice_timer = 4.0


func _on_player_died(cause := ""):
	death_label.text = "DEFEATED"
	if cause != "":
		death_label.text += "\nby " + cause
	death_label.text += "\n\nBack at the gate."
	death_label.visible = true
	death_timer = 3.0


func _process(delta):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player and not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)
	spawner = Zones.local_first("spawner")	# the zone you're in right now
	if notice_timer > 0.0:
		notice_timer -= delta
		if notice_timer <= 0.0:
			notice_label.visible = false
	gold_bar.value = GameState.gold_carried
	gold_label.text = "Gold: %d / %d" % [GameState.gold_carried, GameState.GOLD_CAPACITY]
	satchel_label.text = GameState.satchel_text()
	if GameState.is_bag_full():
		gold_label.text += "  - FULL! Take the gold portal home"
	if death_timer > 0.0:
		death_timer -= delta
		if death_timer <= 0.0:
			death_label.visible = false
	if player:
		health_bar.value = (player.health / player.MAX_HEALTH) * 100
		energy_bar.value = (player.energy / player.MAX_ENERGY) * 100
		speed_label.text = "Attack Speed: %d" % player.speed_level
	# Active skill effects (boost, shield, auras, vow...)
	var active = []
	if player and player.dps_boost_stacks > 0:
		active.append("DMG BOOST x%.0f (%d stacks)" % [pow(player.boost_base, player.dps_boost_stacks), player.dps_boost_stacks])
	if player and player.skills:
		active.append_array(player.skills.status_lines())
	if active.size() > 0:
		boost_label.text = "   ".join(active)
		boost_label.modulate = Color(1.0, 0.75, 0.35)
	else:
		boost_label.text = ""

	if spawner:
		kill_label.text = "%s: %d | %s: %d | %s: %d | %s: %d" % [
			SkinManager.name_of("enemy_trash"), spawner.trash_killed,
			SkinManager.name_of("enemy_thug"), spawner.thugs_killed,
			SkinManager.name_of("enemy_master"), spawner.masters_killed,
			SkinManager.name_of("enemy_boss"), spawner.bosses_killed
		]
		if spawner.targets_ready or Net.is_client():
			kill_label.text += "   |   Cleared %d / %d" % [spawner.total_killed, spawner.min_clear]
	else:
		kill_label.text = ""	# no enemies here (Home)

	zone_label.text = GameState.current_zone

	# Pomodoro flow timer
	flow_label.text = SessionManager.flow_text()
	if SessionManager.is_flow_done():
		flow_label.text += "  - The air grows heavy. Return home to rest."
		flow_label.modulate = Color(1.0, 0.85, 0.3)  # Gold
	else:
		flow_label.modulate = Color(1, 1, 1)
