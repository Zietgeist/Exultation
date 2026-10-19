extends Control
## The map (press M).
## - At Home: first the town map (shops, gates, the rest shrine, fast travel). Press M again for the
##   whole spiral, showing what you've explored in each zone. Once more closes it.
## - In a zone: the ground you've explored (the rest stays dark), with you, gates, landmarks you've
##   found, fast-travel stops, shrines, where you fell (red X) and where bosses fell (gold ring).
##   Once you've cleared it (both bosses down), it also shows every enemy left.
## Zoom: left click zooms in on that spot, right click zooms out, mouse wheel too.
## Hover the mouse over anything on the map to see what it is.
## While the map is open, clicks go to the map (no attacks). You can still walk.

const LAYOUT = preload("res://world_layout.gd")	# fog square size per zone: LAYOUT.fog_cell(path)
const BG = Color(0.03, 0.03, 0.05, 0.85)
const UNEXPLORED = Color(0.12, 0.12, 0.16)
const EXPLORED = Color(0.45, 0.45, 0.5)
const LOCKED = Color(0.07, 0.07, 0.09)
const GOLD = Color(1.0, 0.85, 0.3)
const TIER_COLORS = [Color(0.2, 0.9, 0.2), Color(0.3, 0.5, 1.0), Color(0.7, 0.2, 1.0), Color(1.0, 0.8, 0.0)]

var _redraw_timer = 0.0
var _home_world := false	# at Home: false = town map, true = the whole spiral
var _zoom := 1.0			# 1 = whole map fits; up to MAX_ZOOM
var _focus := Vector2.ZERO	# how far the view is moved from the middle (in unzoomed screen pixels)
var _took_ui := false		# we set GameState.ui_open, so we clear it on close
var _mouse := Vector2(-1000, -1000)	# where the mouse is (for hover labels)
var _hot := []				# things drawn this frame you can hover: [{p, r, text}]
const MAX_ZOOM = 16.0


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)	# fill the whole screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		if Zones.local_path() == "res://Home.tscn":	# town map -> spiral -> closed
			if not visible:
				_set_open(true)
				_home_world = false
			elif not _home_world:
				_home_world = true
				_reset_zoom()
			else:
				_set_open(false)
		else:
			_set_open(not visible)
		queue_redraw()


func _set_open(open: bool):
	visible = open
	_reset_zoom()
	mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open and not GameState.ui_open:
		GameState.ui_open = true	# so clicks zoom the map instead of attacking
		_took_ui = true
	elif not open and _took_ui:
		GameState.ui_open = false
		_took_ui = false


func _reset_zoom():
	_zoom = 1.0
	_focus = Vector2.ZERO


## Left click: zoom in on that spot. Right click: zoom out. Wheel: in / out.
func _gui_input(event):
	if event is InputEventMouseMotion:
		_mouse = event.position
		queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 2.0 if event.button_index == MOUSE_BUTTON_LEFT else 1.25)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 0.5 if event.button_index == MOUSE_BUTTON_RIGHT else 0.8)
		_:
			return
	accept_event()
	queue_redraw()


func _zoom_at(click: Vector2, factor: float):
	var new_zoom = clamp(_zoom * factor, 1.0, MAX_ZOOM)
	if new_zoom <= 1.0:
		_reset_zoom()
		return
	# The spot under the mouse (in unzoomed pixels). Clicks center it; the wheel keeps it under the mouse.
	var u = (click - size / 2.0) / _zoom + size / 2.0 + _focus
	if factor >= 2.0 or factor <= 0.5:
		_focus = u - size / 2.0
	else:
		_focus = u - size / 2.0 - (click - size / 2.0) / new_zoom
	_zoom = new_zoom


func _process(delta):
	if not visible:
		return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 0.2
		queue_redraw()


