extends RefCounted
## Flying with wings (Scarlet's Wings, from Daddy in Zone 2). One per player (character_body_3d.gd `flight`).
##   Hold Shift to fly while your wings meter lasts (the wings say how long: Scarlet's Wings = 5 s).
##   It refills on the ground (half as fast as it drains).
##   Up in the air: over walls, hills, water and enemies; nothing can hurt you; you can't attack or use skills.
##   You can't fly out of the zone, and you won't come down into deep water (you keep gliding to the shore).
## The wings show on your back (simple shapes for now; each world can get its own look later).

const FLY_HEIGHT = 4.6		# body center up here: above walls (3), hills (3.5) and water boxes (3.5)
const RISE = 7.0			# how quickly you climb to it / settle back down
const REFILL = 0.5			# meter refills at half the speed it drains
const MIN_START = 0.6		# need this much meter to take off
const SCARLET = Color(0.85, 0.08, 0.22)

var flying := false
var meter := 0.0
var max_time := 0.0		# 0 = no wings worn
var _wings: Node3D = null
var _flap := 0.0


## Wings worn (apply_gear): how long they let you fly.
func set_wings(player, seconds: float):
	max_time = seconds
	meter = minf(meter, max_time) if meter > 0.0 else max_time
	if seconds <= 0.0:
		_land(player)
		if _wings:
			_wings.queue_free()
			_wings = null
	elif _wings == null:
		_wings = _make_wings()
		player.add_child(_wings)


## Every physics frame, before gravity. Returns true while flying (then the caller skips gravity).
func update(player, delta: float, wants_to_fly: bool) -> bool:
	if max_time <= 0.0:
		return false
	if flying:
		meter -= delta
		var over_water = GameState.dry_spot(player.global_position, player).distance_to(player.global_position) > 0.5
		if (not wants_to_fly or meter <= 0.0) and not (over_water and meter > -3.0):
			_land(player)
		elif meter <= -3.0:	# out of meter for a while over the sea: put down on the nearest shore
			player.global_position = GameState.dry_spot(player.global_position, player) + Vector3(0, 1.5, 0)
			_land(player)
	elif wants_to_fly and meter >= MIN_START:
		flying = true
		player.set_collision_mask_value(player.ENEMY_LAYER, false)	# over (through) enemies
	else:
		meter = minf(max_time, meter + delta * REFILL)
	if _wings:
		_flap += delta * (14.0 if flying else 2.0)
		var a = sin(_flap) * (0.6 if flying else 0.12)
		_wings.get_child(0).rotation.y = 0.35 + a
		_wings.get_child(1).rotation.y = -0.35 - a
	if not flying:
		return false
	player.velocity.y = (FLY_HEIGHT - player.global_position.y) * RISE
	var floor_node = Zones.first(player, "map_floor")	# never out over the zone's walls
	if floor_node and floor_node.has_method("get_half_size"):
		var half = floor_node.get_half_size() - Vector2(1.5, 1.5)
		player.global_position.x = clampf(player.global_position.x, -half.x, half.x)
		player.global_position.z = clampf(player.global_position.z, -half.y, half.y)
	return true


func _land(player):
	if not flying:
		return
	flying = false
	meter = maxf(meter, 0.0)
	player.set_collision_mask_value(player.ENEMY_LAYER, true)


## Share of the meter left (for the HUD).
func share() -> float:
	return clampf(meter / max_time, 0.0, 1.0) if max_time > 0.0 else 0.0


func _make_wings() -> Node3D:
	var root = Node3D.new()
	root.name = "Wings"
	var m = StandardMaterial3D.new()
	m.albedo_color = SCARLET
	m.emission_enabled = true
	m.emission = SCARLET
	m.emission_energy_multiplier = 0.5
	for side in [-1.0, 1.0]:
		var pivot = Node3D.new()
		pivot.position = Vector3(0.18 * side, 1.25, 0.35)	# on your back
		var w = MeshInstance3D.new()
		var pm = PrismMesh.new()
		pm.size = Vector3(1.3, 0.9, 0.06)
		w.mesh = pm
		w.material_override = m
		w.position = Vector3(0.65 * side, 0.1, 0)
		w.rotation.z = -0.5 * side
		pivot.add_child(w)
		root.add_child(pivot)
	return root
