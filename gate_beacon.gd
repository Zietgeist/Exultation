extends Node3D
## Lighthouse beam for a gate. Every 20 seconds it sweeps a long, soft beam across the zone
## from the gate, so you can tell which way the exit is even through the fog.
## Only shines while the gate is open.

const PERIOD = 20.0		# seconds between sweeps
const SWEEP_TIME = 4.0		# how long one sweep takes
const SWEEP_ARC = deg_to_rad(150)	# total arc it swings through
const LENGTH = 140.0
const WIDTH = 4.0
const COLOR = Color(1.0, 0.95, 0.7)

var door = null
var _beam: MeshInstance3D
var _mat: StandardMaterial3D
var _t = 0.0
var _inward_angle = 0.0


func _ready():
	_t = randf() * PERIOD	# gates don't all sweep at once
	var inward = -door.global_position
	inward.y = 0
	if inward.length() < 0.1:
		inward = Vector3.FORWARD
	_inward_angle = atan2(inward.x, inward.z)

	var mesh = BoxMesh.new()
	mesh.size = Vector3(WIDTH, 0.05, LENGTH)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.albedo_color = Color(COLOR, 0.0)
	_beam = MeshInstance3D.new()
	_beam.mesh = mesh
	_beam.material_override = _mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.position = Vector3(0, 0, LENGTH / 2.0)	# beam starts at the gate and points away
	var pivot = Node3D.new()
	pivot.name = "Pivot"
	pivot.top_level = true	# don't inherit the door's transform
	add_child(pivot)
	pivot.global_position = Vector3(door.global_position.x, 0.45, door.global_position.z)	# just above the fog
	pivot.add_child(_beam)


func _process(delta):
	_t += delta
	var phase = fmod(_t, PERIOD)
	var pivot = $Pivot
	if phase > SWEEP_TIME or not GameState.is_unlocked(door.target_scene):
		_mat.albedo_color.a = 0.0
		return
	var k = phase / SWEEP_TIME	# 0 -> 1 across the sweep
	pivot.rotation.y = _inward_angle - SWEEP_ARC / 2.0 + SWEEP_ARC * k
	_mat.albedo_color.a = 0.35 * sin(k * PI)	# fade in, then out
