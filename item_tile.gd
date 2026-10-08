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
	return make(ICONS.kind_of(it), ICONS.item_color(it), int(it.get("quality", 0)), 0, tip, side)


## A tile for an empty gear slot.
static func for_empty(accepts: String, label: String, side := 56.0):
	var t = make(ICONS.slot_kind(accepts), Color(1, 1, 1, 0.18), -1, 0, label + ": empty", side)
	t.empty = true
	return t


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
