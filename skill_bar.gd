extends HBoxContainer
## Skill bar at the bottom of the screen.
## Shows each skill, the button to press, and its energy cost.
## Skills are dimmed when you don't have enough energy or they're cooling down.
## Hover a skill: a box above it says what it does (name, rank, cost, cooldown, your numbers).
## (Our own box, not Godot's tooltip: the game's mouse handling kept those from showing.)

var player = null
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
var slots = []
var _tip: PanelContainer
var _tip_label: Label
var _tip_for := -1		# which slot the box is showing (-1 = none)


func _ready():
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	_tip = PanelContainer.new()
	_tip.top_level = true	# drawn over everything, placed by hand
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.05, 0.08, 0.95)
	st.border_color = Color(1.0, 0.85, 0.3)
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	_tip.add_theme_stylebox_override("panel", st)
	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(330, 0)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_label)
	_tip.visible = false
	add_child(_tip)


func _process(_delta):
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
		_build(player.get_skills())

	var skills = player.get_skills()
	for i in range(min(skills.size(), slots.size())):
		_update_slot(slots[i], skills[i])
	_update_tip(skills)


## The hover box: is the mouse over a slot? (checked every frame, so nothing can swallow it)
func _update_tip(skills: Array):
	var mouse = get_global_mouse_position()
	var over = -1
	for i in range(min(skills.size(), slots.size())):
		if slots[i].panel.get_global_rect().has_point(mouse):
			over = i
	if over == -1:
		_tip.visible = false
		_tip_for = -1
		return
	_tip_label.text = _tip_text(skills[over])
	_tip.visible = true
	_tip.reset_size()
	var r = slots[over].panel.get_global_rect()
	var vw = get_viewport_rect().size
	var x = clampf(r.position.x + r.size.x / 2.0 - _tip.size.x / 2.0, 8.0, vw.x - _tip.size.x - 8.0)
	_tip.global_position = Vector2(x, r.position.y - _tip.size.y - 8.0)
	_tip_for = over


func _tip_text(s: Dictionary) -> String:
	var key = "F / Space" if s.key == "F" else s.key
	match s.key:
		"LMB":
			return "STRIKE  (left click)\nHits one enemy: %d damage, every %.1f s, reach %d m.\nBest for: one tough enemy (a pack leader, a Master, a Boss)." % [player.st_damage, player.st_cooldown_time, player.ST_RANGE]
		"RMB":
			return "SWEEP  (right click)\nHits up to %d enemies in front of you: %d damage each, every %.1f s.\nBest for: a close group of small enemies." % [player.aoe_max_targets, player.aoe_damage, player.aoe_cooldown_time]
		"1":
			var ps = Crafting.potions()
			if ps.is_empty():
				return "POTION  (1)\nNo potions. Make them at the Chemist (or Alchemist) from tonics and essences."
			return "POTION  (1)  -  %d left\nDrinks your oldest potion:\n%s" % [ps.size(), Crafting.describe(ps[0])]
	var cid = player.skills.class_id if player.skills else ""
	var def = Classes.skill(cid, s.key)
	var lines = []
	var rank = int(s.get("rank", 1))
	lines.append("%s  (%s)%s" % [s.name.to_upper(), key, ("  -  rank %s" % ROMAN[mini(rank, 10)]) if rank > 1 else ""])
	var cost = "%d energy" % roundi(s.cost) if s.cost > 0.0 else "free"
	var cd = float(def.get("cooldown", 0.0))
	lines.append(cost + ("  -  %d s cooldown" % roundi(cd) if cd > 0.0 else ""))
	if str(s.get("about", "")) != "":
		lines.append("")
		lines.append(str(s.about))
	if cid != "":
		lines.append("")
		lines.append("Gets stronger with use: " + Classes.rank_progress(cid, s.key))
	return "\n".join(lines)


func _build(skills: Array):
	for child in get_children():
		if child != _tip:	# keep the hover box
			child.queue_free()
	slots.clear()
	for s in skills:
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(110, 70)
		var box = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		panel.add_child(box)

		var key_label = Label.new()
		key_label.text = "F / Space" if s.key == "F" else s.key
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
	slot.name.text = s.name + (" " + ROMAN[min(s.rank, 10)] if s.get("rank", 1) > 1 else "")
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
