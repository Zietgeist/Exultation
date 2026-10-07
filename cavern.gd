extends Node3D
## A cavern (behind a cavern entrance, lm_cavern.gd): a dark maze of tunnels, 7 x 7 chambers.
##   - Only a small circle of light around each of you.
##   - Ore veins (one quality better than the zone) and geodes (refine at the Smith into gems,
##     a strong creative-slot material for any recipe, advanced ones too).
##   - Foes in the tunnels and a Cavern Lord in the deepest chamber. Beat them all: cleared
##     (saved with the party). Coming back later, the cave has fewer foes but fresh veins.
##   - Sometimes your Rivals from the zone above are hiding down here (a Rival nest).
## Online: the host runs the foes. The way out is right where you came in.

const CELLS = 7
const CELL = 20.0
const HALF = 70.0
const WALL_H = 4.0

var info := {}
var alive := 0
var cleared := false
var _lights := {}		# player node -> OmniLight3D
var _open := {}		# Vector2i cell -> [Vector2i neighbors it opens to]
var _rng := RandomNumberGenerator.new()


func _ready():
	var z = Zones.zone_of(self)
	info = z.info if z and not z.info.is_empty() else {parent = "res://Zone5.tscn", id = "cavern0", name = "Test Cave", zone = 5, q = 4, back_scene = "res://Home.tscn", back_pos = Vector3(0, 1, 8)}
	if z:
		z.zone_name = info.name
	_rng.seed = hash(str(info.parent) + str(info.id))	# same tunnels every visit
	_dark()
	_maze()
	_exit()
	_veins()
	if not Net.is_client():
		_foes.call_deferred()
	if Zones.local_zone() == z:
		GameState.notify.call_deferred("%s: it's dark down here. Stay together." % info.name)


## Night-dark: no sun, very low ambient; each player carries a light.
func _dark():
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.11, 0.14)
	env.ambient_light_energy = 1.0
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _process(_delta):
	for m in GameState.party(self):
		if not is_instance_valid(m):
			continue
		var l = _lights.get(m)
		if l == null or not is_instance_valid(l):
			l = OmniLight3D.new()
			l.light_color = Color(1.0, 0.85, 0.6)
			l.omni_range = 16.0
			l.light_energy = 1.6
			l.shadow_enabled = false
			add_child(l)
			_lights[m] = l
		l.global_position = m.global_position + Vector3(0, 3, 0)


# ---------------- The tunnels ----------------

func _cell_center(c: Vector2i) -> Vector3:
	return Vector3(-HALF + CELL * (c.x + 0.5), 0, -HALF + CELL * (c.y + 0.5))


## A random maze (every chamber reachable), plus a few extra openings so it isn't one long corridor.
func _maze():
	var start = Vector2i(CELLS / 2, CELLS - 1)
	var seen = {start: true}
	var stack = [start]
	for c in range(CELLS * CELLS):
		_open[Vector2i(c % CELLS, c / CELLS)] = []
	while stack.size() > 0:
		var c = stack[-1]
		var nexts = []
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = c + d
			if n.x >= 0 and n.y >= 0 and n.x < CELLS and n.y < CELLS and not seen.has(n):
				nexts.append(n)
		if nexts.is_empty():
			stack.pop_back()
			continue
		var n = nexts[_rng.randi() % nexts.size()]
		_open[c].append(n)
		_open[n].append(c)
		seen[n] = true
		stack.append(n)
	for i in 6:	# loops
		var c = Vector2i(_rng.randi() % (CELLS - 1), _rng.randi() % CELLS)
		var n = c + Vector2i(1, 0)
		if not n in _open[c]:
			_open[c].append(n)
			_open[n].append(c)
	var rock = SkinManager.material("cave_wall", Color(0.3, 0.27, 0.25))
	for x in range(CELLS):
		for y in range(CELLS):
			var c = Vector2i(x, y)
			var p = _cell_center(c)
			if x < CELLS - 1 and not Vector2i(x + 1, y) in _open[c]:
				_wall(p + Vector3(CELL / 2.0, 0, 0), Vector3(1.5, WALL_H, CELL + 1.5), rock)
			if y < CELLS - 1 and not Vector2i(x, y + 1) in _open[c]:
				_wall(p + Vector3(0, 0, CELL / 2.0), Vector3(CELL + 1.5, WALL_H, 1.5), rock)
	for side in [[Vector3(0, 0, -HALF), Vector3(HALF * 2, WALL_H, 1.5)], [Vector3(0, 0, HALF), Vector3(HALF * 2, WALL_H, 1.5)],
			[Vector3(-HALF, 0, 0), Vector3(1.5, WALL_H, HALF * 2)], [Vector3(HALF, 0, 0), Vector3(1.5, WALL_H, HALF * 2)]]:
		_wall(side[0], side[1], rock)