func _draw():
	_hot.clear()
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var path = Zones.local_path()
	if path == "":
		return
	var font = get_theme_default_font()
	if path == "res://Home.tscn" and _home_world:
		_draw_world(font)
	elif path == "res://Home.tscn":
		_draw_town(font)
		_hint(font, "M: the whole spiral")
		_draw_tooltip(font)
		return
	elif path.begins_with("res://Zone"):
		_draw_zone(path, font, GameState.is_zone_cleared(path))
	elif path == "res://RealZone.tscn":	# a Real Place draws its own streets (real_zone.gd draw_map)
		var rz = Zones.local_zone().root if Zones.local_zone() else null
		if rz and rz.has_method("draw_map"):
			var h = rz.REAL_MAP.HALF_SIZE
			var fit = _fit(Rect2(-h, -h, h * 2.0, h * 2.0), 0.85)
			rz.draw_map(self, fit.offset, fit.scale, Rect2(Vector2.ZERO, size))
			var left = "%d enemies left, %d boss%s" % [rz.alive, rz.bosses_left, "" if rz.bosses_left == 1 else "es"]
			draw_string(font, Vector2(0, 50), "Real Place  -  " + ("cleared!" if rz.cleared else left), HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD)
			draw_string(font, Vector2(12, size.y - 12), "Map data (c) OpenStreetMap contributors", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
	else:
		var msg = "No map here."
		draw_multiline_string(font, Vector2(0, size.y / 2.0 - 40), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, -1, GOLD)
	_hint(font, "M to close")
	_draw_tooltip(font)


func _hint(font, text: String):
	var z = "Hover: what is it?  -  Click: zoom in  -  Right-click: zoom out" if _zoom <= 1.0 else "Zoom x%d  -  Right-click: zoom out" % int(round(_zoom))
	draw_rect(Rect2(0, size.y - 52, size.x, 52), BG)	# keep the hint readable over a zoomed map
	draw_string(font, Vector2(0, size.y - 30), text + "  -  " + z, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.8, 0.8, 0.8))


# ---------- World map (Home) ----------
func _draw_world(font):
	var bounds = Rect2()
	var first = true
	for p in GameState.ZONE_LAYOUT:
		var r = GameState.ZONE_LAYOUT[p]
		bounds = r if first else bounds.merge(r)
		first = false
	var fit = _fit(bounds, 0.8)
	draw_string(font, Vector2(0, 50), "THE SPIRAL", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD)
	for p in GameState.ZONE_LAYOUT:
		var r = GameState.ZONE_LAYOUT[p]
		var screen = Rect2(fit.offset + r.position * fit.scale, r.size * fit.scale)
		var zone_label = GameState.ZONE_NAMES.get(p, p)
		var status = ""
		if p == "res://Home.tscn":
			draw_rect(screen, EXPLORED)
			var player = get_tree().get_first_node_in_group("player")
			if player:
				var pp = r.position + r.size / 2.0 + Vector2(player.global_position.x, player.global_position.z)
				draw_circle(fit.offset + pp * fit.scale, 5, Color.WHITE)
				_tip(fit.offset + pp * fit.scale, "You")
		elif not GameState.is_unlocked(p):
			draw_rect(screen, LOCKED)
			status = "locked"
		else:
			var fog = GameState.zone_memory.get(p, {}).get("fog", null)
			_draw_fog_cells(screen, r.size / 2.0, fog, LAYOUT.fog_cell(p))
			if GameState.is_zone_cleared(p):
				status = "cleared"
			elif fog == null:
				status = "not explored yet"
		draw_rect(screen, GOLD if GameState.is_zone_cleared(p) else Color(0.5, 0.5, 0.55), false, 2.0)
		var about = "Your town: shops, rest and bank"
		if p != "res://Home.tscn":
			match status:
				"locked": about = "Locked. " + GameState.unlock_hint(p)
				"cleared": about = "Cleared: both bosses defeated"
				"not explored yet": about = "Open, but you haven't been inside yet"
				_: about = "Open. Defeat %d bosses here to clear it" % GameState.BOSSES_TO_UNLOCK
		_tip_rect(screen, zone_label + "\n" + about)
		# Name and status, centered near the top of each zone
		draw_string(font, screen.position + Vector2(0, 20), zone_label, HORIZONTAL_ALIGNMENT_CENTER, screen.size.x, 15, Color.WHITE)
		if status != "":
			draw_string(font, screen.position + Vector2(0, 36), status, HORIZONTAL_ALIGNMENT_CENTER, screen.size.x, 12, GOLD if status == "cleared" else Color(0.7, 0.7, 0.75))


