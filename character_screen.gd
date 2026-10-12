extends CanvasLayer
## Character window (press C). Four tabs:
##   Gear      your race's body with every gear slot on it (paper_doll.gd), plus gear you're not wearing.
##   Stats     health, energy, attacks, resistances and skills, as bars and cards.
##   Becoming  the six sliders that move with how you play, and your pet.
##   Journey   zones, gold, time, and the Trial ladder.
## The game keeps running while it's open (multiplayer). Gear can be changed only in town.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.65, 0.65, 0.65)
const CARD_BG = Color(0.11, 0.1, 0.13)
const TILE = preload("res://item_tile.gd")
const ICONS = preload("res://icons.gd")
const DOLL = preload("res://paper_doll.gd")
const TABS = ["Gear", "Stats", "Becoming", "Journey"]

var panel: PanelContainer
var tabs: TabContainer
var pages := {}				# tab name -> VBoxContainer
var _tab := 0
var _refresh := 0.0
var _menu: PopupMenu
var _menu_actions := []


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
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(976, 596)
	panel.add_child(tabs)
	for t in TABS:
		var scroll = ScrollContainer.new()
		scroll.name = t
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var page = VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 8)
		scroll.add_child(page)
		pages[t] = page
	tabs.tab_changed.connect(func(i): _tab = i; if visible: _rebuild())	# after the pages exist
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(func(i): _menu_actions[i].call())
	panel.add_child(_menu)
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
		tabs.current_tab = _tab
		_rebuild()


## Stats change while you play (health, energy, wards): refresh that tab.
func _process(delta):
	if not visible or TABS[_tab] != "Stats":
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_rebuild()


func _rebuild():
	var page = pages[TABS[_tab]]
	for c in page.get_children():
		c.queue_free()
	var p = Zones.player
	if p == null:
		return
	_header(page, p)
	match TABS[_tab]:
		"Gear": _gear(page, p)
		"Stats": _stats(page, p)
		"Becoming": _becoming(page, p)
		"Journey": _journey(page)


func _header(page, p):
	var row = HBoxContainer.new()
	page.add_child(row)
	var t = _label("%s  ·  %s %s" % [Story.player_name, SkinManager.race().name, SkinManager.class_label(p.player_class)], GOLD, 24)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	row.add_child(_label("Day %d  ·  %s  ·  %s" % [Story.day(), GameState.current_zone, SkinManager.skin_name()], DIM, 14))
	var feedback = Button.new()
	feedback.text = "Send feedback"
	feedback.tooltip_text = "Opens the Discord feedback channel. @mention the bot with ideas or bugs."
	feedback.pressed.connect(GameState.open_feedback)
	row.add_child(feedback)
	var close = Button.new()
	close.text = "Close (C)"
	close.pressed.connect(toggle)
	row.add_child(close)


# ---------------- Gear ----------------

func _gear(page, p):
	var in_town = Zones.local_path() == "res://Home.tscn"
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	page.add_child(cols)
	var left = VBoxContainer.new()
	cols.add_child(left)
	var race = SkinManager.race()
	left.add_child(_label(race.get("about", ""), DIM, 13, 440.0))
	var doll = DOLL.new()
	doll.setup(in_town, func(): _rebuild.call_deferred(), Vector2(440, 470))
	left.add_child(doll)

	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_label("Weapon: %s" % p.weapon_name, SOFT, 16))
	right.add_child(_label("Potions (press 1)", GOLD, 18))
	var pots = Crafting.potions()
	var prow = _grid(right, 7)
	for it in pots:
		prow.add_child(TILE.for_item(it, 50))
	if pots.is_empty():
		right.add_child(_label("None. Make them at the Chemist.", DIM, 13))
	right.add_child(_label("Not worn", GOLD, 18))
	right.add_child(_label("Click one to wear it (in town)." if in_town else "You can change gear in town.", DIM, 13))
	var grid = _grid(right, 7)
	var spare = Crafting.items.filter(func(it): return it.slot != "potion" and not Crafting.is_equipped(it.id))
	for it in spare:
		var t = TILE.for_item(it, 50)
		if Crafting.slot_for(it) == null:
			t.tooltip_text += "\n\nYour race can't wear this."
			t.modulate = Color(1, 1, 1, 0.5)
		var item = it
		t.pressed.connect(func(): _spare_clicked(item, in_town))
		t.wire_gear(_rebuild.call_deferred)
		grid.add_child(t)
	if spare.is_empty():
		right.add_child(_label("Nothing else yet.", DIM, 13))


