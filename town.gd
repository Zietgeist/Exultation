extends Node3D
## Builds the town buildings in Home: the Smith, the Chemist and the Inn, each with a shopkeeper.
## Placeholder shapes for now (a skin can replace them later).

const SHOP_UI = preload("res://shop_ui.gd")
const NPC = preload("res://npc.gd")

# Each building: where it stands, its size, colors, and its keeper.
const BUILDINGS = [
	{shop = "smith", sign = "SMITH", pos = Vector3(-28, 0, -26), size = Vector3(12, 5, 9),
		wall = Color(0.32, 0.3, 0.3), roof = Color(0.5, 0.22, 0.15),
		keeper = "Brann", role = "the Smith", keeper_pos = Vector3(-21, 0, -18), keeper_color = Color(0.55, 0.35, 0.25)},
	{shop = "chemist", sign = "CHEMIST", pos = Vector3(28, 0, -26), size = Vector3(12, 5, 9),
		wall = Color(0.25, 0.4, 0.38), roof = Color(0.2, 0.3, 0.45),
		keeper = "Ilsa", role = "the Chemist", keeper_pos = Vector3(21, 0, -18), keeper_color = Color(0.4, 0.65, 0.5)},
	{shop = "inn", sign = "INN", pos = Vector3(0, 0, 36), size = Vector3(16, 6, 9),
		wall = Color(0.55, 0.42, 0.28), roof = Color(0.45, 0.2, 0.2),
		keeper = "Old Tamsin", role = "Innkeeper", keeper_pos = Vector3(-6, 0, 27), keeper_color = Color(0.75, 0.6, 0.45)},
]

var ui = null


func _ready():
	ui = SHOP_UI.new()
	add_child(ui)
	for b in BUILDINGS:
		_build(b)


func _build(b: Dictionary):
	var body = StaticBody3D.new()
	add_child(body)
	body.position = b.pos

	var walls = BoxMesh.new()
	walls.size = b.size
	var walls_mi = MeshInstance3D.new()
	walls_mi.mesh = walls
	walls_mi.material_override = _mat(b.wall)
	walls_mi.position.y = b.size.y / 2.0
	body.add_child(walls_mi)

	var roof = PrismMesh.new()
	roof.size = Vector3(b.size.x + 1.0, 2.5, b.size.z + 1.0)
	var roof_mi = MeshInstance3D.new()
	roof_mi.mesh = roof
	roof_mi.material_override = _mat(b.roof)
	roof_mi.position.y = b.size.y + 1.25
	body.add_child(roof_mi)

	var door = BoxMesh.new()	# just paint: shows which side is the front
	door.size = Vector3(2.0, 3.0, 0.1)
	var door_mi = MeshInstance3D.new()
	door_mi.mesh = door
	door_mi.material_override = _mat(Color(0.18, 0.12, 0.08))
	var front = -1.0 if b.pos.z > 0 else 1.0	# face the middle of town
	door_mi.position = Vector3(0, 1.5, front * (b.size.z / 2.0 + 0.05))
	body.add_child(door_mi)

	var shape = BoxShape3D.new()
	shape.size = b.size
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = b.size.y / 2.0
	body.add_child(col)

	var sign_label = Label3D.new()
	sign_label.text = b.sign
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.pixel_size = 0.02
	sign_label.font_size = 64
	sign_label.outline_size = 14
	sign_label.modulate = Color(1.0, 0.9, 0.6)
	sign_label.position.y = b.size.y + 4.0
	body.add_child(sign_label)

	var npc = NPC.new()
	npc.npc_name = b.keeper
	npc.role = b.role
	npc.shop = b.shop
	npc.color = b.keeper_color
	npc.ui = ui
	add_child(npc)
	npc.position = b.keeper_pos


func _mat(c: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	return m
