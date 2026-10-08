extends Control
## The paper doll in the character window: your race's body, with a tile for every gear slot
## it has, joined to the spot on the body where it's worn. Bodies come from body_plans.gd and the
## race's "body" block in the skin JSON, so races with other limbs (4 arms, a tail, wings, roots)
## just need data.
##   Click a slot: wear something that fits / take it off (in town). Hover: what it is.

const PLANS = preload("res://body_plans.gd")
const TILE = preload("res://item_tile.gd")
const BIG = 58.0
const COL = 64.0		# width of each side column

var can_change := false
var on_change := Callable()
var _plan := {}
var _links := []		# [tile, body point (px)] for the connector lines
var _menu: PopupMenu
var _menu_actions := []


func setup(change_ok: bool, changed: Callable, doll_size := Vector2(420, 420)):
	can_change = change_ok
	on_change = changed
	custom_minimum_size = doll_size
	size = doll_size


func _ready():
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(func(i): _menu_actions[i].call())
	add_child(_menu)
	_build()


## Body space (0..1 square) to pixels: centered between the side columns.
func _px(v: Vector2) -> Vector2:
	var h = size.y - 20.0
	return Vector2(size.x / 2.0 + (v.x - 0.5) * h, 10.0 + v.y * h)


func _build():
	for c in get_children():
		if c != _menu:
			c.queue_free()
	_links.clear()
	var race = SkinManager.race()
	_plan = PLANS.plan_for(race)
	var cols = {L = [], R = []}
	var leftovers = []
	for rs in SkinManager.race_slots():
		var a = _plan.anchors.get(rs.slot, _plan.anchors.get(rs.accepts, null))
		var ids = Crafting.equipped.get(rs.slot, [])
		var small = a != null and (a.get("small", false) or rs.count > 3)
		var pts = []
		if a != null:
			pts = PLANS.spread(a.path, rs.count) if a.has("path") else a.pts
		for i in rs.count:
			var id = ids[i] if i < ids.size() else -1
			var tile = _tile(rs, i, id, small)
			if a == null or pts.is_empty():
				leftovers.append(tile)
				continue
			var at = _px(pts[min(i, pts.size() - 1)])
			if small:
				var side = clamp(_spacing_px(pts) * 0.9, 18.0, 30.0)
				tile.custom_minimum_size = Vector2(side, side)
				tile.size = tile.custom_minimum_size
				tile.position = at - tile.size / 2.0
				add_child(tile)
			else:
				cols[a.side].append([tile, at])
	for side in ["L", "R"]:
		_column(cols[side], side)
	# Slots this body has no spot for (new kinds of gear): a row along the bottom
	var x = 0.0
	for t in leftovers:
		t.position = Vector2(x, size.y - BIG)
		add_child(t)
		x += BIG + 6.0
	queue_redraw()


func _spacing_px(pts: Array) -> float:
	if pts.size() < 2:
		return 30.0
	return _px(pts[0]).distance_to(_px(pts[1]))


## Big tiles down one side, in body order (head to feet), never overlapping.
func _column(list: Array, side: String):
	list.sort_custom(func(a, b): return a[1].y < b[1].y)
	var y_next = 0.0
	for e in list:
		var t = e[0]
		var y = max(e[1].y - BIG / 2.0, y_next)
		y = min(y, size.y - BIG)
		t.position = Vector2(0.0 if side == "L" else size.x - BIG, y)
		add_child(t)
		_links.append([t, e[1], side])
		y_next = y + BIG + 6.0


func _tile(rs: Dictionary, index: int, id: int, small: bool):
	var t
	if id != -1 and Crafting.item_by_id(id) != null:
		var it = Crafting.item_by_id(id)
		t = TILE.for_item(it, BIG)
		t.tooltip_text = "%s\n%s\n\n%s" % [rs.label, t.tooltip_text, "Click to change" if can_change else "Change gear in town"]
	else:
		t = TILE.for_empty(rs.accepts, rs.label, BIG)
		t.tooltip_text += "\n" + ("Click to wear something" if can_change else "Change gear in town")
	if not small:
		t.caption = rs.label
	t.pressed.connect(func(): _clicked(rs, index, id))
	return t


func _clicked(rs: Dictionary, index: int, id: int):
	if not can_change:
		GameState.notify("You can change gear in town.")
		return
	_menu.clear()
	_menu_actions.clear()
	if id != -1:
		_menu.add_item("Take off")
		_menu_actions.append(func(): Crafting.unequip(id); _changed())
	for it in Crafting.items:
		if it.slot == rs.accepts and not Crafting.is_equipped(it.id):
			_menu.add_item("Wear: " + Story.display_name(it))
			var item_id = it.id
			_menu_actions.append(func(): Crafting.equip(item_id, rs.slot, index); _changed())
	if _menu_actions.is_empty():
		GameState.notify("Nothing to wear there yet. The Smith makes gear.")
		return
	_menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _changed():
	if on_change.is_valid():
		on_change.call()
	_build.call_deferred()


func _draw():
	if _plan.is_empty():
		return
	var col = PLANS.body_color(SkinManager.race())
	var outline = col.lightened(0.25)
	var h = size.y - 20.0
	# Soft floor shadow under the lowest point of the body (a flat oval)
	var low = 0.0
	for part in _plan.parts:
		for k in ["a", "b", "c"]:
			if part.has(k):
				low = max(low, part[k].y)
	draw_set_transform(_px(Vector2(0.5, low + 0.01)), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, h * 0.16, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for part in _plan.parts:
		match part.t:
			"limb":
				draw_line(_px(part.a), _px(part.b), outline, part.w * h + 3.0)
				draw_line(_px(part.a), _px(part.b), col, part.w * h)
				draw_circle(_px(part.a), part.w * h / 2.0, col)
				draw_circle(_px(part.b), part.w * h / 2.0, col)
			"circle":
				draw_circle(_px(part.c), part.r * h + 1.5, outline)
				draw_circle(_px(part.c), part.r * h, col)
			"poly":
				var pts = PackedVector2Array(part.pts.map(func(v): return _px(v)))
				draw_colored_polygon(pts, col.lightened(part.get("shade", 0.0)) if part.get("shade", 0.0) >= 0.0 else col.darkened(-part.shade))
				pts.append(pts[0])
				draw_polyline(pts, outline, 1.5)
			"joint":
				var r = part.r * h
				draw_rect(Rect2(_px(part.c) - Vector2(r, r), Vector2(r, r) * 2.0), Color(0.4, 0.9, 1.0) if part.get("glow", false) else Color(0.6, 0.62, 0.68))
			"glow":
				draw_circle(_px(part.c), part.r * h, Color(0.4, 0.8, 1.0, 0.5))
			"leaf":
				draw_circle(_px(part.c), part.r * h, Color(0.25, 0.5, 0.25, 0.85))
			"eyes":
				for sd in [-1, 1]:
					draw_circle(_px(part.c + Vector2(sd * 0.03, 0)), part.r * h, Color(1.0, 0.85, 0.3))
	# Lines from each tile to where it's worn
	for l in _links:
		var t = l[0]
		var from = t.position + Vector2(BIG if l[2] == "L" else 0.0, BIG / 2.0)
		draw_line(from, l[1], Color(1.0, 0.85, 0.3, 0.45), 1.5)
		draw_circle(l[1], 3.5, Color(1.0, 0.85, 0.3, 0.8))
