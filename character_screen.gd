extends CanvasLayer
## Character screen (press C). Shows who you are, what you're carrying and how far you've come.
## The game keeps running while it's open (ready for multiplayer). Gear can be swapped here, but only in town.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.65, 0.65, 0.65)
const GEAR_VIEW = preload("res://gear_view.gd")

var panel: PanelContainer
var left: VBoxContainer
var right: VBoxContainer
var you_box: VBoxContainer		# refreshed twice a second (health, energy, attacks)


func _ready():
	layer = 45
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1000, 620)
	panel.position = Vector2(-500, -310)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.96)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(968, 588)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var cols = HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 28)
	scroll.add_child(cols)
	left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(right)
	visible = false
	Crafting.changed.connect(func(): if visible: _rebuild())


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_C and (visible or not GameState.ui_open):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and visible:
		toggle()
		get_viewport().set_input_as_handled()


func toggle():
	visible = not visible
	GameState.ui_open = visible	# the game keeps running (multiplayer-friendly); only your attack keys are paused
	if visible:
		_rebuild()


var _refresh = 0.0

## The game keeps running, so keep the "You" side (health, energy, wards) up to date.
func _process(delta):
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		var p = get_tree().get_first_node_in_group("player")
		if p and is_instance_valid(you_box):
			for c in you_box.get_children():
				c.queue_free()
			_you(p)


# ---------------- Contents ----------------

func _rebuild():
	for c in left.get_children() + right.get_children():
		c.queue_free()
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	_traits(p)
	_pet(p)
	you_box = VBoxContainer.new()
	left.add_child(you_box)
	_you(p)
	_gear(p)
	_journey()
	var close = Button.new()
	close.text = "Close (C or Esc)"
	close.pressed.connect(toggle)
	right.add_child(close)


func _you(p):
	_title(you_box, "%s %s  -  %s" % [SkinManager.race().name, SkinManager.class_label(p.player_class), GameState.current_zone])
	_text(you_box, "World: %s" % SkinManager.skin_name(), DIM)
	_text(you_box, Traits.rest_text(), Color(0.7, 0.95, 0.7) if not Traits.is_driven() else Color(1.0, 0.6, 0.4))
	_text(you_box, "Health %d / %d     Energy %.1f / %d" % [p.health, p.MAX_HEALTH, p.energy, p.MAX_ENERGY], SOFT)
	_text(you_box, "Move speed %.1f%s" % [p.SPEED * (1.0 + p.haste), "  (hasted)" if p.haste > 0.0 else ""], SOFT)

	_title(you_box, "Attacks", 20)
	var bonus = p._element_damage()
	_text(you_box, "Hit (left click): %d%s   reach %d" % [p.st_damage, "  +%d elemental" % bonus if bonus > 0 else "", p.ST_RANGE], SOFT)
	_text(you_box, "Sweep (right click): %d%s   up to %d enemies, %d° wide" % [p.aoe_damage, "  +%d elemental" % (bonus * 0.5) if bonus > 0 else "", p.aoe_max_targets, roundi(rad_to_deg(acos(clamp(p.aoe_cone, -1.0, 1.0))) * 2)], SOFT)
	_text(you_box, "Attack time: hit %.1fs, sweep %.1fs   (mouse wheel level %+d)" % [p.st_cooldown_time, p.aoe_cooldown_time, p.speed_level], SOFT)
	if p.auto:
		var al = _text(you_box, "Auto-attack (Tab): %s   Main target (R): %s   - hover for more" % ["ON" if p.auto.on else "off", p.auto.mode_name()], GOLD if p.auto.on else SOFT)
		al.mouse_filter = Control.MOUSE_FILTER_STOP	# so the tooltip shows
		al.tooltip_text = "Auto-attack fights enemies that are already after you. It never starts a fight.\n%s with your %s.\nYour own clicks always win.\n\nMain target: %s\n%s\nPress R to change: %s." % [
			Crafting.auto_text(p.auto_sweep), p.weapon_name, p.auto.mode_name(), p.auto.MODE_TIPS[p.auto.mode],
			", ".join(p.auto.MODES.map(func(m): return p.auto.MODE_NAMES[m]))]
	for el in p.element_bonus:
		_text(you_box, "  +%d %s damage per hit" % [p.element_bonus[el], SkinManager.element_label(el)], Crafting.ELEMENT_COLORS[el])
	if p.lifesteal > 0.0:
		_text(you_box, "  Heals %.1f per hit" % p.lifesteal, Color(0.5, 1.0, 0.5))
	if p.dps_boost_stacks > 0:
		_text(you_box, "  Boost x%d active" % pow(p.boost_base, p.dps_boost_stacks), Color(1.0, 0.5, 0.3))

	_title(you_box, "Resistances", 20)
	for el in Crafting.ELEMENTS:
		var r = p.resistance(el)
		var line = "%s: %d%%" % [SkinManager.element_label(el), roundi(r * 100)]
		if p.ward_time > 0.0 and p.ward.get(el, 0.0) > 0.0:
			line += "  (potion ward, %ds left)" % p.ward_time
		_text(you_box, line, Crafting.ELEMENT_COLORS[el] if r > 0.0 else DIM)

	_title(you_box, "Skills  (they rank up as you use them)", 20)
	for s in p.skills.skill_list():
		var cost = ("%d energy" % s.cost) if s.cost > 0 else "free"
		_text(you_box, "%s  %s  rank %d  (%s)  -  %s" % [s.key, s.name, s.rank, cost, Classes.rank_progress(p.player_class, s.key)], SOFT)
		_text(you_box, "      " + s.about, DIM)
	for line in p.skills.status_lines():
		_text(you_box, "  " + line, Color(1.0, 0.75, 0.35))