# ---------- Town map (Home) ----------
func _draw_town(font):
	var half = Vector2(50, 50)
	var floor_node = Zones.local_first("map_floor")
	if floor_node:
		half = floor_node.get_half_size()
	var local_rect = Rect2(-half, half * 2.0)
	var fit = _fit(local_rect, 0.8)
	var screen = Rect2(fit.offset + local_rect.position * fit.scale, local_rect.size * fit.scale)
	draw_rect(screen, Color(0.3, 0.3, 0.32))
	draw_rect(screen, GOLD, false, 2.0)
	draw_string(font, Vector2(0, 50), "HOME", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD)
	# Shops
	for b in load("res://town.gd").BUILDINGS:
		var c = _to_screen(fit, b.pos)
		var r = Rect2(c - Vector2(b.size.x, b.size.z) * fit.scale / 2.0, Vector2(b.size.x, b.size.z) * fit.scale)
		draw_rect(r, Color(0.55, 0.38, 0.25))
		_tip_rect(r, b.sign + "\nShop. Walk up to the shopkeeper and talk")
		draw_string(font, Vector2(c.x - 60, r.position.y + r.size.y / 2.0 + 6), b.sign, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color.WHITE)
	# Rest shrine (Pomodoro gate: bank gold, rest)
	var gate_node = Zones.local_root().get_node_or_null("PomodoroGate") if Zones.local_root() else null
	if gate_node:
		_map_mark(fit, gate_node.global_position, Color(1.0, 0.8, 0.2), "Deposit / rest", font, "Bank your gold and resources, and take a break")
	# Fast travel, Hall of Legends
	for w in Zones.local_all("waystation"):
		_map_mark(fit, w.global_position, Color(0.5, 0.9, 1.0), Travel.station_name(), font, "Fast travel to stops you've found")
	_map_mark(fit, preload("res://spiral_floor.gd").HALL_SPOT, Color(0.85, 0.72, 0.35), "Hall of Legends", font, "Your story and achievements")
	# Gates to the zones
	for door in Zones.local_all("door"):
		var c = _to_screen(fit, door.global_position)
		var open = GameState.is_unlocked(door.target_scene)
		draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color(0, 1, 1) if open else Color(0.9, 0.1, 0.1))
		_tip(c, _gate_tip(door.target_scene), 12.0)
		var text = GameState.ZONE_NAMES.get(door.target_scene, "?") + ("" if open else " (locked)")
		var dir = (fit.offset + local_rect.get_center() * fit.scale - c).normalized()
		var inward = dir * (34.0 + 50.0 * abs(dir.x))	# side gates need more room for the label
		draw_string(font, c + inward - Vector2(60, -5), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color.WHITE)
	# Shopkeepers and you
	for n in Zones.local_all("npc"):
		if n.has_method("talk") and not n.is_in_group("shrine"):
			draw_circle(_to_screen(fit, n.global_position), 4, Color(0.9, 0.75, 0.5))
			_tip(_to_screen(fit, n.global_position), "%s\n%s" % [n.npc_name, n.role], 8.0)
	var player = get_tree().get_first_node_in_group("player")
	if player:
		draw_circle(_to_screen(fit, player.global_position), 6, Color.WHITE)
		draw_string(font, _to_screen(fit, player.global_position) + Vector2(-20, -10), "You", HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Color.WHITE)
		_tip(_to_screen(fit, player.global_position), "You")


