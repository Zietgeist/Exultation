extends Node3D
## DADDY (Zone 2), asked for by Scarlet. Made by spiral_floor.gd in Zone 2.
##   Daddy waits at "Daddy's Spot": a big armchair, a lamp and a rug. Come near and he gets up.
##   His power: get too close and he TICKLES you: "Tickles for you!", and you're stunned for 3 seconds
##   (a few seconds before he can tickle the same player again). Keep your distance: Strike from range!
##   Beat him and everyone there gets their first wings: Scarlet's Wings (crafting.gd grant_wings).
##   Once per play session (he's back next time, for the fun of it; the wings only come once).
## Host (or solo) runs him; joined players get "daddy_down" (Net.group_event) and their own wings.

const ENEMY_SCENE = preload("res://enemy.tscn")
const WAKE = 40.0			# he gets up when someone comes this close
const TICKLE_RANGE = 3.2	# too close!
const TICKLE_STUN = 3.0
const TICKLE_AGAIN = 6.0	# seconds before he can tickle the same player again
const HEALTH = 2.5			# a Master this many times tougher
const LINES = ["Tickles for you!", "Tickle monster!", "Who wants tickles?!", "Gotcha!"]

static var beaten_this_session := false

var _daddy = null
var _cooldowns := {}		# player instance id -> seconds
var _t := 0.0
var _say: Label3D


func _ready():
	add_to_group("daddy_camp")
	_build_spot()


func _build_spot():
	var chair = Color(0.45, 0.27, 0.18)
	_box(Vector3(3.2, 1.0, 2.6), Vector3(0, 0.5, 0), chair)			# seat
	_box(Vector3(3.2, 2.4, 0.6), Vector3(0, 1.2, -1.2), chair)		# back
	_box(Vector3(0.6, 1.5, 2.6), Vector3(-1.6, 0.75, 0), chair.darkened(0.2))	# arms
	_box(Vector3(0.6, 1.5, 2.6), Vector3(1.6, 0.75, 0), chair.darkened(0.2))
	_box(Vector3(6.0, 0.04, 5.0), Vector3(0, 0.03, 1.0), Color(0.55, 0.2, 0.25))	# rug
	_box(Vector3(0.15, 2.6, 0.15), Vector3(2.8, 1.3, -0.8), Color(0.2, 0.2, 0.22))	# lamp
	var shade = _box(Vector3(0.9, 0.6, 0.9), Vector3(2.8, 2.8, -0.8), Color(1.0, 0.85, 0.5))
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.4)
	m.emission_energy_multiplier = 1.5
	shade.material_override = m
	var l = Label3D.new()
	l.text = "Daddy's Spot"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 44
	l.pixel_size = 0.013
	l.outline_size = 12
	l.modulate = Color(1.0, 0.7, 0.75)
	l.position.y = 4.2
	add_child(l)
	_say = Label3D.new()
	_say.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_say.no_depth_test = true
	_say.font_size = 52
	_say.pixel_size = 0.013
	_say.outline_size = 12
	_say.modulate = Color(1.0, 0.55, 0.7)
	_say.visible = false
	add_child(_say)


func _box(size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = SkinManager.material("daddy_%s" % c.to_html(false), c)
	add_child(mi)
	return mi


func _process(delta):
	for k in _cooldowns.keys():
		_cooldowns[k] -= delta
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.15
	if _say.visible and _daddy and is_instance_valid(_daddy):
		_say.global_position = _daddy.global_position + Vector3(0, 4.0, 0)
	if Net.is_client():
		_name_mirror()
		return
	if beaten_this_session:
		return
	var people = GameState.party(self).filter(func(m): return is_instance_valid(m) and m.is_inside_tree())
	if _daddy == null:
		if people.any(func(m): return _flat(m.global_position, global_position) < WAKE):
			_get_up()
		return
	if not is_instance_valid(_daddy) or _daddy.is_queued_for_deletion():
		return
	for m in people:	# too close: tickles!
		var id = m.get_instance_id()
		if _cooldowns.get(id, 0.0) > 0.0 or _flat(m.global_position, _daddy.global_position) > TICKLE_RANGE:
			continue
		if "flight" in m and m.flight.flying:
			continue	# can't tickle what you can't reach
		_cooldowns[id] = TICKLE_AGAIN
		var line = LINES[0] if randf() < 0.6 else LINES[randi() % LINES.size()]
		m.stun(TICKLE_STUN, line)
		_speak(line)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _get_up():
	var e = ENEMY_SCENE.instantiate()
	e.set_meta("landmark", "daddy")	# the spawner leaves him alone
	Zones.root_of(self).add_child(e)
	e.global_position = global_position + Vector3(0, 1.2, 2.5)
	e.setup(HEALTH, 2, "physical")
	e.no_count = true	# not one of the zone's two bosses
	e.set_title("Daddy")
	e.get_node("MeshInstance3D").scale = Vector3.ONE * 1.6
	e.enemy_died.connect(func(_t): _down())
	_daddy = e
	_speak("Who wants tickles?!")


func _speak(text: String):
	_say.text = text
	_say.visible = true
	if _daddy and is_instance_valid(_daddy):
		_say.global_position = _daddy.global_position + Vector3(0, 4.0, 0)
	var tw = create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func(): _say.visible = false)


func _down():
	beaten_this_session = true
	Net.group_event(self, "daddy_camp", "daddy_down", {})
	net_event("daddy_down", {})


## Host and joined players: Daddy is down. Everyone here gets their wings (once).
func net_event(event: String, _data: Dictionary):
	if event != "daddy_down":
		return
	var me = Zones.player
	if me == null or Zones.zone_of(me) != Zones.zone_of(self):
		return
	if Crafting.grant_wings():
		GameState.notify("Daddy is down! You got SCARLET'S WINGS! Hold Shift to fly.")
		Story.once("scarlets_wings", "Beat Daddy in %s and earned Scarlet's Wings." % GameState.ZONE_NAMES.get(Zones.path_of(self), "Zone 2"))
	else:
		GameState.add_gold(10)
		GameState.notify("Daddy is down! (+10 gold)  \"Okay, okay... no more tickles!\"")


## Joined players: put Daddy's name over his mirror copy (the host's title isn't sent).
func _name_mirror():
	for e in Zones.all(self, "enemy"):
		if e.tier == 2 and e._title_label == null and _flat(e.global_position, global_position) < 30.0:
			e.set_title("Daddy")
