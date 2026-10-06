extends CanvasLayer
## The shop window for the Smith, the Chemist and the Inn.
## Opens when you talk to a shopkeeper (G). Esc or walking away closes it.

const GREETINGS = {
	"smith": "Brann: \"Bring me ore, I'll give you metal. Bring me metal, I'll give you a weapon.\nPut anything in the open slots. Sunleaf in a vest? It'll drink the sun's fire.\"",
	"chemist": "Ilsa: \"Herbs in, tonics out. Tonics and essences can go in anything —\neven Brann's steel. My draughts take a slot too, if you're curious.\"",
	"inn": "Old Tamsin: \"Rest your feet. Bank your gold at the shrine out front, and the road will wait.\"",
}
const SHOP_TITLES = {"smith": "The Smithy", "chemist": "The Chemist", "inn": "The Inn"}
const GOLD = Color(1.0, 0.85, 0.3)
const GEAR_VIEW = preload("res://gear_view.gd")

var shop = ""
var npc = null
var panel: PanelContainer
var content: VBoxContainer

# Current choices in the "Make" section
var sel_base = ""
var sel_q = -1
var sel_slots = []	# per slot: index into stash list, or -1 for empty


func _ready():
	layer = 40
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(820, 600)
	panel.position = Vector2(-410, -300)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(790, 570)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	visible = false


func open(shop_id: String, who):
	shop = shop_id
	npc = who
	sel_base = ""
	sel_q = -1
	sel_slots = []
	visible = true
	GameState.ui_open = true
	_rebuild()


func close():
	visible = false
	GameState.ui_open = false


func _unhandled_input(event):
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(_delta):
	if not visible:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and npc and npc.horizontal_distance(player.global_position) > 7.0:
		close()	# walked away


# ---------------- Building the window ----------------

func _rebuild():
	for c in content.get_children():
		c.queue_free()
	_title(SHOP_TITLES[shop])
	_text(GREETINGS[shop], Color(0.85, 0.82, 0.75))
	match shop:
		"smith", "chemist":
			_refine_section()
			_make_section()
			_owned_section()
		"inn":
			_inn_section()
	var close_btn = Button.new()
	close_btn.text = "Close (Esc)"
	close_btn.pressed.connect(close)
	content.add_child(close_btn)


func _refine_section():
	_title("Refine", 20)
	var opts = Crafting.refine_options(shop)
	if opts.is_empty():
		_text("Nothing to refine. Gather resources out in the zones (G).", Color(0.7, 0.7, 0.7))
	for o in opts:
		var row = HBoxContainer.new()
		var lbl = Label.new()
		lbl.text = "%s x%d   →   %s   (%d each)" % [o.name, o.have, o.result, o.cost]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var one = Button.new()
		one.text = "Refine"
		one.disabled = o.have < o.cost
		one.pressed.connect(func(): Crafting.refine(o.raw, o.q); _rebuild.call_deferred())
		row.add_child(one)
		var all = Button.new()
		all.text = "All"
		all.disabled = o.have < o.cost
		all.pressed.connect(func():
			while Crafting.refine(o.raw, o.q): pass
			_rebuild.call_deferred())
		row.add_child(all)
		content.add_child(row)
	var stash = Crafting.stash_list()
	var parts = []
	for s in stash:
		parts.append("%s x%d" % [s.name, s.count])
	_text("Materials: " + (", ".join(parts) if parts.size() > 0 else "none yet"), Color(0.75, 0.85, 1.0))