func _map_mark(fit: Dictionary, pos: Vector3, c: Color, text: String, font, about := ""):
	var p = _to_screen(fit, pos)
	draw_circle(p, 7, c)
	_tip(p, text + ("\n" + about if about != "" else ""))
	draw_string(font, p + Vector2(-70, 22), text, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, c)


# ---------- Zone map (cleared zone) ----------
## A zone's map. Only ground you've explored is drawn (the rest stays dark), and only things on it:
## gates, landmarks you've found, fast-travel stops, shrines, where you fell.
## Cleared zones (both bosses down) also show every enemy left.
func _draw_zone(path: String, font, cleared := true):
	var floor_node = Zones.local_first("map_floor")
	if floor_node == null:
		return
	var half = floor_node.get_half_size()
	var local_rect = Rect2(-half, half * 2.0)
	var fit = _fit(local_rect, 0.8)
	var screen = Rect2(fit.offset + local_rect.position * fit.scale, local_rect.size * fit.scale)
	var fog = Zones.local_first("zone_fog")
	_draw_fog_cells(screen, half, fog.revealed if fog else null, fog.CELL if fog else 4.0)
	draw_rect(screen, GOLD, false, 2.0)
	var seen = func(pos: Vector3) -> bool: return cleared or fog == null or fog.is_revealed(pos)
	var title = GameState.ZONE_NAMES.get(path, path) + ("  - cleared" if cleared else "  - %d%% explored" % roundi(100.0 * (fog.explored_fraction() if fog else 0.0)))
	draw_string(font, Vector2(0, 50), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD)

	if cleared:	# enemies still left (awake and sleeping)
		var sp = Zones.local_first("zone_spawner")
		for e in Zones.local_all("enemy"):
			draw_circle(_to_screen(fit, e.global_position), 2.0, TIER_COLORS[e.tier])
			_tip(_to_screen(fit, e.global_position), SkinManager.name_of(e.TIER_IDS[e.tier] + "_one") + "\nEnemy still here", 6.0)
		if sp:
			for d in sp.dormant:
				draw_circle(_to_screen(fit, d.p), 2.0, TIER_COLORS[d.t])
				_tip(_to_screen(fit, d.p), SkinManager.name_of(preload("res://enemy.gd").TIER_IDS[d.t] + "_one") + "\nEnemy still here (asleep)", 6.0)
	# Bosses: shown once you've explored their spot or hurt them (a boss never hides from you)
	var bosses = []	# [position, health share, asleep]
	for e in Zones.local_all("enemy"):
		if e.tier == 3 and not e.is_queued_for_deletion() and e.rival.is_empty():
			bosses.append([e.global_position, float(e.health) / e.MAX_HEALTH, false, e.health < e.MAX_HEALTH])
	var bsp = Zones.local_first("zone_spawner")
	if bsp:
		for d in bsp.dormant:
			if d.t == 3:
				var full = preload("res://enemy.gd").TIER_STATS[3].health
				bosses.append([d.p, (d.h / full) if d.h > 0.0 else 1.0, true, d.h > 0.0])
	for b in bosses:
		if not (b[3] or seen.call(b[0])):
			continue
		var c = _to_screen(fit, b[0])
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(8, 0), c + Vector2(0, 9), c + Vector2(-8, 0)]), GOLD)
		draw_polyline(PackedVector2Array([c + Vector2(0, -9), c + Vector2(8, 0), c + Vector2(0, 9), c + Vector2(-8, 0), c + Vector2(0, -9)]), Color(0.3, 0.1, 0.0), 1.5)
		_tip(c, "%s (boss)\n%d%% health%s" % [SkinManager.name_of("enemy_boss_one"), roundi(b[1] * 100.0), "  -  resting" if b[2] else ""], 12.0)
	# Landmarks you've found
	for l in Zones.local_all("landmark"):
		if not (cleared or l._found or Landmarks.state(path, l.info.id).has("found")):
			continue
		var c = _to_screen(fit, l.global_position)
		var r = max(6.0, l.info.size * fit.scale)
		var col = Color(0.7, 1.0, 0.7) if Landmarks.state(path, l.info.id).has("taken") else Color(0.95, 0.75, 0.45)
		draw_arc(c, r, 0, TAU, 32, col, 2.0)
		_tip(c, l.info.name + "\n" + ("Landmark - done" if Landmarks.state(path, l.info.id).has("taken") else "Landmark - go explore it"), r + 4.0)
		draw_string(font, c + Vector2(-130, -r - 6), l.info.name, HORIZONTAL_ALIGNMENT_CENTER, 260, 14, col)
	# A captive to free (helpers.gd): always shown, so you know where to go
	for n in Zones.local_all("npc"):
		if str(n.get("shop")).begins_with("captive:"):
			var c = _to_screen(fit, n.global_position)
			draw_arc(c, 9.0, 0, TAU, 20, Color(0.3, 0.9, 1.0), 2.5)
			draw_circle(c, 3.5, Color(0.3, 0.9, 1.0))
			_tip(c, "%s\nCaptive! Clear the guards, then press G to free them" % n.npc_name, 12.0)
	# Fast-travel stops you've found
	for w in Zones.local_all("waystation"):
		if Travel.is_found(path, w.station_id):
			var c = _to_screen(fit, w.global_position)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(6, 0), c + Vector2(0, 7), c + Vector2(-6, 0)]), Color(0.5, 0.8, 1.0))
			if not str(w.station_id).begins_with("lm:"):	# a landmark's stop: the landmark's name is already there
				var where = _station_short(w.label_text)	# "by the Zone 5 gate", "northwest"...
				draw_string_outline(font, c + Vector2(-90, 20), where, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, 4, Color(0, 0, 0, 0.8))
				draw_string(font, c + Vector2(-90, 20), where, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, Color(0.6, 0.88, 1.0))
			_tip(c, "%s: %s\nFast travel stop you've found" % [Travel.station_name(), w.label_text])
	# Shrines you've seen
	for sh in Zones.local_all("shrine"):
		if seen.call(sh.global_position):
			var c = _to_screen(fit, sh.global_position)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 4), c + Vector2(-5, 4)]), Trials.TYPES[sh.ability].color)
			_tip(c, SkinManager.name_of("shrine") + "\n" + Trials.TYPES[sh.ability].name + " trial")
	# Gates
	for door in Zones.local_all("door"):
		if not seen.call(door.global_position):
			continue
		var c = _to_screen(fit, door.global_position)
		draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(0, 1, 1) if GameState.is_unlocked(door.target_scene) else Color(0.9, 0.1, 0.1))
		_tip(c, _gate_tip(door.target_scene))
	# Where you fell / where bosses fell
	for m in GameState.zone_marks.get(path, []):
		var c = _to_screen(fit, m.p)
		if m.kind == "death":
			draw_line(c - Vector2(5, 5), c + Vector2(5, 5), Color(1, 0.2, 0.2), 2.0)
			draw_line(c - Vector2(5, -5), c + Vector2(5, -5), Color(1, 0.2, 0.2), 2.0)
			_tip(c, "You fell here" + ("\nKilled by " + m.info if m.get("info", "") != "" else ""))
		else:
			draw_arc(c, 8, 0, TAU, 20, GOLD, 2.0)
			_tip(c, "Boss defeated here" + ("\n" + m.info if m.get("info", "") != "" else ""))
	# You
	var player = get_tree().get_first_node_in_group("player")
	if player:
		draw_circle(_to_screen(fit, player.global_position), 5, Color.WHITE)
		_tip(_to_screen(fit, player.global_position), "You")


