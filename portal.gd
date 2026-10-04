extends Area3D
## A glowing ring you walk into to fast travel.
## Set target_scene (and optionally target_position) before adding it to the scene.

var target_scene = "res://Home.tscn"
var target_position = null	# where to appear in the target scene (null = at the matching door)
var label_text = "Portal"
var color = Color(1.0, 0.8, 0.2)
var active = true
var before_travel: Callable	# optional: runs just before traveling

var _ring: MeshInstance3D
var _label: Label3D


func _ready():
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 1.0
	ring_mesh.outer_radius = 1.4
	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.rotation_degrees.x = 90
	_ring.position.y = 1.6
	add_child(_ring)

	var shape = BoxShape3D.new()
	shape.size = Vector3(2.4, 3.0, 1.2)
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5
	add_child(col)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 3.8
	_label.font_size = 44
	_label.outline_size = 12
	_label.no_depth_test = true
	add_child(_label)

	body_entered.connect(_on_body_entered)
	refresh()


func refresh():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color if active else Color(0.35, 0.35, 0.35)
	mat.emission_enabled = active
	mat.emission = color
	_ring.material_override = mat
	_label.text = label_text
	_label.modulate = color if active else Color(0.7, 0.7, 0.7)


func _process(delta):
	_ring.rotation.y += delta * (2.0 if active else 0.3)


func _on_body_entered(body: Node):
	if not active or body.name != "Player":
		return
	if not ResourceLoader.exists(target_scene):
		ErrorLog.fail("Portal leads to a scene that doesn't exist: " + str(target_scene))
		return
	if before_travel.is_valid():
		before_travel.call()
	GameState.remember_current_zone()
	GameState.previous_scene = get_tree().current_scene.scene_file_path
	GameState.pending_spawn = target_position
	get_tree().call_deferred("change_scene_to_file", target_scene)
