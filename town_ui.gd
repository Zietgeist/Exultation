extends CanvasLayer
## Window for a neutral town's Trader and Quest Board (lm_town.gd). G next to them opens it.
## The game keeps running (multiplayer-friendly). Esc closes.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.6, 0.6, 0.6)
const GOODS = ["ingot", "silverbar", "tonic", "essence", "gem"]

var panel: PanelContainer
var box: VBoxContainer
var _kind := ""
var _town = null


func _ready():
	layer = 46
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 540)
	panel.position = Vector2(-310, -270)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.96)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(588, 508)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	panel.visible = false


func _unhandled_input(event):
	if panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## npc.gd calls this: kind "trader" or "board".
func open(kind: String, _who):
	_kind = kind
	_town = get_parent()
	panel.visible = true
	GameState.ui_open = true
	_rebuild()


func close():
	panel.visible = false
	GameState.ui_open = false


func _rebuild():
	for c in box.get_children():
		c.queue_free()
	if _kind == "trader":
		_trader()
	else:
		_board()
	_button("Close (Esc)", close)


# ---------------- Trader ----------------

func _price(mat: String, q: int) -> int:
	return (30 if mat == "gem" else 12) * max(1, q)


func _trader():
	var q = GameState.zone_quality(_town.zone_path)
	_title("%s - %s" % [Landmarks.word("trader"), _town.info.name])
	_text("Banked gold: %d. Materials go straight to your stash at Home." % GameState.gold_banked, GOLD)
	for m in GOODS:
		var price = _price(m, q)
		var b = _button("Buy 1 %s - %d gold" % [Crafting.material_name(m, q), price], func():
			if GameState.spend_gold(price):
				Crafting.add_material(m, q, 1)
				GameState.notify("Bought " + Crafting.material_name(m, q))
			else:
				GameState.notify("Not enough banked gold.")
			_rebuild())
		b.disabled = GameState.gold_banked < price


# ---------------- Quest board ----------------

func _board():
	_title("%s - %s" % [Landmarks.word("board"), _town.info.name])
	_text("Jobs pay banked gold. You can carry up to 5. Hunts count anywhere in that zone.", DIM)
	for o in Landmarks.offers(_town.zone_path, _town.info.id):
		var taken = Landmarks.has_quest(o.key)
		var b = _button("%s  (%d gold)%s" % [o.text, o.gold, "  - taken" if taken else ""], func():
			Landmarks.accept(o)
			_rebuild())
		b.disabled = taken
	_title("Your jobs", 20)
	if Landmarks.quests().is_empty():
		_text("None yet.", DIM)
	for q in Landmarks.quests():
		var line = "%s  -  %d / %d" % [q.text, q.have, q.need] if q.kind != "gather" else "%s  (in your satchel: %d)" % [q.text, GameState.satchel.get("%s:%d" % [q.res, q.q], 0)]
		_text(line, SOFT)
		if q.kind == "gather":
			_button("Hand over", func(): Landmarks.deliver(q); _rebuild())
		elif Landmarks.ready_to_collect(q):
			_button("Collect %d gold" % q.gold, func(): Landmarks.collect(q); _rebuild())


# ---------------- helpers ----------------

func _title(t: String, size := 24):
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	box.add_child(l)


func _text(t: String, c: Color):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_color_override("font_color", c)
	box.add_child(l)


func _button(t: String, f: Callable) -> Button:
	var b = Button.new()
	b.text = t
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(f)
	box.add_child(b)
	return b
