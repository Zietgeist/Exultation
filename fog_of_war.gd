extends Node3D
## Fog of war: a dark layer over the ground in parts of the zone you haven't been near yet.
## Enemies stand above it, so you can still see them coming.
## It lifts as you explore and stays lifted for the rest of the play session.

const CELL = 4.0		# size of one fog square
const REVEAL_RADIUS = 16.0	# how far around you the fog lifts
const HEIGHT = 0.35		# just above the floor: hides the ground, but enemies and tall things stand out of it
const FOG_COLOR = Color(0.06, 0.07, 0.1, 0.93)
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
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node == null:
		ErrorLog.fail("Fog of war: no map floor found")
		return
	half = floor_node.get_half_size()
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
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var p = player.global_position
	var c0 = clampi(floori((p.x - REVEAL_RADIUS + half.x) / CELL), 0, cols - 1)
	var c1 = clampi(floori((p.x + REVEAL_RADIUS + half.x) / CELL), 0, cols - 1)
	var r0 = clampi(floori((p.z - REVEAL_RADIUS + half.y) / CELL), 0, rows - 1)
	var r1 = clampi(floori((p.z + REVEAL_RADIUS + half.y) / CELL), 0, rows - 1)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var i = r * cols + c
			if revealed[i]:
				continue
			if Vector2(_cell_x(c) - p.x, _cell_z(r) - p.z).length() <= REVEAL_RADIUS:
				revealed[i] = 1
				mm.set_instance_color(i, Color(0, 0, 0, 0))


## How much of the zone has been explored (0.0 to 1.0)
func explored_fraction() -> float:
	var n = 0
	for b in revealed:
		n += b
	return float(n) / max(1, revealed.size())


func save_state() -> PackedByteArray:
	return revealed.duplicate()
