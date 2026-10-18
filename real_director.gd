extends Node
## The Real Place DIRECTOR (pacing like Left 4 Dead / Back 4 Blood).
## It watches how hard you're being pushed ("stress", 0-100) and runs a loop:
##   CALM      (CALM_TIME s): no hordes. Loot, heal, catch your breath.
##   BUILD_UP  a horde rushes you from off-screen every ~WAVE_EVERY s, each one bigger.
##   PEAK      stress maxed out (heavy damage, swarmed, or low health): no more hordes;
##             fight off what's left, then it goes CALM again.
## It ADAPTS: reach the peak without dropping low -> next cycle bigger. Nearly die -> smaller.
## Stress goes up when you take damage and when enemies are on you; it drains when nothing is close.
## Hordes don't count toward clearing the place (only its packs and bosses do).
## Host only (enemies run on the host). Real Places are solo for now.

const ENEMY_SCENE = preload("res://enemy.tscn")
const REAL_MAP = preload("res://real_map.gd")

const GRACE = 25.0			# quiet seconds after you arrive
const CALM_TIME = 60.0		# "subsiding for a minute"
const WAVE_EVERY = Vector2(4.0, 7.0)	# seconds between hordes while building up
const SWARMS_PER_WAVE = Vector2i(2, 3)	# each horde bursts out of this many buildings around you
const DOOR_OUT = 1.5		# spawn this far outside a building's wall ("out the door")
const BASE_WAVE = 30			# first horde of a cycle (before strength)
const WAVE_GROW = 15			# each horde in the same cycle is this much bigger
const MAX_BUILD = 120.0		# a build-up never lasts longer than this
const MAX_HORDE_ALIVE = 180	# cap on horde enemies at once (keeps it fast)
const PATHING = preload("res://pathing.gd")
const FLOW_RADIUS = 25		# route map: squares (2 m) each way around you = 50 m
const FLOW_EVERY = 0.5
const SPAWN_DIST = Vector2(28.0, 42.0)	# off-screen ring around you
const PEAK = 100.0
const STRESS_PER_HP = 130.0		# losing 100% of your health = +130 stress
const STRESS_PER_CLOSE = 1.5	# per enemy within CLOSE m beyond the first 2, per second (up to 12/s)
const CLOSE = 10.0
const STRESS_DRAIN = 6.0		# per second once you haven't been hurt for CALM_AFTER s (double while CALM)
const CALM_AFTER = 3.0
const LOW_HEALTH = 0.3			# below this share of health: instant peak
const STRENGTH_RANGE = Vector2(0.5, 3.0)

enum State {GRACE, CALM, BUILD_UP, FIGHT_OUT}

var zone = null				# real_zone.gd
var state = State.GRACE
var stress := 0.0
var strength := 1.0			# grows/shrinks cycle to cycle to keep you near your limit
var horde_alive := 0
var _t := GRACE				# seconds left in GRACE / CALM, or until the next horde
var _wave := 0				# hordes so far this build-up
var _build_time := 0.0
var _lowest := 1.0			# lowest health share this cycle
var _last_hp := -1.0
var _since_hurt := 0.0
var _doors := []			# [{p = Vector2 spot just outside a wall, c = building center}] (built once)
var _flow := {}				# route map: grid square -> steps to you (0 = your square)
var _clear := {}			# grid square -> true if a straight run from it to you hits no building
var _flow_start := Vector2i.ZERO
var _flow_t := 0.0
const NEIGHBORS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


func _ready():
	_build_doors.call_deferred()


## A "door" on every building: the middle of its longest wall, a little outside. Hordes pour out of these.
func _build_doors():
	if zone == null:
		return
	for b in zone.info.data.buildings:
		var pts = b.pts
		if pts.size() < 3:
			continue
		var center = Vector2.ZERO
		for q in pts:
			center += q
		center /= pts.size()
		var best = -1.0
		var door = null
		for i in range(pts.size()):
			var a = pts[i]
			var c = pts[(i + 1) % pts.size()]
			var l = a.distance_to(c)
			if l > best:
				var mid = (a + c) / 2.0
				var out = (mid - center).normalized()
				best = l
				door = mid + out * DOOR_OUT
		if door != null and not REAL_MAP._inside_building(zone.info.data, door):
			_doors.append({p = door, c = center})