func _make_section():
	_title("Make", 20)
	var bases = []
	for id in Crafting.BASES:
		if Crafting.BASES[id].shop == shop:
			bases.append(id)
	if sel_base == "" or not bases.has(sel_base):
		sel_base = bases[0]
	var base = Crafting.BASES[sel_base]

	# Base recipe picker
	var row = HBoxContainer.new()
	row.add_child(_label("Recipe:"))
	var base_pick = OptionButton.new()
	for i in range(bases.size()):
		var b = Crafting.BASES[bases[i]]
		var needs = []
		for m in b.need:
			needs.append("%d %s" % [b.need[m], Crafting.MATERIAL_LABELS[m]])
		base_pick.add_item("%s  (%s, %d open slot%s) - %s" % [b.label, ", ".join(needs), b.slots, "" if b.slots == 1 else "s", b.about])
		if bases[i] == sel_base:
			base_pick.select(i)
	base_pick.item_selected.connect(func(i): sel_base = bases[i]; sel_q = -1; sel_slots = []; _rebuild.call_deferred())
	row.add_child(base_pick)
	content.add_child(row)

	# Quality of the main material
	var qs = Crafting.base_qualities(sel_base)
	if qs.is_empty():
		var needs = []
		for m in base.need:
			needs.append("%d %s" % [base.need[m], Crafting.MATERIAL_LABELS[m]])
		_text("You need %s of one quality to make this." % ", ".join(needs), Color(1, 0.6, 0.5))
		return
	if not qs.has(sel_q):
		sel_q = qs[qs.size() - 1]
	var qrow = HBoxContainer.new()
	qrow.add_child(_label("Made from:"))
	var q_pick = OptionButton.new()
	for i in range(qs.size()):
		q_pick.add_item(Crafting.material_name(base.need.keys()[0], qs[i]))
		if qs[i] == sel_q:
			q_pick.select(i)
	q_pick.item_selected.connect(func(i): sel_q = qs[i]; _rebuild.call_deferred())
	qrow.add_child(q_pick)
	content.add_child(qrow)

	# Creative slots: any refined material
	var stash = Crafting.stash_list()
	while sel_slots.size() < base.slots:
		sel_slots.append(-1)
	var chosen = []
	for s in range(base.slots):
		var srow = HBoxContainer.new()
		srow.add_child(_label("Open slot %d:" % (s + 1)))
		var pick = OptionButton.new()
		pick.add_item("(empty)")
		for i in range(stash.size()):
			var attrs = Crafting.material_attributes(stash[i].mat, stash[i].q)
			var bits = []
			for k in attrs:
				bits.append("%s %.0f" % [k, attrs[k]])
			pick.add_item("%s x%d   [%s]" % [stash[i].name, stash[i].count, ", ".join(bits)])
		pick.select(sel_slots[s] + 1 if sel_slots[s] < stash.size() else 0)
		var slot_index = s
		pick.item_selected.connect(func(i): sel_slots[slot_index] = i - 1; _rebuild.call_deferred())
		srow.add_child(pick)
		content.add_child(srow)
		if sel_slots[s] >= 0 and sel_slots[s] < stash.size():
			chosen.append({mat = stash[sel_slots[s]].mat, q = stash[sel_slots[s]].q})

	# Preview
	var preview = Crafting.design(sel_base, sel_q, chosen)
	preview.made_from = preview.made_from	# (no date yet)
	_text("Preview: " + preview.name, GOLD)
	_text(Crafting.describe(preview), Color(0.9, 0.9, 0.9))
	var make = Button.new()
	make.text = "Make it"
	make.disabled = not Crafting.can_make_base(sel_base, sel_q, chosen)
	if make.disabled:
		_text("Not enough materials for this combination.", Color(1, 0.6, 0.5))
	make.pressed.connect(func():
		var item = Crafting.craft(sel_base, sel_q, chosen)
		if item:
			GameState.notify("Made: " + item.name)
		sel_slots = []
		_rebuild.call_deferred())
	content.add_child(make)


func _owned_section():
	if shop == "smith":
		GEAR_VIEW.build(content, true, func(): _rebuild.call_deferred())
		return
	_title("Your potions (press 1 to drink)", 20)
	var pots = Crafting.potions()
	if pots.is_empty():
		_text("Nothing yet.", Color(0.7, 0.7, 0.7))
	for it in pots:
		_text(it.name + "\n" + Crafting.describe(it), Color(0.9, 0.9, 0.9))


func _inn_section():
	_title("Your rest", 20)
	var rest = "Rested and ready." if not SessionManager.is_resting() else "Resting: %d:%02d left" % [int(SessionManager.rest_left) / 60, int(SessionManager.rest_left) % 60]
	_text("Banked gold: %d\nCarrying: %d / %d gold\n%s" % [GameState.gold_banked, GameState.gold_carried, GameState.GOLD_CAPACITY, rest], GOLD)
	var heal = Button.new()
	heal.text = "Have a meal (full health)"
	heal.pressed.connect(func():
		var p = get_tree().get_first_node_in_group("player")
		if p:
			p.health = p.MAX_HEALTH
		GameState.notify("Old Tamsin's stew. Fully healed.")
		_rebuild.call_deferred())
	content.add_child(heal)
	_title("What you're carrying", 20)
	_text(GameState.satchel_text(), Color(0.75, 0.85, 1.0))
	var parts = []
	for s in Crafting.stash_list():
		parts.append("%s x%d" % [s.name, s.count])
	_text("Materials: " + (", ".join(parts) if parts.size() > 0 else "none"), Color(0.75, 0.85, 1.0))
	var w = Crafting.equipped_weapon()
	var worn = Crafting.equipped_items().filter(func(it): return it.slot != "weapon")
	_text("Weapon: %s\nArmor pieces worn: %d\nPotions: %d\n(Press C for the full character screen.)" % [w.name if w else "Fists", worn.size(), Crafting.potions().size()], Color(0.9, 0.9, 0.9))
	_title("Tips", 20)
	_text("• Step on the shrine outside to bank gold and start your 5-minute rest.\n• Press M for the map.\n• Ore grows around hills, herbs around trees. Look for Treesilver in ancient trees and orchids on hills.", Color(0.8, 0.8, 0.8))


# ---------------- small helpers ----------------

func _title(t: String, size := 26):
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	content.add_child(l)


func _text(t: String, color: Color):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	content.add_child(l)


func _label(t: String) -> Label:
	var l = Label.new()
	l.text = t
	l.custom_minimum_size.x = 110
	return l
