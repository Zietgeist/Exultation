extends Node3D
## A shopkeeper. Walk up and press G to talk; that opens their shop window.
## Set npc_name, role, shop, color and ui before adding.

var npc_name = "Shopkeeper"
var role = ""
var shop = "smith"		# "smith", "chemist" or "inn"
var color = Color(0.8, 0.7, 0.6)
var ui = null			# the shop window (shop_ui.gd)
var reach = 1.0

var _hint: Label3D


func _ready():
	add_to_group("npc")
	var body = CapsuleMesh.new()
	body.radius = 0.5
	body.height = 2.0
	var mi = MeshInstance3D.new()
	mi.mesh = body
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position.y = 1.0
	add_child(mi)
	var hat = CylinderMesh.new()	# a little hat so they read as people, not enemies
	hat.top_radius = 0.2
	hat.bottom_radius = 0.6
	hat.height = 0.5
	var hat_mi = MeshInstance3D.new()
	hat_mi.mesh = hat
	hat_mi.material_override = mat
	hat_mi.position.y = 2.25
	add_child(hat_mi)

	var name_label = Label3D.new()
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position.y = 3.2
	name_label.pixel_size = 0.012
	name_label.font_size = 36
	name_label.outline_size = 10
	name_label.text = "%s\n%s" % [npc_name, role]
	add_child(name_label)

	_hint = Label3D.new()
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.position.y = 4.4
	_hint.pixel_size = 0.012
	_hint.font_size = 36
	_hint.outline_size = 10
	_hint.modulate = Color(1.0, 0.85, 0.3)
	_hint.text = "G: Talk"
	_hint.visible = false
	add_child(_hint)


func horizontal_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func set_highlight(on: bool):
	_hint.visible = on


func talk():
	if ui:
		ui.open(shop, self)
