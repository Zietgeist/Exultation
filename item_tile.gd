extends Button
## One square tile: an icon, a colored border (quality), a count, and a tooltip.
## Used by the inventory, the character window's paper doll and anywhere else items are shown.
##   var t = ItemTile.make("ingot", color, quality, count, tooltip, size)

const ICONS = preload("res://icons.gd")

var kind := "ring"
var icon_color := Color.WHITE
var border := Color(0.4, 0.4, 0.45)
var count := 0			# shown bottom-right when > 1
var empty := false		# an empty slot: faint outline icon
var caption := ""		# small text under the icon (slot name), optional
var lit := false		# highlighted (selected / can act)
var item := {}			# the crafted item shown (gives the rich hover summary)
var hint := ""			# a last line in the hover summary ("Right-click: wear")

signal right_clicked	# right mouse button on this tile


static func make(kind_: String, color: Color, quality: int, count_: int, tip: String, side := 56.0):
	var t = load("res://item_tile.gd").new()
	t.kind = kind_
	t.icon_color = color
	t.border = ICONS.quality_color(quality) if quality >= 0 else Color(0.4, 0.4, 0.45)
	t.count = count_
	t.tooltip_text = tip
	t.custom_minimum_size = Vector2(side, side)
	return t


## A tile for a crafted item.
static func for_item(it: Dictionary, side := 56.0):
	var tip = "%s\n%s" % [Story.display_name(it), Crafting.describe(it)]
	var t = make(ICONS.kind_of(it), ICONS.item_color(it), int(it.get("quality", 0)), 0, tip, side)
	t.item = it
	return t


## A tile for an empty gear slot.
static func for_empty(accepts: String, label: String, side := 56.0):
	var t = make(ICONS.slot_kind(accepts), Color(1, 1, 1, 0.18), -1, 0, label + ": empty", side)
	t.empty = true
	return t


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()
		accept_event()


## The hover summary for gear: name, what it does, how it compares to what you wear, its story.
func _make_custom_tooltip(_for_text):
	if item.is_empty():
		return null
	var panel = PanelContainer.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.06, 0.08, 0.97)
	st.border_color = border
	st.set_border_width_all(2)
	st.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", st)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	_line(v, Story.display_name(item), border.lightened(0.2), 17)
	var worn = Crafting.is_equipped(item.get("id", -1))
	_line(v, "%s  ·  quality %d%s" % [SkinManager.slot_label(item.slot), int(item.get("quality", 0)) + 1, "  ·  wearing" if worn else ""], Color(0.65, 0.65, 0.7), 12)
	for l in Crafting.describe(item).split("\n"):
		_line(v, l, Color(0.9, 0.9, 0.9), 14)
	if not worn:
		var diffs = compare_lines(item)
		if diffs.size() > 0:
			_line(v, "Compared to what you wear:", Color(1.0, 0.85, 0.3), 12)
			for d in diffs:
				_line(v, "  " + d[0], Color(0.5, 1.0, 0.5) if d[1] > 0 else Color(1.0, 0.5, 0.45), 13)
	if item.get("bound_to", "") != "":
		_line(v, "Bound to %s" % item.bound_to, Color(0.6, 0.6, 0.6), 11)
	if hint != "":
		_line(v, hint, Color(0.6, 0.6, 0.6), 11)
	return panel


func _line(box: VBoxContainer, t: String, c: Color, size: int):
	var l = Label.new()
	l.text = t
	if t.length() > 48:	# long story lines wrap instead of running off the screen
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 360
	l.add_theme_color_override("font_color", c)
	l.add_theme_font_size_override("font_size", size)
	box.add_child(l)


## How an unworn item compares with what's worn in its slot: [[text, +1 better / -1 worse], ...]
static func compare_lines(it: Dictionary) -> Array:
	var rs = Crafting.slot_for(it)
	if rs == null:
		return [["Your race can't wear this", -1]]
	var ids = Crafting.equipped.get(rs.slot, [])
	var worn = null
	if ids.size() > 0 and ids[0] != -1:
		worn = Crafting.item_by_id(ids[0])
	var a = Crafting.effects(it)
	var b = Crafting.effects(worn) if worn != null else {}
	var out = []
	var keys = {"st": "Hit", "aoe": "Sweep", "reach": "Reach", "targets": "Sweep targets", "move": "Move speed", "max_health": "Max health", "lifesteal": "Heals per hit"}
	for k in keys:
		if not a.has(k):
			continue
		var d = float(a[k]) - float(b.get(k, 0.0))
		if k == "move":
			d *= 100.0
		if abs(d) >= 0.05:
			out.append(["%s %+.0f%s" % [keys[k], d, "%" if k == "move" else ""], 1 if d > 0 else -1])
	if a.has("resist"):
		for el in Crafting.ELEMENTS:
			var d = (a.resist.get(el, 0.0) - b.get("resist", {}).get(el, 0.0)) * 100.0
			if abs(d) >= 0.5:
				out.append(["%s resist %+.0f%%" % [SkinManager.element_label(el), d], 1 if d > 0 else -1])
	if a.has("st_cd"):
		var d = float(a.st_cd) - float(b.get("st_cd", a.st_cd))
		if abs(d) >= 0.05:
			out.append(["Hit time %+.1fs" % d, 1 if d < 0 else -1])
	if worn == null and rs.count == 1:
		out.append(["(that slot is empty)", 1])
	return out


## Right-click on gear anywhere: wear it, or take it off if you're wearing it (in town).
static func wear_or_remove(it: Dictionary) -> bool:
	if it.get("slot", "") == "potion":
		return false
	if Zones.local_path() != "res://Home.tscn":
		GameState.notify("You can change gear in town.")
		return false
	if Crafting.is_equipped(it.id):
		Crafting.unequip(it.id)
		GameState.notify("Took off " + Story.display_name(it))
	elif Crafting.slot_for(it) == null:
		GameState.notify("Your race can't wear that.")
		return false
	else:
		Crafting.equip(it.id)
		GameState.notify("Wearing " + Story.display_name(it))
	return true


## Hook a gear tile up: right-click wears / takes off, and the summary says so.
func wire_gear(after: Callable):
	if item.is_empty() or item.get("slot", "") == "potion":
		return
	hint = "Right-click: %s (in town)" % ("take off" if Crafting.is_equipped(item.id) else "wear")
	right_clicked.connect(func(): if wear_or_remove(item): after.call())


func _ready():
	focus_mode = Control.FOCUS_NONE
	flat = true
	text = ""


func _draw():
	var r = Rect2(Vector2.ZERO, size)
	var bg = Color(0.12, 0.12, 0.15, 0.95) if not empty else Color(0.08, 0.08, 0.1, 0.7)
	if is_hovered():
		bg = bg.lightened(0.12)
	draw_rect(r, bg)
	draw_rect(r.grow(-1), border if not empty else Color(0.35, 0.35, 0.4, 0.6), false, 3.0 if lit else 2.0)
	var pad = size.x * 0.12
	var icon_r = Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	if caption != "":
		icon_r.size.y -= 12
	ICONS.draw(self, kind, icon_r, icon_color)
	var font = get_theme_default_font()
	if count > 1:
		var txt = str(count)
		var fs = 13
		var w = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(size.x - w - 4, size.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
		draw_string(font, Vector2(size.x - w - 4, size.y - 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if caption != "":
		draw_string(font, Vector2(0, size.y - 4), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(0.75, 0.75, 0.75))


func _process(_delta):
	queue_redraw()	# hover highlight
	set_process(false)


func _notification(what):
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()
