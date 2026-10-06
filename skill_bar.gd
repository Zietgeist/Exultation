extends HBoxContainer
## Skill bar at the bottom of the screen.
## Shows each skill, the button to press, and its energy cost.
## Skills are dimmed when you don't have enough energy or they're cooling down.

var player = null
var slots = []


func _ready():
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)


func _process(_delta):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
		_build(player.get_skills())

	var skills = player.get_skills()
	for i in range(min(skills.size(), slots.size())):
		_update_slot(slots[i], skills[i])


func _build(skills: Array):
	for child in get_children():
		child.queue_free()
	slots.clear()
	for s in skills:
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(110, 70)
		var box = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(box)

		var key_label = Label.new()
		key_label.text = s.key
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 22)
		key_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		box.add_child(key_label)

		var name_label = Label.new()
		name_label.text = s.name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name_label)

		var info_label = Label.new()
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_label.add_theme_font_size_override("font_size", 12)
		box.add_child(info_label)

		add_child(panel)
		slots.append({panel = panel, name = name_label, info = info_label})


func _update_slot(slot: Dictionary, s: Dictionary):
	slot.name.text = s.name
	var can_use = player.energy >= s.cost and s.cooldown <= 0.0 and not s.soon and s.get("note", "") != "Make at Chemist"

	if s.soon:
		slot.info.text = "Coming soon"
	elif s.get("note", "") != "":
		slot.info.text = s.note
	elif s.cooldown > 0.0:
		slot.info.text = "%.1fs" % s.cooldown
	elif s.cost > 0.0:
		slot.info.text = "%d energy" % roundi(s.cost)
	else:
		slot.info.text = "Free"

	if can_use:
		slot.panel.modulate = Color(1, 1, 1)
	else:
		slot.panel.modulate = Color(0.45, 0.45, 0.45)
