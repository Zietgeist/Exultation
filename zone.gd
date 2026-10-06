extends SubViewport
## One loaded zone: its own little world (own physics), holding the zone's scene.
## Made by Zones.load_zone(). The zone on screen sits inside the World's screen;
## other loaded zones keep running in the background without being drawn.

var path := ""					# the zone's scene file, e.g. res://Zone2.tscn
var key := ""					# usually the same as path; one-off copies add "#id" (Trial Grounds)
var info := {}					# extra info handed in when it loaded (Trial Ground: ability, quality, way back)
var root: Node = null			# the zone's scene (floor, spawner, terrain, doors...)
var default_spawn := Vector3(0, 1, 0)	# where the zone's old Player node stood
var zone_name := ""				# shown on the HUD (floors set this)


func _init():
	own_world_3d = true		# separate physics and visuals from other zones
	handle_input_locally = false
	audio_listener_enable_3d = true


func _ready():
	if zone_name == "":
		zone_name = GameState.ZONE_NAMES.get(path, path.get_file().get_basename())
