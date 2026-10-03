extends Node3D
## The Pomodoro Gate at Home:
## - Deposit Shrine: walk in to bank your gold. That starts a 5-minute rest.
## - Return Portal: takes you back to exactly where you left your zone, once the rest is over.

const REST_SECONDS = 5 * 60
const PORTAL_OFFSET = Vector3(8, 0, 0)

var shrine: Area3D
var shrine_label: Label3D
var portal = null


func _ready():
	_build_shrine()
	_build_portal()


func _build_shrine():
	shrine = Area3D.new()
	add_child(shrine)
	var mesh = CylinderMesh.new()
	mesh.top_radius = 1.5
	mesh.bottom_radius = 2.0
	mesh.height = 1.2
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = 0.6
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.45, 0.05)
	mi.material_override = mat
	shrine.add_child(mi)
	var shape = CylinderShape3D.new()
	shape.radius = 2.2
	shape.height = 3.0
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5
	shrine.add_child(col)
	shrine_label = Label3D.new()
	shrine_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shrine_label.position.y = 3.2
	shrine_label.font_size = 44
	shrine_label.outline_size = 12
	shrine_label.no_depth_test = true
	shrine_label.modulate = Color(1.0, 0.85, 0.3)
	shrine.add_child(shrine_label)
	shrine.body_entered.connect(_on_shrine_entered)


func _build_portal():
	if GameState.return_scene == "":
		return
	portal = load("res://portal.gd").new()
	portal.target_scene = GameState.return_scene
	portal.target_position = GameState.return_position
	portal.color = Color(0.3, 0.8, 1.0)
	portal.position = PORTAL_OFFSET
	portal.before_travel = func(): GameState.return_scene = ""	# one trip back per deposit
	add_child(portal)


func _on_shrine_entered(body: Node):
	if body.name != "Player":
		return
	var amount = GameState.deposit_gold()
	if amount > 0:
		SessionManager.start_rest(REST_SECONDS)
		print("Deposited ", amount, " gold. Rest for 5 minutes.")


func _process(_delta):
	shrine_label.text = "Deposit Shrine\nBanked: %d gold" % GameState.gold_banked
	if GameState.gold_carried > 0:
		shrine_label.text += "\n(step in to deposit %d)" % GameState.gold_carried
	if portal:
		var zone_name = GameState.ZONE_NAMES.get(portal.target_scene, "your zone")
		if SessionManager.is_resting():
			var s = int(SessionManager.rest_left)
			portal.active = false
			portal.label_text = "Return to %s\nResting %d:%02d" % [zone_name, s / 60, s % 60]
		else:
			portal.active = true
			portal.label_text = "Return to %s\nReady" % zone_name
		portal.refresh()
