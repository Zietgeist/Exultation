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
		if p:
			for c in left.get_children():
				c.queue_free()
			_you(p)


# ---------------- Contents ----------------

func _rebuild():
	for c in left.get_children() + right.get_children():
		c.queue_free()
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	_you(p)
	_gear(p)
	_journey()
	var close = Button.new()
	close.text = "Close (C or Esc)"
	close.pressed.connect(toggle)
	right.add_child(close)


func _you(p):
	_title(left, "%s %s  -  %s" % [SkinManager.race().name, SkinManager.class_label(p.player_class), GameState.ZONE_NAMES.get(get_tree().current_scene.scene_file_path, "")])
	_text(left, "World: %s" % SkinManager.skin_name(), DIM)
	_text(left, "Health %d / %d     Energy %.1f / %d" % [p.health, p.MAX_HEALTH, p.energy, p.MAX_ENERGY], SOFT)
	_text(left, "Move speed %.1f%s" % [p.SPEED * (1.0 + p.haste), "  (hasted)" if p.haste > 0.0 else ""], SOFT)

	_title(left, "Attacks", 20)
	var bonus = p._element_damage()
	_text(left, "Hit (left click): %d%s   reach %d" % [p.st_damage, "  +%d elemental" % bonus if bonus > 0 else "", p.ST_RANGE], SOFT)
	_text(left, "Sweep (right click): %d%s   up to %d enemies, %d° wide" % [p.aoe_damage, "  +%d elemental" % (bonus * 0.5) if bonus > 0 else "", p.aoe_max_targets, roundi(rad_to_deg(acos(clamp(p.aoe_cone, -1.0, 1.0))) * 2)], SOFT)
	_text(left, "Attack time: hit %.1fs, sweep %.1fs   (mouse wheel level %+d)" % [p.st_cooldown_time, p.aoe_cooldown_time, p.speed_level], SOFT)
	for el in p.element_bonus:
		_text(left, "  +%d %s damage per hit" % [p.element_bonus[el], SkinManager.element_label(el)], Crafting.ELEMENT_COLORS[el])
	if p.lifesteal > 0.0:
		_text(left, "  Heals %.1f per hit" % p.lifesteal, Color(0.5, 1.0, 0.5))
	if p.dps_boost_stacks > 0:
		_text(left, "  Boost x%d active" % pow(2, p.dps_boost_stacks), Color(1.0, 0.5, 0.3))

	_title(left, "Resistances", 20)
	for el in Crafting.ELEMENTS:
		var r = p.resistance(el)
		var line = "%s: %d%%" % [SkinManager.element_label(el), roundi(r * 100)]
		if p.ward_time > 0.0 and p.ward.get(el, 0.0) > 0.0:
			line += "  (potion ward, %ds left)" % p.ward_time
		_text(left, line, Crafting.ELEMENT_COLORS[el] if r > 0.0 else DIM)

	_title(left, "Skills", 20)
	var lines = []
	for s in p.get_skills():
		var cost = ("%d energy" % s.cost) if s.cost > 0 else "free"
		lines.append("%s  %s  (%s)%s" % [s.key, s.name, cost, "  - coming soon" if s.soon else ""])
	_text(left, "\n".join(lines), SOFT)


func _gear(p):
	var in_town = get_tree().current_scene.scene_file_path == "res://Home.tscn"
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
