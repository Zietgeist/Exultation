extends Control
## The map (press M).
## - At Home: the whole spiral, showing what you've explored in each zone.
## - In a zone you've cleared (both bosses down): that zone, with you, the gates,
##   enemies still left, where you fell (red X) and where bosses fell (gold ring).
## - Anywhere else: no map. You learn the zone by walking it.

const FOG_CELL = 4.0		# must match fog_of_war.gd CELL
const BG = Color(0.03, 0.03, 0.05, 0.85)
const UNEXPLORED = Color(0.12, 0.12, 0.16)
const EXPLORED = Color(0.45, 0.45, 0.5)
const LOCKED = Color(0.07, 0.07, 0.09)
const GOLD = Color(1.0, 0.85, 0.3)
const TIER_COLORS = [Color(0.2, 0.9, 0.2), Color(0.3, 0.5, 1.0), Color(0.7, 0.2, 1.0), Color(1.0, 0.8, 0.0)]

var _redraw_timer = 0.0


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)	# fill the whole screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		visible = not visible
		queue_redraw()


func _process(delta):
	if not visible:
		return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 0.2
		queue_redraw()


func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var scene = get_tree().current_scene
	if scene == null:
		return
	var path = scene.scene_file_path
	var font = get_theme_default_font()
	if path == "res://Home.tscn":
		_draw_world(font)
	elif GameState.is_zone_cleared(path):
		_draw_zone(path, font)
	else:
		var msg = "No map yet.\nDefeat both bosses in this zone to draw its map.\nThe map at Home shows everywhere you've been."
		draw_multiline_string(font, Vector2(0, size.y / 2.0 - 40), msg, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, -1, GOLD)
	draw_string(font, Vector2(0, size.y - 30), "M to close", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(0.8, 0.8, 0.8))


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
			_draw_fog_cells(screen, r.size / 2.0, fog)
			if GameState.is_zone_cleared(p):
				status = "cleared"
			elif fog == null:
				status = "not explored yet"
		draw_rect(screen, GOLD if GameState.is_zone_cleared(p) else Color(0.5, 0.5, 0.55), false, 2.0)
		# Name and status, centered near the top of each zone
		draw_string(font, screen.position + Vector2(0, 20), zone_label, HORIZONTAL_ALIGNMENT_CENTER, screen.size.x, 15, Color.WHITE)
		if status != "":
			draw_string(font, screen.position + Vector2(0, 36), status, HORIZONTAL_ALIGNMENT_CENTER, screen.size.x, 12, GOLD if status == "cleared" else Color(0.7, 0.7, 0.75))


# ---------- Zone map (cleared zone) ----------
func _draw_zone(path: String, font):
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node == null:
		return
	var half = floor_node.get_half_size()
	var local_rect = Rect2(-half, half * 2.0)
	var fit = _fit(local_rect, 0.8)
	var screen = Rect2(fit.offset + local_rect.position * fit.scale, local_rect.size * fit.scale)
	var fog = get_tree().get_first_node_in_group("zone_fog")
	_draw_fog_cells(screen, half, fog.revealed if fog else null)
	draw_rect(screen, GOLD, false, 2.0)
	draw_string(font, Vector2(0, 50), GameState.ZONE_NAMES.get(path, path) + "  - cleared", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD)

	# Enemies still left (awake and sleeping)
	var sp = get_tree().get_first_node_in_group("zone_spawner")
	for e in get_tree().get_nodes_in_group("enemy"):
		draw_circle(_to_screen(fit, e.global_position), 2.0, TIER_COLORS[e.tier])
	if sp:
		for d in sp.dormant:
			draw_circle(_to_screen(fit, d.p), 2.0, TIER_COLORS[d.t])
	# Gates
	for door in get_tree().get_nodes_in_group("door"):
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
	return {scale = s, offset = offset}


func _to_screen(fit: Dictionary, world_pos: Vector3) -> Vector2:
	return fit.offset + Vector2(world_pos.x, world_pos.z) * fit.scale


## Paint a zone's fog grid into a screen rectangle: explored squares light, the rest dark.
func _draw_fog_cells(screen: Rect2, half: Vector2, revealed):
	draw_rect(screen, UNEXPLORED)
	if revealed == null:
		return
	var cols = ceili(half.x * 2.0 / FOG_CELL)
	var rows = ceili(half.y * 2.0 / FOG_CELL)
	if revealed.size() != cols * rows:
		return
	var cw = screen.size.x / cols
	var ch = screen.size.y / rows
	for r in range(rows):
		for c in range(cols):
			if revealed[r * cols + c]:
				draw_rect(Rect2(screen.position + Vector2(c * cw, r * ch), Vector2(cw + 0.5, ch + 0.5)), EXPLORED)
