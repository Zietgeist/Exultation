extends "res://lm_base.gd"
## Monument (Fallen Statue / Crashed Airliner / Derelict Satellite): huge, lit up, seen from far away.
## The first of you to reach it goes on the party's record. A shrine waits beside it (if a trial is
## open for you). Has a fast-travel stop.


func title_height() -> float:
	return 30.0


func build():
	match SkinManager.props_style():
		"zombie": _airliner()
		"scifi": _satellite()
		_: _statue()
	var beacon = OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.85, 0.5)
	beacon.omni_range = 40.0
	beacon.light_energy = 2.0
	beacon.position.y = 22.0
	add_child(beacon)
	var s = state()
	if s.has("found_by"):
		label("First reached by %s (%s)" % [s.found_by, s.found], Vector3(0, 26, 0), 30, Color(0.9, 0.9, 1.0))


func _statue():
	var stone = mat("lm_statue", Color(0.62, 0.6, 0.58))
	box(Vector3(14, 3, 14), Vector3(0, 1.5, 0), stone)
	box(Vector3(5, 18, 4), Vector3(0, 12, 0), stone)
	box(Vector3(14, 3, 3), Vector3(0, 18, 0), stone)	# arms
	var head = MeshInstance3D.new()
	var sp = SphereMesh.new()
	sp.radius = 3.0
	sp.height = 6.0
	head.mesh = sp
	head.material_override = stone
	head.position = Vector3(9, 1.8, 6)	# fallen off, lying in the grass
	add_child(head)
	box(Vector3(1.2, 1.2, 1.2), Vector3(0, 22, 0), mat("lm_glow", Color(1.0, 0.85, 0.4), true), false)


func _airliner():
	var hull = mat("lm_hull", Color(0.75, 0.75, 0.78))
	var body = box(Vector3(36, 6, 6), Vector3(0, 3.5, 0), hull, true, 0.35)
	body.rotation.z = 0.12
	box(Vector3(8, 1, 30), Vector3(-2, 3, 0), hull, true, 0.35)	# wings
	box(Vector3(5, 8, 1), Vector3(-15, 8, -5), hull, true, 0.35)	# tail fin
	box(Vector3(1.2, 1.2, 1.2), Vector3(-15, 13, -5), mat("lm_glow", Color(1.0, 0.3, 0.2), true), false)


func _satellite():
	var metal = mat("lm_metal", Color(0.6, 0.65, 0.7))
	box(Vector3(3, 16, 3), Vector3(0, 8, 0), metal)
	var dish = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 9.0
	cyl.bottom_radius = 5.0
	cyl.height = 1.5
	dish.mesh = cyl
	dish.material_override = metal
	dish.position.y = 17.0
	dish.rotation_degrees.x = 35.0
	add_child(dish)
	for side in [-1, 1]:	# solar panels
		box(Vector3(10, 0.3, 4), Vector3(side * 7, 10, 0), mat("lm_panel", Color(0.15, 0.25, 0.6)), false)
	box(Vector3(1.2, 1.2, 1.2), Vector3(0, 20, 0), mat("lm_glow", Color(0.3, 1.0, 0.9), true), false)


## A shrine beside it, if any trial is open (and there isn't one already).
func host_start():
	if Trials.due_abilities().is_empty():
		return
	var terrain = Zones.first(self, "zone_terrain")
	if terrain == null:
		return
	var spot = global_position + facing() * (info.size + 14.0) + Vector3(facing().z, 0, -facing().x) * 10.0
	for s in Zones.all(self, "shrine"):
		if s.global_position.distance_to(spot) < 30.0:
			return
	terrain._make_shrine({p = terrain.to_local(spot), ability = Trials.due_abilities().pick_random()})