# ---------- Hover labels ----------
## Remember something on the map you can hover. r = how close the mouse must be (pixels).
func _tip(p: Vector2, text: String, r := 10.0):
	_hot.append({p = p, r = r, text = text})


## Same, for a rectangle (zones on the spiral, shops in town).
func _tip_rect(rect: Rect2, text: String):
	_hot.append({rect = rect, text = text})


## A gate's label: where it goes, and whether it's open.
func _gate_tip(target: String) -> String:
	var zn = GameState.ZONE_NAMES.get(target, "?")
	if target == "res://Home.tscn":
		return "Gate to " + zn
	if GameState.is_unlocked(target):
		return "Gate to %s\nOpen" % zn
	return "Gate to %s\nLocked. %s" % [zn, GameState.unlock_hint(target)]


## Draw the label for whatever is under the mouse (the closest thing wins).
func _draw_tooltip(font):
	var best = null
	var best_d = INF
	for h in _hot:
		var d = INF
		if h.has("rect"):
			if h.rect.has_point(_mouse):
				d = 1000.0	# small markers inside a zone or shop win over the area itself
		else:
			d = _mouse.distance_to(h.p)
			if d > h.r:
				d = INF
		if d < best_d:
			best_d = d
			best = h
	if best == null:
		return
	var lines = best.text.split("\n")
	var fs = 16
	var w = 0.0
	for l in lines:
		w = max(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var box = Rect2(_mouse + Vector2(16, 12), Vector2(w + 16, lines.size() * (fs + 4) + 10))
	if box.end.x > size.x:	# keep it on screen
		box.position.x = _mouse.x - box.size.x - 12
	if box.end.y > size.y:
		box.position.y = _mouse.y - box.size.y - 8
	draw_rect(box, Color(0.05, 0.05, 0.08, 0.95))
	draw_rect(box, GOLD, false, 1.5)
	for i in range(lines.size()):
		draw_string(font, box.position + Vector2(8, 5 + fs + i * (fs + 4)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD if i == 0 else Color(0.85, 0.85, 0.85))


# ---------- helpers ----------
## Scale + offset that fits a world rectangle into a share of the screen, centered.
func _fit(world: Rect2, share: float) -> Dictionary:
	var s = min(size.x * share / world.size.x, size.y * share / world.size.y)
	var offset = size / 2.0 - (world.position + world.size / 2.0) * s
	# Zoom: screen = middle + (unzoomed - middle - focus) * zoom
	offset = size / 2.0 + (offset - size / 2.0 - _focus) * _zoom
	return {scale = s * _zoom, offset = offset}


func _to_screen(fit: Dictionary, world_pos: Vector3) -> Vector2:
	return fit.offset + Vector2(world_pos.x, world_pos.z) * fit.scale


## Paint a zone's fog grid into a screen rectangle: explored squares light, the rest dark.
func _draw_fog_cells(screen: Rect2, half: Vector2, revealed, cell := 4.0):
	draw_rect(screen, UNEXPLORED)
	if revealed == null:
		return
	var cols = ceili(half.x * 2.0 / cell)
	var rows = ceili(half.y * 2.0 / cell)
	if revealed.size() != cols * rows:
		return
	var cw = screen.size.x / cols
	var ch = screen.size.y / rows
	for r in range(rows):	# one rectangle per run of explored squares (huge zones have 90,000 squares)
		var start = -1
		for c in range(cols + 1):
			var on = c < cols and revealed[r * cols + c]
			if on and start == -1:
				start = c
			elif not on and start != -1:
				draw_rect(Rect2(screen.position + Vector2(start * cw, r * ch), Vector2((c - start) * cw + 0.5, ch + 0.5)), EXPLORED)
				start = -1


## A stop's label without the zone name in front ("Zone 6, by the Zone 5 gate" -> "by the Zone 5 gate").
func _station_short(label: String) -> String:
	var i = label.find(", ")
	return label.substr(i + 2) if i >= 0 else label