func _wall(pos: Vector3, size: Vector3, m: Material):
	var body = StaticBody3D.new()
	var cs = CollisionShape3D.new()
	var sh = BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var mi = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	body.add_child(mi)
	body.position = pos + Vector3(0, size.y / 2.0, 0)
	add_child(body)


## Chambers by how far they are from the way in (deepest last).
func _by_depth() -> Array:
	var start = Vector2i(CELLS / 2, CELLS - 1)
	var dist = {start: 0}
	var queue = [start]
	while queue.size() > 0:
		var c = queue.pop_front()
		for n in _open[c]:
			if not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	var cells = dist.keys()
	cells.sort_custom(func(a, b): return dist[a] < dist[b])
	return cells


func _exit():
	var g = load("res://portal.gd").new()
	g.target_scene = info.back_scene
	g.target_position = info.back_pos
	g.label_text = "Way out"
	g.color = Color(0.9, 0.8, 0.5)
	add_child(g)
	g.position = Vector3(0, 0, HALF - 4.0)


# ---------------- Veins ----------------

func _veins():
	var cells = _by_depth()
	var node_script = preload("res://resource_node.gd")
	for i in 16:
		var c = cells[2 + _rng.randi() % (cells.size() - 2)]
		var n = node_script.new()
		n.type = "geode" if i % 3 == 0 else "ore"
		n.quality = max(1, int(info.q) + (0 if n.type == "geode" else 1))	# ore one step better than above
		add_child(n)
		n.position = _cell_center(c) + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))


# ---------------- Foes (host) ----------------

func _foes():
	var lm_state = Landmarks.state(info.parent, info.id)
	var share = 0.5 if lm_state.has("cleared") else 1.0
	var diff = 1.0 + 0.3 * (int(info.zone) - 1)
	var cells = _by_depth()
	for c in cells.slice(2):
		if _rng.randf() > 0.7 * share:
			continue
		for i in range(_rng.randi_range(1, 3)):
			_foe(_rng.randi() % 2 if _rng.randf() < 0.8 else 2, _cell_center(c) + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)), diff)
	var lord = _foe(3, _cell_center(cells[-1]), diff * 1.5)
	lord.no_count = true
	lord.set_title("Lord of " + info.name)


func _foe(tier: int, pos: Vector3, diff: float):
	var e = preload("res://enemy.tscn").instantiate()
	e.set_meta("landmark", info.id)
	add_child(e)
	e.global_position = Vector3(pos.x, 1.2, pos.z)
	e.setup(diff, tier, Crafting.roll_enemy_element(info.parent, tier == 3))
	adopt_enemy(e)
	return e


## Rivals that come down here count too (rivals.gd calls this).
func adopt_enemy(e):
	e.enemy_died.connect(_on_enemy_died)
	alive += 1


## Somewhere for a Rival to lurk (rivals.gd).
func rival_spot() -> Vector3:
	var cells = _by_depth()
	var c = cells[cells.size() / 2 + _rng.randi() % max(1, cells.size() / 2)]
	return _cell_center(c) + Vector3(0, 1.2, 0)


func _on_enemy_died(_tier):
	alive -= 1
	if alive <= 0 and not cleared:
		cleared = true
		Landmarks.set_state(info.parent, info.id, {cleared = Time.get_date_string_from_system(), by = Landmarks.who()})
		Landmarks.refresh_landmark_jobs()
		_cleared({by = Landmarks.who()})
		Net.scene_event(self, "cleared", {by = Landmarks.who()})


func net_event(event: String, data: Dictionary):
	if event == "cleared" and not cleared:
		cleared = true
		_cleared(data)


func _cleared(data: Dictionary):
	GameState.notify("%s is cleared!" % info.name)
	Story.add("Cleared out %s with %s." % [info.name, ", ".join(data.get("by", [Story.player_name]))])
	Traits.nudge("roam", -5.0, "cleared " + info.name)
