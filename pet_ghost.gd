extends Node3D
## Another player's pet, as seen on my screen (online). It follows that player's own pet.
## On the HOST it can be targeted by enemies (the host runs them): hits go to its owner's game,
## where the real pet takes them. On joined players' screens it's just for looks.

var peer_id := 0
var color := Color(0.55, 0.9, 1.0)
var is_alive := true
var gathering := false	# out on a job (only then can enemies notice it)
var _target := Vector3.ZERO
var _body: MeshInstance3D


func _ready():
	top_level = true	# a child of the player stand-in, but moves on its own
	if Net.is_host():
		add_to_group("pet")	# enemies (run by the host) can go after it
	_body = MeshInstance3D.new()
	var s = SphereMesh.new()
	s.radius = 0.42
	s.height = 0.84
	_body.mesh = s
	var m = StandardMaterial3D.new()
	m.albedo_color = color.lerp(Color(0.55, 0.9, 1.0), 0.5)
	_body.material_override = m
	add_child(_body)


func net_state(pos: Vector3, alive_now: bool, gathering_now := true):
	gathering = gathering_now
	_target = pos
	is_alive = alive_now
	visible = alive_now
	if global_position.distance_to(pos) > 10.0:
		global_position = pos


func _process(delta):
	global_position = global_position.lerp(_target, min(1.0, delta * 12.0))
	_body.position.y = 0.15 * sin(Time.get_ticks_msec() / 300.0)


func alive() -> bool:
	return is_alive


func draws_aggro() -> bool:
	return gathering


## An enemy hit it (host only): the owner's real pet takes the hit.
func take_damage(amount, _source = null):
	if is_alive:
		Net.hurt_pet(peer_id, amount)


## Someone took down an enemy that was after it.
func guarded():
	Net.pet_guarded(peer_id)