func _physics_process(delta):
	if zone == null or not is_instance_valid(zone) or zone.cleared:
		return
	var me = Zones.player
	if me == null or not is_instance_valid(me) or not me.is_inside_tree() or Zones.zone_of(me) != Zones.zone_of(self):
		return
	_measure(me, delta)
	_flow_t -= delta
	if _flow_t <= 0.0 and horde_alive > 0:
		_flow_t = FLOW_EVERY
		_build_flow(me)
	match state:
		State.GRACE, State.CALM:
			_t -= delta
			if _t <= 0.0:
				_start_build_up()
		State.BUILD_UP:
			_build_time += delta
			if stress >= PEAK or _build_time >= MAX_BUILD:
				_peak()
				return
			_t -= delta
			if _t <= 0.0:
				_t = randf_range(WAVE_EVERY.x, WAVE_EVERY.y)
				_send_horde(me)
		State.FIGHT_OUT:	# no new hordes: calm starts once the rush is (mostly) beaten
			_t -= delta
			if horde_alive <= 2 or _t <= 0.0:
				_calm()


## Stress: damage taken, enemies on you, low health. Drains when nothing is close.
func _measure(me, delta: float):
	var share = me.health / maxf(me.MAX_HEALTH, 1.0)
	_since_hurt += delta
	if _last_hp >= 0.0 and me.health < _last_hp:
		stress += (_last_hp - me.health) / maxf(me.MAX_HEALTH, 1.0) * STRESS_PER_HP
		_since_hurt = 0.0
	_last_hp = me.health
	_lowest = minf(_lowest, share)
	var close = _enemies_on(me, CLOSE)
	if close > 2:	# swarmed (a straggler or two doesn't count)
		stress += minf(close - 2, 8) * STRESS_PER_CLOSE * delta
	elif _since_hurt >= CALM_AFTER:
		stress -= STRESS_DRAIN * (2.0 if state == State.CALM else 1.0) * delta
	if share < LOW_HEALTH:
		stress = PEAK
	stress = clampf(stress, 0.0, PEAK)


func _enemies_on(me, radius: float) -> int:
	var n = 0
	for e in Zones.all(self, "enemy"):
		if e.aggroed and e.global_position.distance_to(me.global_position) <= radius:
			n += 1
	return n


func _start_build_up():
	state = State.BUILD_UP
	stress = minf(stress, 20.0)	# every build-up starts fresh
	_wave = 0
	_build_time = 0.0
	_lowest = 1.0
	_t = 2.0	# first horde right away
	GameState.notify("Something's coming... a horde!")
	print("Director: build-up (strength %.2f)" % strength)


func _peak():
	state = State.FIGHT_OUT
	_t = 30.0	# at most this long before calm, even if a few stragglers are left
	# Adapt: easy peak -> bigger next time; a close call -> smaller
	if _wave == 0:
		pass	# peaked before any horde (already swarmed): no change
	elif _lowest < 0.25:
		strength = maxf(STRENGTH_RANGE.x, strength * 0.85)
	elif _lowest > 0.5:
		strength = minf(STRENGTH_RANGE.y, strength * 1.15)
	print("Director: peak after %d hordes (lowest health %d%%, next strength %.2f)" % [_wave, roundi(_lowest * 100), strength])


func _calm():
	state = State.CALM
	_t = CALM_TIME
	GameState.notify("It's quiet... for now.")
	print("Director: calm")


func _send_horde(me):
	if horde_alive >= MAX_HORDE_ALIVE:
		return
	var spots = _horde_doors(me, randi_range(SWARMS_PER_WAVE.x, SWARMS_PER_WAVE.y))
	if spots.is_empty():
		var open = _offscreen_spot(me)	# no buildings around: out of the open, like before
		if open == null:
			return	# nowhere hidden right now: next time
		spots = [open]
	_wave += 1
	var size = mini(roundi((BASE_WAVE + WAVE_GROW * (_wave - 1)) * strength), MAX_HORDE_ALIVE - horde_alive)
	var d = zone._difficulty()
	var tiers = []
	if _wave >= 2:
		tiers.append(1)	# a Thug leads from the 2nd horde on (the "special")
	if _wave % 3 == 0:
		tiers.append(2)	# every 3rd horde: a Master too
	while tiers.size() < size:
		tiers.append(0)
	tiers.shuffle()
	for k in range(tiers.size()):
		var t = tiers[k]
		var center = spots[k % spots.size()]	# split the horde between the buildings
		for attempt in range(6):
			var a = randf() * TAU
			var p = center + Vector2(cos(a), sin(a)) * randf_range(0.3, 2.5)
			if not REAL_MAP._inside_building(zone.info.data, p) and absf(p.x) < REAL_MAP.HALF_SIZE - 2.0 and absf(p.y) < REAL_MAP.HALF_SIZE - 2.0:
				_spawn(t, p, d)
				break


func _spawn(tier: int, p: Vector2, d: Array):
	var e = ENEMY_SCENE.instantiate()
	e.defeated.connect(func(_tier): horde_alive -= 1)	# died or turned
	zone.add_child(e)
	e.global_position = Vector3(p.x, 1.2, p.y)
	e.setup(d[0], tier, Crafting.roll_enemy_element(d[1], false))
	e.horde = self			# follows the route map: straight at you, around buildings when it must
	e.aggroed = true
	e.hunter = true			# comes straight for you, never gives up
	horde_alive += 1


