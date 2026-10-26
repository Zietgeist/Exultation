extends Node
## The horde DIRECTOR for big zones (Zone 6 and up), the same idea as the Real Place director
## (real_director.gd, Left 4 Dead style) but tuned for exploring a big zone. Host (or solo) only:
## a child of zone_features.gd. It watches how hard the party is being pushed ("stress", 0-100):
##   GRACE     a quiet couple of minutes after you arrive
##   CALM      no hordes for a few minutes: explore, loot, catch your breath
##   BUILD_UP  a horde rushes someone from off screen every few seconds, each one bigger
##   PEAK      stress maxed out (big hits, swarmed, low health) or enough hordes: no more,
##             fight off what's left, then it goes CALM again
## It ADAPTS: a peak reached without dropping low -> the next cycle is bigger; a close call -> smaller.
## Horde kills count toward the zone's 2nd boss. Nowhere out here is safe from them (only Home has no
## hordes): low health is part of the drama. Taken strongholds' guards shoot them at the gates
## (lm_stronghold.gd). Hordes find their way around walls (smart_path). The warning ("from the north!")
## comes with the first one; a build-up that can't find anywhere to send a horde goes calm and tries later.

const GRACE = 120.0
const CALM_TIME = Vector2(150.0, 240.0)
const WAVE_EVERY = Vector2(7.0, 11.0)
const MAX_WAVES = 4
const MAX_BUILD = 75.0
const BASE_WAVE = 8			# first horde of a cycle (before strength and party size)
const WAVE_GROW = 4			# each horde in the same cycle is this much bigger
const MAX_HORDE_ALIVE = 60
const SPAWN_DIST = Vector2(30.0, 42.0)
const PEAK = 100.0
const STRESS_PER_HP = 130.0		# losing all your health = +130
const STRESS_PER_CLOSE = 1.5	# per enemy within CLOSE beyond the first 2, per second
const CLOSE = 10.0
const STRESS_DRAIN = 6.0
const CALM_AFTER = 3.0
const STRENGTH_RANGE = Vector2(0.6, 2.0)
const PUT_AWAY = 220.0			# idle horde enemies this far from everyone are removed

enum State {GRACE, CALM, BUILD_UP, FIGHT_OUT}

var features = null
var state = State.GRACE
var stress := 0.0
var strength := 1.0
var _t := GRACE
var _wave := 0
var _build_time := 0.0
var _lowest := 1.0
var _last_hp := {}		# player instance id -> health last frame
var _since_hurt := 0.0
var _horde := []


func _physics_process(delta):
	if features == null or Net.is_client():
		return
	var who = features._people()
	if who.is_empty():
		return
	_horde = _horde.filter(func(e): return is_instance_valid(e) and not e.is_queued_for_deletion())
	_measure(who, delta)
	match state:
		State.GRACE, State.CALM:
			_t -= delta
			if _t <= 0.0:
				_start_build_up()
		State.BUILD_UP:
			_build_time += delta
			if _wave == 0 and _build_time >= MAX_BUILD:	# never found a spot to send a horde from: try later
				_calm()
				return
			if _wave > 0 and (stress >= PEAK or _build_time >= MAX_BUILD or _wave >= MAX_WAVES):
				_peak()
				return
			_t -= delta
			if _t <= 0.0:
				_t = randf_range(WAVE_EVERY.x, WAVE_EVERY.y)
				_send_horde(who)
		State.FIGHT_OUT:
			_t -= delta
			if _horde.size() <= 2 or _t <= 0.0:
				_calm()
	_put_away(who)


## Stress: health lost by anyone here, enemies on them, low health. Drains when nothing is close.
func _measure(who: Array, delta: float):
	_since_hurt += delta
	var swarmed = false
	for m in who:
		if not ("health" in m and "MAX_HEALTH" in m):
			continue
		var share = m.health / maxf(m.MAX_HEALTH, 1.0)
		var id = m.get_instance_id()
		if _last_hp.has(id) and m.health < _last_hp[id]:
			stress += (_last_hp[id] - m.health) / maxf(m.MAX_HEALTH, 1.0) * STRESS_PER_HP / who.size()
			_since_hurt = 0.0
		_last_hp[id] = m.health
		_lowest = minf(_lowest, share)
		var close = _enemies_on(m, CLOSE)
		if close > 2:
			stress += minf(close - 2, 8) * STRESS_PER_CLOSE * delta
			swarmed = true
	if not swarmed and _since_hurt >= CALM_AFTER:
		stress -= STRESS_DRAIN * (2.0 if state == State.CALM else 1.0) * delta
	stress = clampf(stress, 0.0, PEAK)