## Who you're becoming: six sliders that move with how you play. Hover a name for what it does.
func _traits(p):
	_title(left, "%s  -  Day %d" % [Story.player_name, Story.day()])
	_title(left, "Who you're becoming", 20)
	_text(left, "These move on their own with how you play. Hover a name or slider to see what it does.", DIM)
	for t in Traits.ORDER:
		var info = Traits.TENSIONS[t]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		left.add_child(row)
		var l = _side_label(info.left, info.left_tip, Traits.left(t) > 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
		var sl = HSlider.new()
		sl.min_value = -100
		sl.max_value = 100
		sl.value = Traits.values[t]
		sl.editable = false
		sl.focus_mode = Control.FOCUS_NONE
		sl.custom_minimum_size = Vector2(170, 0)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.tooltip_text = "%s\n\n%s: %s\n\n%s: %s" % [Traits.label(t), info.left, info.left_tip, info.right, info.right_tip]
		var h = Traits.history.get(t, [])
		if h.size() > 0:
			sl.tooltip_text += "\n\nLately:\n" + "\n".join(h)
		row.add_child(sl)
		row.add_child(_side_label(info.right, info.right_tip, Traits.right(t) > 0.0))
		var state = Label.new()
		state.text = Traits.label(t)
		state.add_theme_color_override("font_color", DIM)
		state.add_theme_font_size_override("font_size", 13)
		row.add_child(state)


## Your pet: how it's growing.
func _pet(p):
	var pet = p.pet
	if pet == null:
		return
	_title(left, "%s  (%s)" % [pet.full_name(), pet.mood()], 20)
	var rows = [
		["Bond", pet.bond, "Grows when you feed it (T near it: one herb), rest at Home together, and protect it.\nHigh Bond: faster, gathers from farther and quicker. At 80+ it gathers two nodes at once."],
		["Sturdy", pet.sturdy, "Grows when it gets hit and gets through scares with you close by.\nSturdy: more health, but slower. (Low = nimble.)"],
		["Stress", pet.stress, "Goes up when it's hit or enemies are near. Comes down with calm time, much faster when you're close.\nToo much at once and it's overwhelmed: it hides behind you until it settles."],
		["Skittish", pet.skittish, "Being overwhelmed again and again (worse when you're far away) makes it panic sooner.\nCalm time near you and resting at Home heal it."],
		["Hunger", pet.hunger, "Goes up while you're out. A hungry pet slowly drifts away. Feed it a herb (T)."],
	]
	for r in rows:
		var row = HBoxContainer.new()
		left.add_child(row)
		var l = _side_label(r[0], r[2], false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
		var bar = ProgressBar.new()
		bar.max_value = 100
		bar.value = r[1]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(170, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.tooltip_text = r[2]
		row.add_child(bar)
		var v = Label.new()
		v.text = "%d" % r[1]
		v.add_theme_color_override("font_color", DIM)
		row.add_child(v)
	_text(left, "Gathered %d · fed %d times · protected %d times · knocked out %d times" % [pet.record.gathered, pet.record.fed, pet.record.guarded, pet.record.knockouts], DIM)


func _side_label(text: String, tip: String, active: bool) -> Label:
	var l = Label.new()
	l.text = text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP	# labels ignore the mouse by default; this turns the tooltip on
	l.custom_minimum_size = Vector2(82, 0)
	l.add_theme_color_override("font_color", GOLD if active else SOFT)
	return l


func _gear(p):
	var in_town = Zones.local_path() == "res://Home.tscn"
	var pots = Crafting.potions()
	_text(right, "Potions (press 1): %d" % pots.size(), GOLD if pots.size() > 0 else DIM)
	GEAR_VIEW.build(right, in_town, func(): _rebuild.call_deferred())


func _journey():
	_title(right, "Journey", 20)
	var unlocked = []
	var cleared = []
	for z in GameState.ZONE_ORDER:
		if not ResourceLoader.exists(z):
			continue
		if GameState.is_unlocked(z):
			unlocked.append(GameState.ZONE_NAMES[z])
		if GameState.is_zone_cleared(z):
			cleared.append(GameState.ZONE_NAMES[z])
	var mins = int(SessionManager.play_seconds_today / 60.0)
	_text(right, "Zones open: %s\nZones cleared: %s\nGold banked: %d   (carrying %d / %d)\nFlow sessions today: %d   Time today: %dh %02dm\nTimes defeated: %d" % [
		", ".join(unlocked), ", ".join(cleared) if cleared.size() > 0 else "none yet",
		GameState.gold_banked, GameState.gold_carried, GameState.GOLD_CAPACITY,
		SessionManager.blocks_today, mins / 60, mins % 60, GameState.deaths], SOFT)
	_text(right, GameState.satchel_text(), Color(0.75, 0.85, 1.0))
	var parts = []
	for s in Crafting.stash_list():
		parts.append("%s x%d" % [s.name, s.count])
	_text(right, "Materials: " + (", ".join(parts) if parts.size() > 0 else "none"), Color(0.75, 0.85, 1.0))
	_trials()


## Shrine trial ladder: your level in each ability and when the next level opens.
func _trials():
	_title(right, "Trials (levels I-VIII)", 20)
	var lines = []
	for id in Trials.TYPES:
		var l = Trials.level(id)
		var w = Trials.wait_text(id)
		var next = "mastered" if w == "mastered" else ("next level open now" if w == "" else "next level in " + w)
		var rec = Crafting.recipe(Crafting.advanced_id(id, l)).label if l > 0 else "basic recipes only"
		lines.append("%s %s - %s (%s)" % [Trials.ability_name(id), Trials.ROMAN[l] if l > 0 else "-", next, rec])
	_text(right, "\n".join(lines), Color(0.85, 0.8, 1.0))


# ---------------- helpers ----------------

func _title(box: VBoxContainer, t: String, size := 26):
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	box.add_child(l)


func _text(box: VBoxContainer, t: String, color: Color):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l
