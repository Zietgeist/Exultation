extends StaticBody3D
## A Real Place's "floor" marker: the ground itself is built by real_zone.gd from the map.
## Other systems ask the floor how big the zone is (group map_floor).

const REAL_MAP = preload("res://real_map.gd")


func _ready():
	add_to_group("map_floor")


func get_half_size() -> Vector2:
	return Vector2(REAL_MAP.HALF_SIZE, REAL_MAP.HALF_SIZE)