func _spare_clicked(it: Dictionary, in_town: bool):
	if not in_town:
		GameState.notify("You can change gear in town.")
		return
	_menu.clear()
	_menu_actions.clear()
	if Crafting.slot_for(it) != null:
		_menu.add_item("Wear it")
		_menu_actions.append(func(): Crafting.equip(it.id); _rebuild.call_deferred())
	if Net.is_online() and Crafting.can_give(it):	# unworn: give it to a friend (its story goes with it)
		for o in Net.others():
			_menu.add_item("Give to " + o[1])
			var to_id = o[0]
			_menu_actions.append(func(): Crafting.give(it.id, to_id); _rebuild.call_deferred())
	if _menu_actions.is_empty():
		return
	_menu.popup(Rect2i(Vector2i(panel.get_global_mouse_position()), Vector2i.ZERO))


# ---------------- Stats ----------------

func _stats(page, p):
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	page.add_child(cols)
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	_bar(left, "Health", p.health, p.MAX_HEALTH, Color(0.85, 0.25, 0.25), "%d / %d" % [p.health, p.MAX_HEALTH])
	_bar(left, "Energy", p.energy, p.MAX_ENERGY, Color(0.3, 0.6, 1.0), "%.1f / %d" % [p.energy, p.MAX_ENERGY])
	left.add_child(_label(Traits.rest_text(), Color(0.7, 0.95, 0.7) if not Traits.is_driven() else Color(1.0, 0.6, 0.4), 13, 460.0))

	left.add_child(_label("Attacks", GOLD, 18))
	var bonus = p._element_damage()
	var cards = _grid(left, 3)
	cards.add_child(_card("Hit", "%d" % p.st_damage, "left click · reach %d%s" % [p.ST_RANGE, " · +%d elem." % bonus if bonus > 0 else ""],
		"Single strike on one enemy (the one nearest your mouse, or your main target)."))
	cards.add_child(_card("Sweep", "%d" % p.aoe_damage, "right click · up to %d · %d°" % [p.aoe_max_targets, roundi(rad_to_deg(acos(clamp(p.aoe_cone, -1.0, 1.0))) * 2)],
		"Hits enemies in a cone in front of you."))
	cards.add_child(_card("Attack time", "%.1fs / %.1fs" % [p.st_cooldown_time, p.aoe_cooldown_time], "hit / sweep · speed %+d" % p.speed_level,
		"Faster attacks for less damage each, or slower and harder.\nChange it with the Faster / Harder buttons below."))
	cards.add_child(_card("Move", "%.1f" % (p.SPEED * (1.0 + p.haste)), "hasted" if p.haste > 0.0 else "speed", "How fast you run."))
	if p.auto:
		cards.add_child(_card("Auto (Tab)", "ON" if p.auto.on else "off", "target: %s (R)" % p.auto.mode_name(),
			"Auto-attack fights enemies that are already after you. It never starts a fight.\nStyle: %s (mouse wheel: up = single target, down = multi target).\nYour own clicks always win.\n\nMain target: %s\n%s" % [
			p.auto.stance_name(), p.auto.mode_name(), p.auto.MODE_TIPS[p.auto.mode]]))
	if p.lifesteal > 0.0:
		cards.add_child(_card("Lifesteal", "%.1f" % p.lifesteal, "heals per hit", "Each hit heals you a little."))
	if p.dps_boost_stacks > 0:
		cards.add_child(_card("Boost", "x%.1f" % p.boost_mult, "%d stacks" % p.dps_boost_stacks, "Your damage boost right now."))
	_speed_row(left, p)
	for el in p.element_bonus:
		left.add_child(_label("  +%d %s damage per hit" % [p.element_bonus[el], SkinManager.element_label(el)], Crafting.ELEMENT_COLORS[el], 14))

	right.add_child(_label("Resistances", GOLD, 18))
	for el in Crafting.ELEMENTS:
		var r = p.resistance(el)
		var note = "%d%%" % roundi(r * 100)
		if p.ward_time > 0.0 and p.ward.get(el, 0.0) > 0.0:
			note += "  (ward %ds)" % p.ward_time
		_bar(right, SkinManager.element_label(el), r * 100.0, 100.0, Crafting.ELEMENT_COLORS[el], note)
	right.add_child(_label("Skills  (they rank up as you use them)", GOLD, 18))
	var sk = _grid(right, 3)
	for s in p.skills.skill_list():
		sk.add_child(_card("%s  %s" % [s.key, s.name], "rank %d" % s.rank, ("%d energy" % s.cost) if s.cost > 0 else "free",
			"%s\n\n%s" % [s.about, Classes.rank_progress(p.player_class, s.key)]))
	for line in p.skills.status_lines():
		right.add_child(_label("  " + line, Color(1.0, 0.75, 0.35), 13))


