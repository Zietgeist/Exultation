extends "res://lm_base.gd"
## Rift (Dark Rift / Nest / Spawning Hive): keeps spawning foes around itself until it's closed.
## Four Guardians stand around it; when all four fall, it closes for good (saved with the party):
## the land around it calms (sleeping foes nearby are gone) and it counts toward the 2nd boss.

const SPAWN_EVERY = 10.0
const MAX_SPAWNED = 20
const CALM_RADIUS = 150.0

var _guardians := 0
var _spawned := []
var _spawn_t := 3.0
var _core: MeshInstance3D
var _closed := false


func title_height() -> float:
	return 11.0


func build():
	var style = SkinManager.props_style()
	var c = {"zombie": Color(0.55, 0.15, 0.1), "scifi": Color(0.5, 0.2, 0.75)}.get(style, Color(0.35, 0.1, 0.55))
	_core = MeshInstance3D.new()
	var t = TorusMesh.new()
	t.inner_radius = 3.0
	t.outer_radius = 4.5
	_core.mesh = t
	_core.rotation_degrees.x = 90
	_core.position.y = 5.0
	_core.material_override = mat("lm_rift", c, true)
	add_child(_core)
	for i in 8:	# jagged shards around it
		var a = TAU * i / 8.0
		var sh = box(Vector3(1.2, randf_range(3, 6), 1.2), Vector3(cos(a), 0, sin(a)) * 9.0 + Vector3(0, 2, 0), mat("lm_shard", c.darkened(0.4)), false, a)
		sh.rotation.z = 0.3
	if state().has("closed"):
		_close_look()


func host_start():
	if state().has("closed"):
		return
	for i in 4:
		var a = TAU * i / 4.0 + 0.4
		var g = spawn_enemy(2, Vector3(cos(a), 0, sin(a)) * 14.0, 1.6, Landmarks.word("guardian"))
		if g:
			_guardians += 1
			g.no_count = true
			g.enemy_died.connect(func(_t): _guardian_down())


func tick(dt: float):
	if _closed:
		return
	_core.rotation.y += dt * 2.0
	if Net.is_client() or state().has("closed"):
		return
	_spawn_t -= dt
	if _spawn_t > 0.0:
		return
	_spawn_t = SPAWN_EVERY
	_spawned = _spawned.filter(func(e): return is_instance_valid(e))
	if _spawned.size() >= MAX_SPAWNED or player_distance() > 160.0 and GameState.party(self).size() <= 1:
		return
	for i in 3:
		var a = randf() * TAU
		var e = spawn_enemy(1 if randf() < 0.25 else 0, Vector3(cos(a), 0, sin(a)) * randf_range(6, 10))
		if e:
			_spawned.append(e)
			count_for_zone(e)


func _guardian_down():
	_guardians -= 1
	if _guardians > 0:
		return
	# Close it: calm the land around it, and it counts toward the zone's 2nd boss
	var sp = Zones.first(self, "zone_spawner")
	if sp:
		for k in sp._buckets.keys():
			sp._buckets[k] = sp._buckets[k].filter(func(d): return d.t == 3 or Vector2(d.p.x - global_position.x, d.p.z - global_position.z).length() > CALM_RADIUS)	# bosses stay
		sp.total_killed += roundi(sp.min_clear * 0.08)
	set_state({closed = Time.get_date_string_from_system(), by = Landmarks.who()})
	announce("closed", {by = Landmarks.who()})


func net_event(event: String, data: Dictionary):
	if event != "closed":
		return
	GameState.notify("%s is closed! The land around it falls quiet." % info.name)
	Story.add("Closed %s with %s." % [info.name, ", ".join(data.get("by", [Story.player_name]))])
	Traits.nudge("pace", 4.0, "closed " + info.name)
	_close_look()


func _close_look():
	_closed = true
	_core.material_override = mat("lm_rift_closed", Color(0.25, 0.25, 0.27))
	_core.rotation.y = 0.0
