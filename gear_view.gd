extends RefCounted
## Shared "what you're wearing" list, used by the Smith's window and the character screen.
## Shows every gear slot your RACE has (from the skin), what's in it, and gear you're not wearing.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.6, 0.6, 0.6)


## box: where to add rows. can_change: show Equip/Remove buttons. on_change: called after a change.
static func build(box: VBoxContainer, can_change: bool, on_change: Callable):
	var race = SkinManager.race()
	_label(box, "%s gear slots" % race.name, GOLD, 20)
	_label(box, race.get("about", ""), DIM, 14)
	for rs in SkinManager.race_slots():
		var ids = Crafting.equipped.get(rs.slot, [])
		var filled = ids.filter(func(x): return x != -1).size()
		var header = rs.label if rs.count == 1 else "%s (%d of %d)" % [rs.label, filled, rs.count]
		if filled == 0:
			_label(box, header + ": empty", DIM, 16)
			continue
		_label(box, header + ":", SOFT, 16)
		for id in ids:
			if id == -1:
				continue
			var it = Crafting.item_by_id(id)
			_item_row(box, it, "Remove" if can_change else "", func(): Crafting.unequip(it.id); on_change.call())

	var spare = Crafting.items.filter(func(it): return it.slot != "potion" and not Crafting.is_equipped(it.id))
	_label(box, "Not worn", GOLD, 20)
	if spare.is_empty():
		_label(box, "Nothing else yet.", DIM, 16)
	elif not can_change:
		_label(box, "You can change gear in town.", DIM, 16)
	for it in spare:
		var fits = Crafting.slot_for(it) != null
		var btn = ""
		if can_change and fits:
			btn = "Equip"
		_item_row(box, it, btn, func(): Crafting.equip(it.id); on_change.call())


static func _item_row(box: VBoxContainer, it: Dictionary, button_text: String, action: Callable):
	var row = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "  %s  [%s]\n%s" % [Story.display_name(it), SkinManager.slot_label(it.slot), Crafting.describe(it)]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", SOFT)
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)
	if button_text != "":
		var b = Button.new()
		b.text = button_text
		b.pressed.connect(action)
		row.add_child(b)
	box.add_child(row)


static func _label(box: VBoxContainer, t: String, c: Color, size: int):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", c)
	l.add_theme_font_size_override("font_size", size)
	box.add_child(l)
