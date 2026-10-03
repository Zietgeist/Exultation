extends Node3D
const DITCH_SCENE = preload("res://Ditch.tscn")
const LOW_WALL_SCENE = preload("res://LowWall.tscn")
const SOLID_WALL_SCENE = preload("res://SolidWall.tscn")
const CLEAR_RADIUS = 10.0

func _ready():
	var m = GameState.obstacle_multiplier()
	spawn_terrain(DITCH_SCENE, roundi(30 * m))
	spawn_clusters(LOW_WALL_SCENE, roundi(15 * m))
	spawn_clusters(SOLID_WALL_SCENE, roundi(10 * m))

func get_clear_pos() -> Vector3:
	var pos = Vector3.ZERO
	var attempts = 0
	var half = map_half_size(8.0)  # extra margin: clusters scatter up to 4 units
	while pos.length() < CLEAR_RADIUS and attempts < 20:
		pos = Vector3(
			randf_range(-half.x, half.x),
			0,
			randf_range(-half.y, half.y)
		)
		attempts += 1
	return pos

func spawn_terrain(scene, count):
	for i in range(count):
		var piece = scene.instantiate()
		add_child(piece)
		piece.position = get_clear_pos()
		piece.rotation.y = randf_range(0, TAU)

func spawn_clusters(scene, cluster_count):
	for i in range(cluster_count):
		var center = get_clear_pos()
		var pieces = randi_range(2, 4)
		for j in range(pieces):
			var piece = scene.instantiate()
			add_child(piece)
			# Scatter pieces close together
			var offset = Vector3(
				randf_range(-4.0, 4.0),
				0,
				randf_range(-4.0, 4.0)
			)
			piece.position = center + offset
			# Similar angle with slight variation for L-shapes
			piece.rotation.y = randf_range(0, TAU)

## Half the size of the current zone's floor (x, z), minus a margin so things stay inside the walls.
func map_half_size(margin := 4.0) -> Vector2:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node and floor_node.has_method("get_half_size"):
		return floor_node.get_half_size() - Vector2(margin, margin)
	ErrorLog.fail("%s: no map floor found (floor must be in group map_floor). Using a guess of 45." % name)
	return Vector2(45.0, 45.0)