# ---------------- Becoming (traits) and the pet ----------------

func _becoming(page, p):
	page.add_child(_label("These move on their own with how you play. Hover a name or slider to see what it does.", DIM, 13))
	for t in Traits.ORDER:
		var info = Traits.TENSIONS[t]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		page.add_child(row)
		var l = _side_label(info.left, info.left_tip, Traits.left(t) > 0.0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(l)
		var sl = HSlider.new()
		sl.min_value = -100
		sl.max_value = 100
		sl.value = Traits.values[t]
		sl.editable = false
		sl.focus_mode = Control.FOCUS_NONE
		sl.custom_minimum_size = Vector2(320, 0)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.tooltip_text = "%s\n\n%s: %s\n\n%s: %s" % [Traits.label(t), info.left, info.left_tip, info.right, info.right_tip]
		var h = Traits.history.get(t, [])
		if h.size() > 0:
			sl.tooltip_text += "\n\nLately:\n" + "\n".join(h)
		row.add_child(sl)
		row.add_child(_side_label(info.right, info.right_tip, Traits.right(t) > 0.0))
		row.add_child(_label(Traits.label(t), DIM, 13))
	var pet = p.pet
	if pet == null:
		return
	page.add_child(_label("%s  (%s)" % [pet.full_name(), pet.mood()], GOLD, 20))
	_bar(page, "Bond", pet.bond, 100.0, Color(0.9, 0.5, 0.9), "%d" % pet.bond)
	_bar(page, "Food", pet.food(), 100.0, Color(1.0, 0.6, 0.2), "%d" % pet.food())
	var b = Button.new()
	b.text = "Open the pet window (K)"
	b.pressed.connect(func():
		toggle()
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if c.get_script() and c.get_script().resource_path == "res://pet_ui.gd":
				c.toggle())
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(b)


# ---------------- Journey ----------------

func _journey(page):
	page.add_child(_label("Zones", GOLD, 18))
	var chips = _grid(page, 6)
	for z in GameState.ZONE_ORDER:
		if not ResourceLoader.exists(z):
			continue
		var state = "cleared" if GameState.is_zone_cleared(z) else ("open" if GameState.is_unlocked(z) else "locked")
		var c = {"cleared": GOLD, "open": Color(0.45, 0.75, 1.0), "locked": Color(0.3, 0.3, 0.33)}[state]
		chips.add_child(_card(GameState.ZONE_NAMES[z], state, "", "", c))
	var mins = int(SessionManager.play_seconds_today / 60.0)
	var nums = _grid(page, 5)
	nums.add_child(_card("Gold banked", "%d" % GameState.gold_banked, "carrying %d / %d" % [GameState.gold_carried, GameState.GOLD_CAPACITY], ""))
	nums.add_child(_card("Flow today", "%d" % SessionManager.blocks_today, "%dh %02dm played" % [mins / 60, mins % 60], ""))
	nums.add_child(_card("Defeated", "%d" % GameState.deaths, "times", ""))
	nums.add_child(_card("Satchel", "%d / %d" % [GameState.satchel_count(), GameState.satchel_capacity()], "I: inventory", ""))
	page.add_child(_label("Trials (levels I-VIII)", GOLD, 18))
	for id in Trials.TYPES:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		page.add_child(row)
		var l = _label(Trials.ability_name(id), SOFT, 15)
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var lvl = Trials.level(id)
		for i in range(1, Trials.MAX_LEVEL + 1):	# one pip per level
			var pip = ColorRect.new()
			pip.custom_minimum_size = Vector2(22, 14)
			pip.color = Trials.TYPES[id].color if i <= lvl else Color(0.2, 0.2, 0.24)
			pip.tooltip_text = "Level %s" % Trials.ROMAN[i]
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pip)
		var w = Trials.wait_text(id)
		row.add_child(_label("  " + ("mastered" if w == "mastered" else ("next level open now" if w == "" else "next in " + w)), DIM, 13))


