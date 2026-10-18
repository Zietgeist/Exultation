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
const TILE = preload("res://item_tile.gd")

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
		var sig = _signature()
		if sig != _last_sig:	# only when something changed, so hovering a tile keeps its tooltip
			_rebuild()


var _last_sig := ""

func _signature() -> String:
	return str([GameState.gold_carried, GameState.gold_banked, GameState.satchel, GameState.storehouse, Crafting.stash, Crafting.items.size(), Crafting.equipped, GameState.buffs.keys()])


func _rebuild():
	_last_sig = _signature()
	for c in left.get_children() + right.get_children():
		c.queue_free()
	_carrying()
	_at_home()


func _carrying():
	_title(left, "Carrying", 26)
	var gold_row = HBoxContainer.new()
	left.add_child(gold_row)
	gold_row.add_child(TILE.make("gold", GOLD, 7, 0, "Gold bag: gold you've picked up. Take it Home to bank it.", 44))
	var gb = _meter(gold_row, GameState.gold_carried, GameState.GOLD_CAPACITY, Color(1.0, 0.8, 0.15))
	gold_row.add_child(_small("%d / %d%s" % [GameState.gold_carried, GameState.GOLD_CAPACITY, "  FULL: take the portal home" if GameState.is_bag_full() else ""], GOLD))

	var used = GameState.satchel_count()
	var cap = GameState.satchel_capacity()
	var sat_row = HBoxContainer.new()
	left.add_child(sat_row)
	sat_row.add_child(TILE.make("satchel", Color.WHITE, 1, 0, "Satchel: raw resources. Refine them at the Smith or Chemist to free space.", 44))
	_meter(sat_row, used, cap, Color(0.55, 0.75, 1.0))
	sat_row.add_child(_small("%d / %d%s" % [used, cap, "  FULL" if used >= cap else ""], BLUE if used < cap else Color(1, 0.6, 0.45)))
	var grid = _grid(left)
	var keys = GameState.satchel.keys()
	keys.sort()
	for k in keys:
		if GameState.satchel[k] <= 0:
			continue
		var bits = k.split(":")
		var type = bits[0]
		var q = int(bits[1])
		grid.add_child(TILE.make(type, GameState.RESOURCE_INFO[type].color, q, GameState.satchel[k],
			"%s  x%d\nRefines into %s at the %s." % [GameState.resource_name(type, q), GameState.satchel[k],
			Crafting.MATERIAL_LABELS.get(Crafting.REFINE[type].to, ""), Crafting.REFINE[type].shop.capitalize()]))
	if grid.get_child_count() == 0:
		_text(left, "Empty. Gather with G (ore by hills, herbs by trees).", DIM)

	var pots = Crafting.potions()
	_title(left, "Potions (press 1)", 20)
	var pg = _grid(left)
	for it in pots:
		pg.add_child(TILE.for_item(it, 52))
	if pots.is_empty():
		_text(left, "None. Make them at the Chemist.", DIM)

	_title(left, "Wearing", 20)
	var wg = _grid(left)
	for it in Crafting.equipped_items().filter(func(it): return it.slot != "potion"):
		var wt = TILE.for_item(it, 52)
		wt.wire_gear(_rebuild.call_deferred)
		wg.add_child(wt)
	if wg.get_child_count() == 0:
		_text(left, "Nothing yet. The Smith makes gear.", DIM)

	var buffs = GameState.buffs.keys().filter(func(id): return GameState.has_buff(id)).map(func(id): return GameState.INN_OFFERS[id].name + ": " + GameState.buff_text(id))
	if buffs.size() > 0:
		_title(left, "Inn treats (until your next rest)", 20)
		_text(left, "\n".join(buffs), Color(0.6, 1.0, 0.6))


func _at_home():
	_title(right, "Stored at Home", 26)
	var bank = HBoxContainer.new()
	right.add_child(bank)
	bank.add_child(TILE.make("gold", GOLD, 7, 0, "Banked gold: spend it on crafting and at the Inn.", 44))
	bank.add_child(_small("Banked gold: %d" % GameState.gold_banked, GOLD))
	_title(right, "Storehouse (raw resources)", 20)
	var sg = _grid(right)
	var skeys = GameState.storehouse.keys()
	skeys.sort()
	for k in skeys:
		var bits = k.split(":")
		var type = bits[0]
		var q = int(bits[1])
		sg.add_child(TILE.make(type, GameState.RESOURCE_INFO[type].color, q, GameState.storehouse[k],
			"%s  x%d (stored)\nRefines into %s at the %s." % [GameState.resource_name(type, q), GameState.storehouse[k],
			Crafting.MATERIAL_LABELS.get(Crafting.REFINE[type].to, ""), Crafting.REFINE[type].shop.capitalize()]))
	if sg.get_child_count() == 0:
		_text(right, "Empty. Step into the bank (the Deposit Shrine at Home, or a camp bank) to empty your satchel here.", DIM)
	_title(right, "Materials", 20)
	var mg = _grid(right)
	for e in Crafting.stash_list():
		var kind = "sigil" if Crafting.is_sigil(e.mat) else e.mat
		var col = Trials.TYPES.get(e.mat.trim_prefix("sigil_"), {}).get("color", GOLD) if kind == "sigil" else _mat_color(e.mat)
		mg.add_child(TILE.make(kind, col, e.q, e.count, "%s  x%d" % [e.name, e.count]))
	if mg.get_child_count() == 0:
		_text(right, "None yet. Refine resources at the Smith or Chemist.", DIM)
	_title(right, "Gear not worn", 20)
	var gg = _grid(right)
	for it in Crafting.items.filter(func(it): return it.slot != "potion" and not Crafting.is_equipped(it.id)):
		var t = TILE.for_item(it, 52)
		t.wire_gear(_rebuild.call_deferred)
		gg.add_child(t)
	if gg.get_child_count() == 0:
		_text(right, "None.", DIM)
	var close = Button.new()
	close.text = "Close (I or Esc)"
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(toggle)
	right.add_child(close)


## Refined materials take the color of what they came from.
func _mat_color(mat: String) -> Color:
	for raw in Crafting.REFINE:
		if Crafting.REFINE[raw].to == mat:
			return GameState.RESOURCE_INFO[raw].color
	return SOFT


func _grid(box) -> GridContainer:
	var g = GridContainer.new()
	g.columns = 7
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	box.add_child(g)
	return g


func _meter(row, value: float, max_v: float, color: Color) -> ProgressBar:
	var b = ProgressBar.new()
	b.max_value = max_v
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(200, 14)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	row.add_child(b)
	return b


func _small(t: String, color: Color) -> Label:
	var l = Label.new()
	l.text = "  " + t
	l.add_theme_color_override("font_color", color)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


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
