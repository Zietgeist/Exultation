extends Control
## The map (press M).
## - At Home: first the town map (shops, gates, the rest shrine, fast travel). Press M again for the
##   whole spiral, showing what you've explored in each zone. Once more closes it.
## - In a zone you've cleared (both bosses down): that zone, with you, the gates,
##   enemies still left, where you fell (red X) and where bosses fell (gold ring).
## - Anywhere else: no map. You learn the zone by walking it.
## Zoom: left click zooms in on that spot, right click zooms out, mouse wheel too.
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
		return
	elif GameState.is_zone_cleared(path):
		_draw_zone(path, font)
	else:
		var msg = "No map yet.\nDefeat both bosses in this zone to draw its map.\nThe map at Home shows everywhere you've been."
		draw_multiline_string(font, Vector2(0, size.y / 2.0 - 40), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, -1, GOLD)
	_hint(font, "M to close")


func _hint(font, text: String):
	var z = "Click: zoom in  -  Right-click: zoom out" if _zoom <= 1.0 else "Zoom x%d  -  Right-click: zoom out" % int(round(_zoom))
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
		draw_string(font, Vector2(c.x - 60, r.position.y + r.size.y / 2.0 + 6), b.sign, HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color.WHITE)
	# Rest shrine (Pomodoro gate: bank gold, rest)
	var gate_node = Zones.local_root().get_node_or_null("PomodoroGate") if Zones.local_root() else null
	if gate_node:
		_map_mark(fit, gate_node.global_position, Color(1.0, 0.8, 0.2), "Deposit / rest", font)
	# Fast travel, Hall of Legends
	for w in Zones.local_all("waystation"):
		_map_mark(fit, w.global_position, Color(0.5, 0.9, 1.0), Travel.station_name(), font)
	_map_mark(fit, preload("res://spiral_floor.gd").HALL_SPOT, Color(0.85, 0.72, 0.35), "Hall of Legends", font)
	# Gates to the zones
	for door in Zones.local_all("door"):
		var c = _to_screen(fit, door.global_position)
		var open = GameState.is_unlocked(door.target_scene)
		draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Color(0, 1, 1) if open else Color(0.9, 0.1, 0.1))
		var text = GameState.ZONE_NAMES.get(door.target_scene, "?") + ("" if open else " (locked)")
		var dir = (fit.offset + local_rect.get_center() * fit.scale - c).normalized()
		var inward = dir * (34.0 + 50.0 * abs(dir.x))	# side gates need more room for the label
		draw_string(font, c + inward - Vector2(60, -5), text, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color.WHITE)
	# Shopkeepers and you
	for n in Zones.local_all("npc"):
		if n.has_method("talk") and not n.is_in_group("shrine"):
			draw_circle(_to_screen(fit, n.global_position), 4, Color(0.9, 0.75, 0.5))
	var player = get_tree().get_first_node_in_group("player")
	if player:
		draw_circle(_to_screen(fit, player.global_position), 6, Color.WHITE)
		draw_string(font, _to_screen(fit, player.global_position) + Vector2(-20, -10), "You", HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Color.WHITE)


func _map_mark(fit: Dictionary, pos: Vector3, c: Color, text: String, font):
	var p = _to_screen(fit, pos)
	draw_circle(p, 7, c)
	draw_string(font, p + Vector2(-70, 22), text, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, c)


# ---------- Zone map (cleared zone) ----------
func _draw_zone(path: String, font):
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
	draw_string(font, Vector2(0, 50), GameState.ZONE_NAMES.get(path, path) + "  - cleared", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD)

	# Enemies still left (awake and sleeping)
	var sp = Zones.local_first("zone_spawner")
	for e in Zones.local_all("enemy"):
		draw_circle(_to_screen(fit, e.global_position), 2.0, TIER_COLORS[e.tier])
	if sp:
		for d in sp.dormant:
			draw_circle(_to_screen(fit, d.p), 2.0, TIER_COLORS[d.t])
	# Gates
	for door in Zones.local_all("door"):
		var c = _to_screen(fit, door.global_position)
		draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(0, 1, 1) if GameState.is_unlocked(door.target_scene) else Color(0.9, 0.1, 0.1))
	# Where you fell / where bosses fell
	for m in GameState.zone_marks.get(path, []):
		var c = _to_screen(fit, m.p)
		if m.kind == "death":
			draw_line(c - Vector2(5, 5), c + Vector2(5, 5), Color(1, 0.2, 0.2), 2.0)
			draw_line(c - Vector2(5, -5), c + Vector2(5, -5), Color(1, 0.2, 0.2), 2.0)
		else:
			draw_arc(c, 8, 0, TAU, 20, GOLD, 2.0)
	# You
	var player = get_tree().get_first_node_in_group("player")
	if player:
		draw_circle(_to_screen(fit, player.global_position), 5, Color.WHITE)


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
	for r in range(rows):
		for c in range(cols):
			if revealed[r * cols + c]:
				draw_rect(Rect2(screen.position + Vector2(c * cw, r * ch), Vector2(cw + 0.5, ch + 0.5)), EXPLORED)
