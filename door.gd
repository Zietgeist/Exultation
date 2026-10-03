extends Area3D

@export var target_scene: String = "res://Zone1.tscn"

func _ready():
	body_entered.connect(_on_body_entered)
	
func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		if not ResourceLoader.exists(target_scene):
			ErrorLog.fail("Door '%s' leads to a zone that doesn't exist: %s" % [name, target_scene])
			return
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		get_tree().call_deferred("change_scene_to_file", target_scene)
		


func _on_body_shape_entered(body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int) -> void:
	pass # Replace with function body.