func _enemies_on(m, radius: float) -> int:
	var n = 0
	for e in Zones.all(self, "enemy"):
		if e.aggroed and e.global_position.distance_to(m.global_position) <= radius:
			n += 1
	return n


func _start_build_up():
	state = State.BUILD_UP
	stress = minf(stress, 20.0)
	_wave = 0
	_build_time = 0.0
	_lowest = 1.0
	_t = 2.0
	print("Zone director: build-up (strength %.2f)" % strength)	# the warning goes out with the first horde


func _peak():
	state = State.FIGHT_OUT
	_t = 40.0
	if _wave > 0:
		if _lowest < 0.25:
			strength = maxf(STRENGTH_RANGE.x, strength * 0.85)
		elif _lowest > 0.5:
			strength = minf(STRENGTH_RANGE.y, strength * 1.15)
	print("Zone director: peak after %d hordes (lowest health %d%%, next strength %.2f)" % [_wave, roundi(_lowest * 100), strength])


func _calm():
	state = State.CALM
	_t = randf_range(CALM_TIME.x, CALM_TIME.y)
	if _wave > 0:
		features._announce("calm", {text = "It's quiet... for now."})
	print("Zone director: calm for %ds" % roundi(_t))


func _send_horde(who: Array):
	if _horde.size() >= MAX_HORDE_ALIVE:
		return
	var target = who.pick_random()	# nowhere is safe out here (only Home has no hordes)
	var spots = []
	for i in randi_range(2, 3):	# from two or three directions
		var s = _offscreen_spot(target)
		if s != null:
			spots.append(s)
	if spots.is_empty():
		return
	_wave += 1
	var size = mini(roundi((BASE_WAVE + WAVE_GROW * (_wave - 1)) * strength * (1.0 + 0.5 * (who.size() - 1))), MAX_HORDE_ALIVE - _horde.size())
	var tiers = []
	if _wave >= 2:
		tiers.append(1)	# a Thug leads from the 2nd horde on
	if _wave >= 3:
		tiers.append(2)	# and a Master on the 3rd
	while tiers.size() < size:
		tiers.append(0)
	for k in range(tiers.size()):
		var center = spots[k % spots.size()]
		var p = center + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
		var e = features._spawn(tiers[k], features.to_local(p))
		e.aggroed = true
		e.hunter = true		# comes straight for them, never gives up
		e.smart_path = true	# and finds its way around fences, huts and walls (Trash too)
		e.player = target
		_horde.append(e)
	if _wave == 1:	# the warning, with where it's coming from
		var d = spots[0] - target.global_position
		var from = ("north" if d.z < 0 else "south") if absf(d.z) > absf(d.x) else ("west" if d.x < 0 else "east")
		features._announce("horde", {text = "A horde is coming from the %s!" % from})
	print("Zone director: horde %d, %d foes" % [_wave, tiers.size()])


## A spot 30-42 m from the target, on land, not somewhere safe, and (for me) off screen.
func _offscreen_spot(target):
	var cam = get_viewport().get_camera_3d() if target == Zones.player else null
	var sp = features._spawner()
	for i in 16:
		var a = randf() * TAU
		var p = target.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(SPAWN_DIST.x, SPAWN_DIST.y)
		if sp:
			if sp.clamp_to_map(p).distance_to(p) > 0.5:
				continue	# off the map
		var local = features.to_local(p)
		if Landmarks.blocks(features.zone_path, local, 8.0) or Regions.in_heart(features.zone_path, local, 8.0):
			continue
		if GameState.dry_spot(p, features).distance_to(p) > 1.0:
			continue	# deep water
		if cam and cam.is_position_in_frustum(p + Vector3(0, 1.2, 0)):
			continue
		return p
	return null


## Horde stragglers nobody is near anymore: gone.
func _put_away(who: Array):
	for e in _horde:
		if e.aggroed and e.hunter:
			continue
		if features._closest(who, e.global_position) > PUT_AWAY:
			e.queue_free()
