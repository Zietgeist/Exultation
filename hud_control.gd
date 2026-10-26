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
var pet_label = null
var pet_health = null
var pet_food = null

func _small_bar(color: Color, tip: String) -> ProgressBar:
	var b = ProgressBar.new()
	b.custom_minimum_size = Vector2(90, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	b.max_value = 100
	b.tooltip_text = tip
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	return b


func _update_pet():
	var pet = player.pet if player and "pet" in player else null
	var show = pet != null and is_instance_valid(pet)
	pet_label.visible = show
	pet_health.get_parent().visible = show
	if not show:
		return
	pet_label.text = "%s (%s)   K: pet" % [pet.pet_name(), pet.mood()]
	pet_health.value = 0.0 if not pet.alive() else 100.0 * pet.health / pet.MAX_HEALTH
	pet_food.value = pet.food()
	pet_food.modulate = Color(1, 0.5, 0.5) if pet.food() < 30.0 else Color.WHITE	# hungry: reddish


func _ready():
	zone_label = get_node("VBoxContainer/ZoneLabel")
	flow_label = get_node("VBoxContainer/FlowLabel")
	health_bar = get_node("VBoxContainer/HealthBar")
	energy_bar = get_node("VBoxContainer/EnergyBar")
	# Bar colors: health green, energy blue
	for pair in [[health_bar, Color(0.25, 0.85, 0.3)], [energy_bar, Color(0.25, 0.5, 1.0)]]:
		var bar_fill = StyleBoxFlat.new()
		bar_fill.bg_color = pair[1]
		pair[0].add_theme_stylebox_override("fill", bar_fill)
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
	satchel_label = Label.new()	# the satchel list lives in the inventory window (I) now, not on screen
	satchel_label.visible = false
	$VBoxContainer.add_child(satchel_label)

	# Your pet: name and mood, health and food bars (K opens the pet window)
	pet_label = Label.new()
	pet_label.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	$VBoxContainer.add_child(pet_label)
	var pet_row = HBoxContainer.new()
	$VBoxContainer.add_child(pet_row)
	pet_health = _small_bar(Color(0.3, 0.9, 0.4), "Pet health")
	pet_food = _small_bar(Color(1.0, 0.6, 0.2), "Food: goes down while you're out. Feed a herb (T near your pet).")
	for pair in [["HP", pet_health], ["Food", pet_food]]:
		var l = Label.new()
		l.text = pair[0]
		pet_row.add_child(l)
		pet_row.add_child(pair[1])
	pet_label.visible = false
	pet_row.visible = false

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

	# Buff icons, top right
	get_parent().add_child.call_deferred(load("res://buff_bar.gd").new())
	# The pet window (press K)
	get_parent().add_child.call_deferred(load("res://pet_ui.gd").new())
	# The map (press M)
	get_parent().add_child.call_deferred(load("res://map_overlay.gd").new())
	# The character screen (press C)
	get_parent().add_child.call_deferred(load("res://character_screen.gd").new())
	# Online party: who's where, Follow / Stay, P to rejoin
	get_parent().add_child.call_deferred(load("res://party_ui.gd").new())
	# Inventory (press I)
	get_parent().add_child.call_deferred(load("res://inventory_ui.gd").new())
	get_parent().add_child.call_deferred(load("res://chronicle_ui.gd").new())
	get_parent().add_child.call_deferred(load("res://travel_ui.gd").new())
	get_parent().add_child.call_deferred(load("res://region_compass.gd").new())	# big zones: arrow to the nearest region heart

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
	satchel_label.text = ""
	if GameState.is_bag_full():
		gold_label.text += "  - FULL! Take the gold portal home"
	if death_timer > 0.0:
		death_timer -= delta
		if death_timer <= 0.0:
			death_label.visible = false
	if player:
		health_bar.value = (player.health / player.MAX_HEALTH) * 100
		energy_bar.value = (player.energy / player.MAX_ENERGY) * 100
		speed_label.text = "Attack speed: %+d (C)" % player.speed_level
		if player.flight.max_time > 0.0:	# wings worn
			speed_label.text += ("   FLYING %d%%" if player.flight.flying else "   Wings %d%% (Shift)") % roundi(player.flight.share() * 100)
		if player.stun_time > 0.0:
			speed_label.text += "   STUNNED"
		_update_pet()
		if player.auto:
			if player.disguised:
				speed_label.text += "   Disguised: no fighting (V: talk)"
			else:
				speed_label.text += ("   AUTO: %s (wheel) - target: %s (R)" % [player.auto.stance_name(), player.auto.mode_name()]) if player.auto.on else "   Tab: auto-attack"
	# Active skill effects (boost, shield, auras, vow...)
	var active = []
	if player and player.dps_boost_stacks > 0:
		active.append("DMG BOOST x%.1f (%d stacks)" % [player.boost_mult, player.dps_boost_stacks])
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
			var steadfast = ceili(spawner.target_total * 0.99)	# Steadfast: 99% of the zone
			kill_label.text += ("   |   STEADFAST (99%) reached" if spawner.total_killed >= steadfast else "   |   99%%: %d" % steadfast)
	else:
		kill_label.text = ""	# no enemies here (Home)

	zone_label.text = GameState.current_zone
	if player and is_instance_valid(player) and player.is_inside_tree():	# big zones: which region you're in
		var rg = Regions.at(Zones.local_path(), player.global_position)
		if not rg.is_empty():
			zone_label.text += "  ·  " + rg.name

	# Pomodoro flow timer
	flow_label.text = SessionManager.flow_text()
	if SessionManager.is_flow_done():
		flow_label.text += "  - The air grows heavy. Return home to rest."
		flow_label.modulate = Color(1.0, 0.85, 0.3)  # Gold
	else:
		flow_label.modulate = Color(1, 1, 1)
