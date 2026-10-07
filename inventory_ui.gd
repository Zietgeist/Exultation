extends CanvasLayer
## Inventory (press I): what you're carrying out here, and what's stored at Home.
## The game keeps running while it's open (multiplayer-friendly).
##   Carrying: gold bag, satchel (raw resources, limited space), potions, gear you're wearing.
##   At Home: banked gold, refined materials, gear you're not wearing.
## Refining (Smith/Chemist) turns satchel resources into materials and frees satchel space.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.6, 0.6, 0.6)
const BLUE = Color(0.75, 0.85, 1.0)

var panel: PanelContainer
var left: VBoxContainer
var right: VBoxContainer
var _refresh := 0.0


func _ready():
	layer = 45
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1000, 620)
	panel.position = Vector2(-500, -310)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.96)
	style.border_color = BLUE
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


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_I and (visible or not GameState.ui_open):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and visible:
		toggle()
		get_viewport().set_input_as_handled()


func toggle():
	visible = not visible
	GameState.ui_open = visible
	if visible:
		_rebuild()


func _process(delta):
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:	# gold and gathering keep changing while it's open
		_refresh = 1.0
		_rebuild()


func _rebuild():
	for c in left.get_children() + right.get_children():
		c.queue_free()
	_carrying()
	_at_home()


func _carrying():
	_title(left, "Carrying", 26)
	_text(left, "Gold bag: %d / %d%s" % [GameState.gold_carried, GameState.GOLD_CAPACITY, "  - FULL, take the portal home" if GameState.is_bag_full() else ""], GOLD)

	var used = GameState.satchel_count()
	var cap = GameState.satchel_capacity()
	_title(left, "Satchel  %d / %d" % [used, cap], 20)
	var bar = ProgressBar.new()
	bar.max_value = cap
	bar.value = used
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	left.add_child(bar)
	var keys = GameState.satchel.keys()
	keys.sort()
	var lines = []
	for k in keys:
		if GameState.satchel[k] > 0:
			var bits = k.split(":")
			lines.append("%s  x%d" % [GameState.resource_name(bits[0], int(bits[1])), GameState.satchel[k]])
	_text(left, "\n".join(lines) if lines.size() > 0 else "Empty. Gather with G (ore by hills, herbs by trees).", BLUE if lines.size() > 0 else DIM)
	if used >= cap:
		_text(left, "Full! Refine at the Smith or Chemist, or buy a bigger satchel at the Inn.", Color(1, 0.6, 0.45))

	var pots = Crafting.potions()
	_title(left, "Potions (press 1)  %d" % pots.size(), 20)
	_text(left, "\n".join(pots.map(func(it): return it.name)) if pots.size() > 0 else "None. Make them at the Chemist.", SOFT if pots.size() > 0 else DIM)

	_title(left, "Wearing", 20)
	var worn = Crafting.equipped_items().filter(func(it): return it.slot != "potion")
	_text(left, "\n".join(worn.map(func(it): return "%s  (%s)" % [Story.display_name(it), SkinManager.slot_label(it.slot)])) if worn.size() > 0 else "Nothing yet. The Smith makes gear.", SOFT if worn.size() > 0 else DIM)

	var buffs = GameState.buffs.keys().map(func(id): return GameState.INN_OFFERS[id].name + ": " + GameState.INN_OFFERS[id].about)
	if buffs.size() > 0:
		_title(left, "Inn treats (until your next rest)", 20)
		_text(left, "\n".join(buffs), Color(0.6, 1.0, 0.6))


func _at_home():
	_title(right, "Stored at Home", 26)
	_text(right, "Banked gold: %d  (spend it on crafting and at the Inn)" % GameState.gold_banked, GOLD)
	_title(right, "Materials", 20)
	var mats = Crafting.stash_list().filter(func(e): return not Crafting.is_sigil(e.mat))
	_text(right, "\n".join(mats.map(func(e): return "%s  x%d" % [e.name, e.count])) if mats.size() > 0 else "None yet. Refine resources at the Smith or Chemist.", BLUE if mats.size() > 0 else DIM)
	_title(right, "Gear not worn", 20)
	var spare = Crafting.items.filter(func(it): return it.slot != "potion" and not Crafting.is_equipped(it.id))
	_text(right, "\n".join(spare.map(func(it): return Story.display_name(it))) if spare.size() > 0 else "None.", SOFT if spare.size() > 0 else DIM)
	var close = Button.new()
	close.text = "Close (I or Esc)"
	close.pressed.connect(toggle)
	right.add_child(close)


func _title(box: VBoxContainer, t: String, size := 26):
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD if size >= 26 else Color(0.95, 0.9, 0.75))
	box.add_child(l)


func _text(box: VBoxContainer, t: String, color: Color):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
