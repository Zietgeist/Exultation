extends Node	# a plain Node (not Node3D) so Zones doesn't pull this scene into the World
## TEST SCENE for real-world maps. Open it from the character screen ("Real place"), or RealMapTest.tscn + F6.
## Type an address or "lat, lon", press Enter, then walk with WASD (Shift = run, mouse wheel = zoom).
## Gray boxes only: no enemies, no saving. The address is never stored.

const REAL_MAP = preload("res://real_map.gd")
static var pending := ""	# set by the character screen; used once, then forgotten (privacy)
const SPEED = 10.0
const CAM_OFFSET = Vector3(0, 12, 7.5)	# same angle as the game camera

var rm
var map_root: Node3D
var player: CharacterBody3D
var cam: Camera3D
var input: LineEdit
var go_button: Button
var label: Label
var zoom := 1.0


func _ready():
	_make_light()
	rm = REAL_MAP.new()
	add_child(rm)
	rm.status.connect(func(t): label.text = t)
	_make_player()
	_make_ui()
	# something to stand on before a map loads
	map_root = rm.build({buildings = [], roads = [], areas = []})
	add_child(map_root)
	if pending != "":
		var q = pending
		pending = ""
		_go(q)


func _go(q: String):
	if q.strip_edges() == "":
		return
	input.release_focus()
	go_button.disabled = true
	var data = await rm.load_place(q)
	go_button.disabled = false
	if data.is_empty():
		return
	map_root.queue_free()
	map_root = rm.build(data)
	add_child(map_root)
	player.global_position = rm.free_spot(data)
	player.velocity = Vector3.ZERO
	label.text = "%s\n%d buildings, %d roads.  WASD to walk, Shift to run, wheel to zoom." % [data.name, data.buildings.size(), data.roads.size()]


func _physics_process(delta):
	var dir = Vector3.ZERO
	if not input.has_focus():	# typing in the box doesn't walk you around
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): dir.z -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): dir.z += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): dir.x += 1
	var speed = SPEED * (2.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	dir = dir.normalized() * speed
	player.velocity.x = dir.x
	player.velocity.z = dir.z
	player.velocity.y -= 9.8 * delta
	player.move_and_slide()
	if player.global_position.y < -20.0:	# fell off the edge: back to the middle
		player.global_position = Vector3(0, 2, 0)
		player.velocity = Vector3.ZERO
	cam.global_position = player.global_position + CAM_OFFSET * zoom
	cam.look_at(player.global_position)
	REAL_MAP.update_see_through(map_root, player, cam)


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(0.4, zoom * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(4.0, zoom * 1.1)


func _make_player():
	player = CharacterBody3D.new()
	var col = CollisionShape3D.new()
	var cap = CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	player.add_child(col)
	var mi = MeshInstance3D.new()
	var cm = CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	mi.mesh = cm
	mi.position.y = 0.9
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.35, 0.8)
	mi.material_override = m
	player.add_child(mi)
	add_child(player)
	player.global_position = Vector3(0, 1, 0)
	cam = Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	cam.current = true


func _make_light():
	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.75, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _make_ui():
	var ui = CanvasLayer.new()
	add_child(ui)
	var box = VBoxContainer.new()
	box.position = Vector2(12, 12)
	ui.add_child(box)
	var row = HBoxContainer.new()
	box.add_child(row)
	input = LineEdit.new()
	input.custom_minimum_size = Vector2(460, 0)
	input.placeholder_text = "Address, or  latitude, longitude"
	input.text_submitted.connect(_go)
	row.add_child(input)
	go_button = Button.new()
	go_button.text = "Go"
	go_button.pressed.connect(func(): _go(input.text))
	row.add_child(go_button)
	var back = Button.new()
	back.text = "Back"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://ClassSelect.tscn"))
	row.add_child(back)
	label = Label.new()
	label.text = "Type an address (or 'lat, lon') and press Enter."
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	box.add_child(label)
	# credits the map services require on screen
	var credit = Label.new()
	credit.text = "Map data (c) OpenStreetMap contributors  |  Search by LocationIQ.com"
	credit.add_theme_font_size_override("font_size", 12)
	credit.add_theme_color_override("font_outline_color", Color.BLACK)
	credit.add_theme_constant_override("outline_size", 3)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credit.position -= Vector2(8, 6)
	ui.add_child(credit)
