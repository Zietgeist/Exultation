extends Area3D
## A gate to another zone. Locked until that zone is unlocked in GameState.

@export var target_scene: String = "res://Zone1.tscn"

const OPEN_COLOR = Color(0, 1, 1)
const LOCKED_COLOR = Color(0.9, 0.1, 0.1)

var label: Label3D = null


func _ready():
	body_entered.connect(_on_body_entered)
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.5, 0)
	label.font_size = 48
	label.outline_size = 12
	label.no_depth_test = true
	add_child(label)
	GameState.zone_unlocked.connect(_on_zone_unlocked)
	_refresh()


func _refresh():
	var open = GameState.is_unlocked(target_scene)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = OPEN_COLOR if open else LOCKED_COLOR
	for child in get_children():
		if child is MeshInstance3D:
			child.material_override = mat
	var zone_name = GameState.ZONE_NAMES.get(target_scene, target_scene)
	if open:
		label.text = zone_name
		label.modulate = OPEN_COLOR
	else:
		label.text = "LOCKED\n" + GameState.unlock_hint(target_scene)
		label.modulate = LOCKED_COLOR


func _on_zone_unlocked(_scene_path):
	_refresh()


func _on_body_entered(body: Node) -> void:
	if body.name != "Player":
		return
	if not ResourceLoader.exists(target_scene):
		ErrorLog.fail("Door '%s' leads to a zone that doesn't exist: %s" % [name, target_scene])
		return
	if not GameState.is_unlocked(target_scene):
		# Bounce the player back the way they came
		var away = body.global_position - global_position
		away.y = 0
		body.global_position += away.normalized() * 2.0
		print("Locked: ", GameState.unlock_hint(target_scene))
		return
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.queue_free()
	get_tree().call_deferred("change_scene_to_file", target_scene)


# Connected in some scenes from the editor; not used.
func _on_body_shape_entered(_body_rid: RID, _body: Node3D, _body_shape_index: int, _local_shape_index: int) -> void:
	pass
