extends Area3D
## A fast-travel stop (see fast_travel.gd). Looks depend on the world: a stone ring portal (Fantasy),
## an elevated train stop (Zombie) or a transit pad (Sci-Fi).
## Walk near it to wake it up; step onto it to open the travel list.

var station_id := ""
var label_text := ""
var zone_path := ""
var _label: Label3D
var _lit := false
var _check := 0.0


func _ready():
	add_to_group("waystation")
	var shape = CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 3.0
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5
	add_child(col)
	match Travel.style():
		"rail": _build_rail_stop()
		"tube": _build_pad()
		_: _build_portal()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 6.5
	_label.font_size = 40
	_label.pixel_size = 0.012
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)
	_refresh()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _refresh():
	_lit = Travel.is_found(zone_path, station_id)
	_label.text = Travel.station_name() + ("" if _lit else "\n(walk closer)")
	_label.modulate = Color(0.6, 1.0, 1.0) if _lit else Color(0.6, 0.6, 0.65)
	for m in find_children("*", "MeshInstance3D", true, false):
		if m.has_meta("glow"):
			m.visible = _lit


func _process(delta):
	if _lit:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var p = Zones.player
	if p and Zones.zone_of(p) == Zones.zone_of(self) and p.global_position.distance_to(global_position) < Travel.WAKE_RANGE:
		Travel.discover(zone_path, station_id, label_text)
		_refresh()


func _on_body_entered(body):
	if body != Zones.player or not _lit or GameState.ui_open:
		return
	var ui = get_tree().get_first_node_in_group("travel_ui")
	if ui == null:
		ErrorLog.fail("Waystation: no travel window (travel_ui.gd) in the HUD")
		return
	ui.open(zone_path, station_id)
	ui.opened_by = self


## Stepped off without picking a stop: close the list.
func _on_body_exited(body):
	if body != Zones.player:
		return
	var ui = get_tree().get_first_node_in_group("travel_ui")
	if ui and ui.panel.visible and ui.opened_by == self:
		ui.close()


# ---------------- Looks ----------------

func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	return m


func _box(size: Vector3, pos: Vector3, c: Color, glow := false) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(c, glow)
	if glow:
		mi.set_meta("glow", true)
	add_child(mi)
	return mi


## Fantasy: a stone ring standing on a round base, with a swirl inside when it's awake.
func _build_portal():
	var base = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 2.2
	cyl.bottom_radius = 2.4
	cyl.height = 0.3
	base.mesh = cyl
	base.position.y = 0.15
	base.material_override = _mat(Color(0.45, 0.43, 0.48))
	add_child(base)
	var ring = MeshInstance3D.new()
	var t = TorusMesh.new()
	t.inner_radius = 1.6
	t.outer_radius = 2.1
	ring.mesh = t
	ring.rotation_degrees.x = 90
	ring.position.y = 2.4
	ring.material_override = _mat(Color(0.55, 0.52, 0.58))
	add_child(ring)
	var swirl = MeshInstance3D.new()
	var disc = CylinderMesh.new()
	disc.top_radius = 1.55
	disc.bottom_radius = 1.55
	disc.height = 0.05
	swirl.mesh = disc
	swirl.rotation_degrees.x = 90
	swirl.position.y = 2.4
	var m = _mat(Color(0.5, 0.8, 1.0, 0.6), true)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	swirl.material_override = m
	swirl.set_meta("glow", true)
	add_child(swirl)


## Zombie: a platform up on pillars (the trains run along the elevated track), stairs on one side.
func _build_rail_stop():
	var rust = Color(0.45, 0.32, 0.22)
	for x in [-2.5, 2.5]:
		for z in [-1.5, 1.5]:
			_box(Vector3(0.5, 4.0, 0.5), Vector3(x, 2.0, z), Color(0.35, 0.33, 0.3))
	_box(Vector3(6.0, 0.4, 4.0), Vector3(0, 4.2, 0), rust)
	_box(Vector3(6.0, 0.25, 0.3), Vector3(0, 4.5, -2.2), Color(0.25, 0.25, 0.27))	# the rail
	for i in 5:	# stairs up
		_box(Vector3(1.6, 0.25, 0.8), Vector3(3.6 + i * 0.6, 0.4 + i * 0.8, 0), rust.darkened(0.2))
	_box(Vector3(0.3, 1.4, 0.3), Vector3(-2.6, 5.1, 1.6), Color(0.9, 0.7, 0.2), true)	# signal lamp


## Sci-Fi: a glowing pad with a glass tube rising out of it.
func _build_pad():
	var pad = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.2
	cyl.height = 0.25
	pad.mesh = cyl
	pad.position.y = 0.13
	pad.material_override = _mat(Color(0.6, 0.65, 0.7))
	add_child(pad)
	var ring = MeshInstance3D.new()
	var t = TorusMesh.new()
	t.inner_radius = 1.6
	t.outer_radius = 1.8
	ring.mesh = t
	ring.position.y = 0.3
	ring.material_override = _mat(Color(0.3, 1.0, 0.9), true)
	ring.set_meta("glow", true)
	add_child(ring)
	var tube = MeshInstance3D.new()
	var tc = CylinderMesh.new()
	tc.top_radius = 1.4
	tc.bottom_radius = 1.4
	tc.height = 4.5
	tube.mesh = tc
	tube.position.y = 2.5
	var glass = _mat(Color(0.6, 0.9, 1.0, 0.18))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tube.material_override = glass
	add_child(tube)
