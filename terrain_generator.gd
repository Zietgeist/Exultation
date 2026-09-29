extends Node3D
const DITCH_SCENE = preload("res://Ditch.tscn")
const LOW_WALL_SCENE = preload("res://LowWall.tscn")
const SOLID_WALL_SCENE = preload("res://SolidWall.tscn")
const MAP_SIZE = 140.0
const CLEAR_RADIUS = 10.0

func _ready():
	spawn_terrain(DITCH_SCENE, 30)
	spawn_clusters(LOW_WALL_SCENE, 15)
	spawn_clusters(SOLID_WALL_SCENE, 10)

func get_clear_pos() -> Vector3:
	var pos = Vector3.ZERO
	var attempts = 0
	while pos.length() < CLEAR_RADIUS and attempts < 20:
		pos = Vector3(
			randf_range(-MAP_SIZE, MAP_SIZE),
			0,
			randf_range(-MAP_SIZE, MAP_SIZE)
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