# ---------------- helpers ----------------

## Attack speed setting: Harder (slower, bigger hits) <-> Faster (quicker, lighter hits).
func _speed_row(box, p):
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_label("Attack speed:", SOFT, 15))
	var harder = Button.new()
	harder.text = "< Harder"
	harder.tooltip_text = "Slower attacks, more damage each."
	harder.disabled = p.speed_level <= -p.MAX_SPEED_LEVELS
	harder.pressed.connect(func(): p.change_attack_speed(-1); _rebuild())
	row.add_child(harder)
	row.add_child(_label("%+d" % p.speed_level, GOLD, 16))
	var faster = Button.new()
	faster.text = "Faster >"
	faster.tooltip_text = "Quicker attacks, less damage each."
	faster.disabled = p.speed_level >= p.MAX_SPEED_LEVELS
	faster.pressed.connect(func(): p.change_attack_speed(1); _rebuild())
	row.add_child(faster)


func _label(t: String, color: Color, size := 16, wrap_width := 0.0) -> Label:
	var l = Label.new()
	l.text = t
	if wrap_width > 0.0:	# long text: wrap at this width
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = wrap_width
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func _grid(box, columns: int) -> GridContainer:
	var g = GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	box.add_child(g)
	return g


## A small card: title, a big value, a note underneath. Hover for the tooltip.
func _card(title: String, value: String, note: String, tip: String, accent := GOLD) -> PanelContainer:
	var c = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = CARD_BG
	st.border_color = accent.darkened(0.3)
	st.border_width_left = 3
	st.set_content_margin_all(8)
	c.add_theme_stylebox_override("panel", st)
	c.custom_minimum_size = Vector2(140, 0)
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	for bit in [[title, DIM, 12], [value, accent, 20], [note, SOFT, 11]]:
		if bit[0] == "":
			continue
		var l = _label(bit[0], bit[1], bit[2])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	return c


## A labeled bar: name on the left, a colored bar, the number on the right.
func _bar(box, name_: String, value: float, max_v: float, color: Color, note: String):
	var row = HBoxContainer.new()
	box.add_child(row)
	var l = _label(name_, SOFT, 14)
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	var b = ProgressBar.new()
	b.max_value = max_v
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(240, 16)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	row.add_child(b)
	row.add_child(_label(note, DIM, 13))


func _side_label(text: String, tip: String, active: bool) -> Label:
	var l = Label.new()
	l.text = text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP	# labels ignore the mouse by default; this turns the tooltip on
	l.custom_minimum_size = Vector2(82, 0)
	l.add_theme_color_override("font_color", GOLD if active else SOFT)
	return l