# ---------------- Route map (one for the whole horde) ----------------

## Steps from every open square near you to you (breadth-first), so each horde enemy
## only has to look at its neighbors. Open ground = a straight charge.
func _build_flow(me):
	var world = zone.get_world_3d()
	var space = world.direct_space_state
	PATHING._use_memory(world)
	var solid = PATHING._solid	# looked up directly: this runs ~20,000 times per map
	var blocked = func(c: Vector2i) -> bool: return solid[c] if solid.has(c) else PATHING._is_solid(space, c)
	var start = PATHING.cell_of(me.global_position)
	_flow_start = start
	_clear = {}
	_flow = {start: 0}
	var queue = [start]
	var i = 0
	while i < queue.size():
		var c = queue[i]
		i += 1
		var d = _flow[c] + 1
		for n in NEIGHBORS:
			var c2 = c + n
			if _flow.has(c2) or absi(c2.x - start.x) > FLOW_RADIUS or absi(c2.y - start.y) > FLOW_RADIUS:
				continue
			if blocked.call(c2):
				continue
			if n.x != 0 and n.y != 0 and (blocked.call(c + Vector2i(n.x, 0)) or blocked.call(c + Vector2i(0, n.y))):
				continue	# don't cut a building's corner
			_flow[c2] = d
			queue.append(c2)


## Where a horde enemy at `pos` should head next (enemy.gd asks every frame).
func next_point(pos: Vector3, goal: Vector3) -> Vector3:
	var c = PATHING.cell_of(pos)
	if not _flow.has(c) or _flow[c] <= 1 or _straight(c):
		return goal		# open ground (or off the map / right next to you): straight at you
	var best = c
	var best_d = _flow[c]
	for n in NEIGHBORS:
		var d = _flow.get(c + n, 1 << 30)
		if d < best_d:
			best = c + n
			best_d = d
	return Vector3((best.x + 0.5) * PATHING.CELL, pos.y, (best.y + 0.5) * PATHING.CELL)


## Nothing but open squares on a straight line from c to you? (worked out once per square per map)
func _straight(c: Vector2i) -> bool:
	if _clear.has(c):
		return _clear[c]
	var steps = maxi(absi(c.x - _flow_start.x), absi(c.y - _flow_start.y))
	var ok = true
	for k in range(1, steps):
		var t = float(k) / steps
		var q = Vector2i(roundi(lerpf(c.x, _flow_start.x, t)), roundi(lerpf(c.y, _flow_start.y, t)))
		if not _flow.has(q):	# a building (or unreachable) square is in the way
			ok = false
			break
	_clear[c] = ok
	return ok


## Up to n building doors around you, off-screen, spread out (not all from one side).
func _horde_doors(me, n: int) -> Array:
	var cam = get_viewport().get_camera_3d()
	var mp = Vector2(me.global_position.x, me.global_position.z)
	var cands = []
	for d in _doors:
		var dist = d.p.distance_to(mp)
		if dist < SPAWN_DIST.x or dist > SPAWN_DIST.y + 10.0:
			continue
		if cam and cam.is_position_in_frustum(Vector3(d.p.x, 1.2, d.p.y)):
			continue
		cands.append(d.p)
	cands.shuffle()
	var out = []
	for p in cands:
		if out.any(func(q): return q.distance_to(p) < 15.0):
			continue	# different buildings, different directions
		out.append(p)
		if out.size() >= n:
			break
	for p in out:	# a puff of dust at each door, so you see where they came from (if you look)
		_dust(Vector3(p.x, 0.5, p.y))
	return out


func _dust(at: Vector3):
	var mi = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 1.6
	sm.height = 2.0
	mi.mesh = sm
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.45, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	zone.add_child(mi)
	mi.global_position = at
	var tw = mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.5, 1.2)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 1.2)
	tw.tween_callback(mi.queue_free)


## Somewhere around you that's out of sight (off the screen) and not inside a building.
func _offscreen_spot(me):
	var cam = get_viewport().get_camera_3d()
	var mp = me.global_position
	for i in range(16):
		var a = randf() * TAU
		var p = Vector2(mp.x, mp.z) + Vector2(cos(a), sin(a)) * randf_range(SPAWN_DIST.x, SPAWN_DIST.y)
		if absf(p.x) > REAL_MAP.HALF_SIZE - 5.0 or absf(p.y) > REAL_MAP.HALF_SIZE - 5.0:
			continue
		if REAL_MAP._inside_building(zone.info.data, p):
			continue
		if cam and cam.is_position_in_frustum(Vector3(p.x, 1.2, p.y)):
			continue
		return p
	return null
