extends Node3D
## Fog of war: a dark ceiling over the parts of the zone you haven't been near yet.
## It sits above head height, so NOTHING under it shows (ground, enemies, trees, walls).
## Only the very tallest things (stronghold towers) poke out: a hint of what's out there.
## The map (M) shows the ground you've explored.
## It lifts as you explore and stays lifted for the rest of the play session.

var CELL = 4.0		# size of one fog square (bigger in huge zones: world_layout.fog_cell)
const REVEAL_RADIUS = 22.0	# how far around you the fog lifts. Smaller than the view, so the outer ~15% of the screen stays fogged
const HEIGHT = 6.5		# above enemies, trees and walls: everything under it is hidden
const FOG_COLOR = Color(0.06, 0.07, 0.1, 1.0)
const CHECK_EVERY = 0.15

var saved = null		# revealed squares from an earlier visit this session
var cols = 0
var rows = 0
var half = Vector2.ZERO
var revealed = PackedByteArray()
var mm: MultiMesh
var _timer = 0.0


func _ready():
	add_to_group("zone_fog")
	var floor_node = Zones.first(self, "map_floor")
	if floor_node == null:
		ErrorLog.fail("Fog of war: no map floor found")
		return
	half = floor_node.get_half_size()
	CELL = preload("res://world_layout.gd").fog_cell(Zones.path_of(self)) if preload("res://world_layout.gd").ZONES.has(Zones.path_of(self)) else 4.0
	cols = ceili(half.x * 2.0 / CELL)
	rows = ceili(half.y * 2.0 / CELL)

	var plane = PlaneMesh.new()
	plane.size = Vector2(CELL * 1.05, CELL * 1.05)	# tiny overlap so no gaps show
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	mm.instance_count = cols * rows
	revealed.resize(cols * rows)
	if saved != null and saved.size() == cols * rows:
		revealed = saved
	for r in range(rows):
		for c in range(cols):
			var i = r * cols + c
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(_cell_x(c), HEIGHT, _cell_z(r))))
			mm.set_instance_color(i, Color(0, 0, 0, 0) if revealed[i] else FOG_COLOR)
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_reveal_around_player()


func _cell_x(c: int) -> float:
	return -half.x + CELL * (c + 0.5)


func _cell_z(r: int) -> float:
	return -half.y + CELL * (r + 0.5)


func _process(delta):
	_timer += delta
	if _timer >= CHECK_EVERY:
		_timer = 0.0
		_reveal_around_player()


func _reveal_around_player():
	if mm == null:
		return
	var player = Zones.first(self, "player")	# fog is for the local player in this zone
	if player == null:
		return
	var p = player.global_position
	var radius = max(REVEAL_RADIUS, CELL * 1.5) * Traits.sight_mult()	# Wanderer: the fog clears wider
	var c0 = clampi(floori((p.x - radius + half.x) / CELL), 0, cols - 1)
	var c1 = clampi(floori((p.x + radius + half.x) / CELL), 0, cols - 1)
	var r0 = clampi(floori((p.z - radius + half.y) / CELL), 0, rows - 1)
	var r1 = clampi(floori((p.z + radius + half.y) / CELL), 0, rows - 1)
	var fresh = 0
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var i = r * cols + c
			if revealed[i]:
				continue
			if Vector2(_cell_x(c) - p.x, _cell_z(r) - p.z).length() <= radius:
				revealed[i] = 1
				mm.set_instance_color(i, Color(0, 0, 0, 0))
				fresh += 1
	if fresh > 0:
		Traits.nudge("roam", -0.004 * fresh * (CELL / 4.0) * (CELL / 4.0))	# exploring new ground: Wanderer


## Has the fog lifted at this spot?
func is_revealed(pos: Vector3) -> bool:
	if cols == 0:
		return true
	var c = floori((pos.x + half.x) / CELL)
	var r = floori((pos.z + half.y) / CELL)
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return false
	return revealed[r * cols + c] == 1


## How much of the zone has been explored (0.0 to 1.0)
func explored_fraction() -> float:
	var n = 0
	for b in revealed:
		n += b
	return float(n) / max(1, revealed.size())


func save_state() -> PackedByteArray:
	return revealed.duplicate()
