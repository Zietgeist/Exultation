extends StaticBody3D
## A zone's floor, border walls and gates, built from world_layout.gd.
## Each zone's floor script just extends this and sets its name and colors, e.g.:
##     extends "res://spiral_floor.gd"
##     func _init(): zone_title = "Zone 4"; color_a = ...; color_b = ...
##
## The floor is one checkerboard plane (a small shader), so even huge zones stay light.
## Gates go wherever this zone touches another one (world_layout.gd works them out);
## each gate gets a door (door.gd) that stays locked until the zone behind it is unlocked.

const LAYOUT = preload("res://world_layout.gd")
const TILE = 10.0
const WALL_HEIGHT = 2.0

var zone_title := "Zone"
var color_a := Color(0.3, 0.3, 0.3)
var color_b := Color(0.5, 0.5, 0.5)
var path := ""
var half := Vector2(50, 50)


func _ready():
	add_to_group("map_floor")
	path = owner.scene_file_path if owner else scene_file_path
	half = LAYOUT.half_size(path)
	_name_zone(zone_title)
	_build_floor()
	_build_walls_and_gates()
	_place_stations.call_deferred()	# after the terrain is up (so stations stay out of deep water)
	if path == "res://Home.tscn":
		_build_hall()
		var rp = load("res://real_place_gate.gd").new()	# Real Place: play in a real neighborhood
		rp.position = REAL_PLACE_SPOT
		add_child(rp)
		Helpers.build_town(self)	# the cook and assistants you've rescued


## Half the floor size (x, z). The spawner and terrain use this to stay on the map.
func get_half_size() -> Vector2:
	return half


func _build_floor():
	var plane = MeshInstance3D.new()
	var mesh = PlaneMesh.new()
	mesh.size = half * 2.0
	plane.mesh = mesh
	var mat = ShaderMaterial.new()
	mat.shader = _checker_shader()
	mat.set_shader_parameter("color_a", SkinManager.color("floor_a", color_a))	# a skin can recolor every floor
	mat.set_shader_parameter("color_b", SkinManager.color("floor_b", color_b))
	mat.set_shader_parameter("tile", TILE)
	mat.set_shader_parameter("half", half)
	plane.material_override = mat
	plane.position.y = 0.15
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plane)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(half.x * 2.0, 0.2, half.y * 2.0)
	col.shape = shape
	col.position = Vector3(0, 0.1, 0)
	add_child(col)


static var _shader: Shader = null

static func _checker_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform float tile = 10.0;
uniform vec2 half = vec2(50.0);
varying vec2 local_xz;
void vertex() { local_xz = VERTEX.xz; }
void fragment() {
	vec2 cell = floor((local_xz + half) / tile);
	float odd = mod(cell.x + cell.y, 2.0);
	ALBEDO = mix(color_a.rgb, color_b.rgb, odd);
	ROUGHNESS = 0.9;
}
"""
	return _shader


## Four walls with a gap (and a door) wherever this zone meets another.
func _build_walls_and_gates():
	var gates = LAYOUT.gates(path)
	for side in ["n", "s", "e", "w"]:
		var along_x = side == "n" or side == "s"
		var length = half.x * 2.0 if along_x else half.y * 2.0
		var gaps = []
		for g in gates:
			if g.side == side:
				gaps.append(g.along)
		gaps.sort()
		# Wall pieces between the gaps
		var start = -length / 2.0
		for a in gaps + [length / 2.0 + LAYOUT.GATE_WIDTH / 2.0]:
			var stop = a - LAYOUT.GATE_WIDTH / 2.0
			if stop - start > 0.5:
				_wall(side, (start + stop) / 2.0, stop - start)
			start = a + LAYOUT.GATE_WIDTH / 2.0
	for g in gates:
		_door(g)


func _wall(side: String, mid: float, length: float):
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	var along_x = side == "n" or side == "s"
	shape.size = Vector3(length, WALL_HEIGHT, 1) if along_x else Vector3(1, WALL_HEIGHT, length)
	col.shape = shape
	body.add_child(col)
	var view = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = shape.size
	view.mesh = mesh
	view.material_override = SkinManager.material("zone_wall", Color(0.15, 0.13, 0.12))
	body.add_child(view)
	match side:
		"n": body.position = Vector3(mid, 1, -half.y)
		"s": body.position = Vector3(mid, 1, half.y)
		"w": body.position = Vector3(-half.x, 1, mid)
		"e": body.position = Vector3(half.x, 1, mid)
	add_child(body)


func _door(g: Dictionary):
	var d = Area3D.new()
	d.set_script(load("res://door.gd"))
	d.target_scene = g.to
	d.name = "DoorTo" + g.to.get_file().get_basename()
	var along_x = g.side == "n" or g.side == "s"
	var size = Vector3(LAYOUT.GATE_WIDTH, 2, 3) if along_x else Vector3(3, 2, LAYOUT.GATE_WIDTH)
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	d.add_child(col)
	var view = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(size.x, 0.2, size.z)	# a glowing strip on the floor of the gap
	view.mesh = mesh
	view.position.y = -0.7
	d.add_child(view)
	d.position = g.pos + Vector3(0, 1, 0)
	add_child(d)


## Fast-travel stops (fast_travel.gd), plus the elevated tracks / vacuum tubes between them.
func _place_stations():
	if not is_inside_tree():
		return
	var terrain = Zones.first(self, "zone_terrain")
	var spots = []
	for s in Travel.stations_for(path):
		var w = Area3D.new()
		w.set_script(load("res://waystation.gd"))
		w.station_id = s.id
		w.label_text = s.label
		w.zone_path = path
		var p = s.pos
		if terrain and terrain.is_water(p):
			p = terrain.nearest_land(p)
		w.position = p
		add_child(w)
		spots.append(p)
	_build_lines(spots)
	Landmarks.build(self, path)	# strongholds, towns, caverns... (Zone 4 and up)
	if Regions.is_big(path):	# regions, encounters and hordes (Zone 6 and up)
		var f = Node3D.new()
		f.set_script(load("res://zone_features.gd"))
		f.zone_path = path
		f.name = "ZoneFeatures"
		add_child(f)
	Helpers.place_captives(self, path)	# a captive to free (cook: Zone 2, assistants: Zones 3-4)


## Rail (Zombie): a track up on pillars. Tube (Sci-Fi): a glass tube. Portal (Fantasy): nothing.
## Each stop links to its two nearest neighbors.
func _build_lines(spots: Array):
	var style = Travel.style()
	if style == "portal" or spots.size() < 2:
		return
	var done = {}
	for i in spots.size():
		var near = range(spots.size()).filter(func(j): return j != i)
		near.sort_custom(func(a, b): return spots[i].distance_to(spots[a]) < spots[i].distance_to(spots[b]))
		for j in near.slice(0, 2):
			var key = "%d-%d" % [min(i, j), max(i, j)]
			if done.has(key):
				continue
			done[key] = true
			if style == "rail":
				_rail(spots[i], spots[j])
			else:
				_tube(spots[i], spots[j])


func _rail(a: Vector3, b: Vector3):
	var dir = Vector3(b.x - a.x, 0, b.z - a.z)
	var length = dir.length()
	var beam = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.6, 0.35, length)
	beam.mesh = box
	beam.material_override = SkinManager.material("rail", Color(0.3, 0.28, 0.27))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	beam.global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (a + b) / 2.0 + Vector3(0, 4.45, 0))
	var n = int(length / 25.0)
	for k in range(1, n):
		var p = a.lerp(b, float(k) / n)
		var pillar = MeshInstance3D.new()
		var pb = BoxMesh.new()
		pb.size = Vector3(0.6, 4.3, 0.6)
		pillar.mesh = pb
		pillar.material_override = SkinManager.material("rail_bed", Color(0.35, 0.33, 0.3))
		pillar.position = Vector3(p.x, 2.15, p.z)
		add_child(pillar)


func _tube(a: Vector3, b: Vector3):
	var dir = Vector3(b.x - a.x, 0, b.z - a.z)
	var tube = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = dir.length()
	cyl.radial_segments = 12
	tube.mesh = cyl
	var glass = StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.9, 1.0, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tube.material_override = glass
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tube)
	var basis = Basis(Quaternion(Vector3.UP, dir.normalized()))
	tube.global_transform = Transform3D(basis, (a + b) / 2.0 + Vector3(0, 4.0, 0))


## Home: the Hall of Legends. Every party (that this PC knows) which cleared the last zone.
const HALL_SPOT = Vector3(34, 0, 30)
const REAL_PLACE_SPOT = Vector3(14, 0, -4)	# the Real Place ring at Home
var _hall_label: Label3D

func _build_hall():
	var stone = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(2.2, 7.0, 2.2)
	stone.mesh = b
	stone.position = HALL_SPOT + Vector3(0, 3.5, 0)
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.72, 0.35)
	m.metallic = 0.6
	m.roughness = 0.3
	stone.material_override = m
	add_child(stone)
	var col = StaticBody3D.new()
	var cs = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = b.size
	cs.shape = shape
	col.add_child(cs)
	col.position = stone.position
	add_child(col)
	_hall_label = Label3D.new()
	_hall_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hall_label.position = HALL_SPOT + Vector3(0, 7.6, 0)
	_hall_label.font_size = 30
	_hall_label.pixel_size = 0.012
	_hall_label.outline_size = 10
	_hall_label.no_depth_test = true
	_hall_label.modulate = Color(1.0, 0.85, 0.35)
	add_child(_hall_label)
	_refresh_hall()
	Party.changed.connect(_refresh_hall)


func _refresh_hall():
	if not is_instance_valid(_hall_label):
		return
	var lines = ["HALL OF LEGENDS", "(clear %s to be written here)" % GameState.ZONE_NAMES.get(GameState.ZONE_ORDER[-1], "the last zone")]
	var legends = Party.legends()
	if legends.size() > 0 or Story.firsts.has("legend_solo"):
		lines = ["HALL OF LEGENDS"]
		for l in legends:
			lines.append("%s  (%s)\n%s" % [l.name, l.date, ", ".join(l.members)])
		if Story.firsts.has("legend_solo"):
			lines.append("%s, alone" % Story.player_name)
	if Party.active():
		lines.append("\nNow playing: %s" % Party.label())
	_hall_label.text = "\n".join(lines)


## The zone's name for the HUD (set on the zone, since several zones can be loaded at once).
func _name_zone(n: String):
	var z = Zones.zone_of(self)
	if z:
		z.zone_name = n
