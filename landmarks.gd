extends Node
## Autoload "Landmarks": big set pieces in Zone 4 and up (design: claude/Landmarks.md).
##
##   Stronghold  (Keep / Barricaded Mall / Outpost)   take it: it becomes a forward camp
##   Neutral town (Free Town / Safe Zone / Trade Hub)  no fighting inside; trader, quest board, rest
##   Cavern      (Cave / Subway Tunnels / Mine Shaft)  a dark party dungeon with geodes and rare ore
##   Event town  (Market / Survivor Camp / Convoy)     defend it from a raid for 3 minutes
##   Monument    (Fallen Statue / Crashed Airliner / Derelict Satellite)  seen from afar; shrines nearby
##   Rift        (Dark Rift / Nest / Spawning Hive)    keeps spawning foes until its guardians fall
##
## Where they go is worked out from the zone (seeded), so everyone sees the same world every visit.
## What happened to them (taken, closed, fallen...) is saved with your PARTY (party.gd), or with you
## when playing solo (user://landmarks.cfg). The host runs the fights; joined players see the results.

const LAYOUT = preload("res://world_layout.gd")
const SAVE_PATH = "user://landmarks.cfg"
const FIRST_ZONE = 4			# landmarks start in Zone 4
const AREA_EACH = 120000.0		# one more landmark per this much floor (Zone 4: 2, Zone 5: 5, Zone 6+: 8)
const MAX_PER_ZONE = 8
const DISCOVER_RANGE = 70.0

const SIZE = {stronghold = 38.0, town = 44.0, event_town = 24.0, cavern = 14.0, monument = 18.0, rift = 28.0}
const SCRIPT = {
	stronghold = "res://lm_stronghold.gd", town = "res://lm_town.gd", event_town = "res://lm_event_town.gd",
	cavern = "res://lm_cavern.gd", monument = "res://lm_monument.gd", rift = "res://lm_rift.gd",
}
const MIN_ZONE = {stronghold = 4, monument = 4, event_town = 4, cavern = 5, town = 6, rift = 7}

# Names per world look (a skin can override any of these with names.lm_<word>)
const WORDS = {
	"fantasy": {stronghold = "Keep", camp = "Forward Camp", town = "Free Town", event_town = "Market",
		cavern = "Cave", monument = "Fallen Statue", rift = "Dark Rift", heart = "Town Well",
		warden = "Warden", guardian = "Rift Guardian", trader = "Trader", board = "Quest Board"},
	"zombie": {stronghold = "Barricaded Mall", camp = "Survivor Base", town = "Safe Zone", event_town = "Survivor Camp",
		cavern = "Subway Tunnels", monument = "Crashed Airliner", rift = "Nest", heart = "Camp Generator",
		warden = "Raider Boss", guardian = "Nest Guardian", trader = "Scavenger", board = "Notice Wall"},
	"scifi": {stronghold = "Outpost", camp = "Forward Base", town = "Trade Hub", event_town = "Trade Convoy",
		cavern = "Mine Shaft", monument = "Derelict Satellite", rift = "Spawning Hive", heart = "Convoy Core",
		warden = "Commander", guardian = "Hive Guardian", trader = "Quartermaster", board = "Job Terminal"},
}
const NAME_A = ["Black", "Iron", "Grey", "Storm", "Red", "Hollow", "Ash", "Raven", "Thorn", "Frost", "Gold", "Bright", "Wolf", "Salt", "Ember"]
const NAME_B = ["water", "stone", "hold", "fall", "crag", "moor", "gate", "ridge", "ford", "watch", "brook", "reach", "mere"]

var _personal := {}		# solo: "path|id" -> state
var _quests := []		# your quest board jobs (always yours, even in a party)
var _safe := {}			# zone key -> [[center, radius]] (neutral towns)


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_personal = cfg.get_value("landmarks", "state", {})
		_quests = cfg.get_value("landmarks", "quests", [])


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("landmarks", "state", _personal)
	cfg.set_value("landmarks", "quests", _quests)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Landmarks: couldn't save " + SAVE_PATH)


func word(w: String) -> String:
	var n = SkinManager.name_of("lm_" + w)
	if n != "lm_" + w:
		return n
	return WORDS.get(SkinManager.props_style(), WORDS.fantasy).get(w, w)


func zone_number(path: String) -> int:
	return GameState.ZONE_ORDER.find(path) + 1


# ---------------- Where they are ----------------

## The landmarks of a zone: [{id, kind, pos, size, name}]. Same every time for the same zone.
var _cache := {}

func for_zone(path: String) -> Array:
	var ck = path + SkinManager.current_id
	if _cache.has(ck):
		return _cache[ck]
	_cache[ck] = _place(path)
	return _cache[ck]


func _place(path: String) -> Array:
	var n = zone_number(path)
	if n < FIRST_ZONE or not LAYOUT.ZONES.has(path):
		return []
	var half = LAYOUT.half_size(path)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(path + "landmarks")
	var count = clampi(roundi(half.x * half.y * 4.0 / AREA_EACH) + 1, 2, MAX_PER_ZONE)
	# Always one stronghold; a town from Zone 6, a cavern from 5, a rift from 7; then a mix
	var kinds = ["stronghold"]
	for k in ["town", "cavern", "rift", "monument", "event_town"]:
		if n >= MIN_ZONE[k] and kinds.size() < count:
			kinds.append(k)
	var allowed = SIZE.keys().filter(func(k): return n >= MIN_ZONE[k])
	while kinds.size() < count:
		kinds.append(allowed[rng.randi() % allowed.size()])
	var avoid = []	# gates and fast-travel stops
	for g in LAYOUT.gates(path):
		avoid.append([g.pos, 70.0])
	for s in Travel.grid_stations(path):
		avoid.append([s.pos, 40.0])
	var out = []
	for i in kinds.size():
		var k = kinds[i]
		var r = SIZE[k]
		var margin = r + 40.0
		for attempt in 300:
			var p = Vector3(rng.randf_range(-half.x + margin, half.x - margin), 0, rng.randf_range(-half.y + margin, half.y - margin))
			if p.length() < 50.0:	# keep the very middle open
				continue
			if avoid.any(func(a): return a[0].distance_to(p) < a[1] + r):
				continue
			if out.any(func(o): return o.pos.distance_to(p) < o.size + r + 90.0):
				continue
			var nm = "%s%s %s" % [NAME_A[rng.randi() % NAME_A.size()], NAME_B[rng.randi() % NAME_B.size()], word(k)]
			out.append({id = "%s%d" % [k, i], kind = k, pos = p, size = r, name = nm, zone = n})
			break
	return out


## Where a landmark's fast-travel stop is (null: it has none).
func station_spot(l: Dictionary):
	var inward = -Vector3(l.pos.x, 0, l.pos.z).normalized()
	match l.kind:
		"stronghold", "town": return l.pos + inward * 14.0
		"monument", "cavern": return l.pos + inward * (l.size + 10.0)
	return null


func station_label(l: Dictionary) -> String:
	return ("%s (%s)" % [word("camp"), l.name]) if l.kind == "stronghold" else l.name


## Which way a landmark faces (its gate / entrance): toward the middle of the zone.
func facing(l: Dictionary) -> Vector3:
	return -Vector3(l.pos.x, 0, l.pos.z).normalized()


## Is this spot inside a landmark (so terrain and enemies stay out)? pad = extra room.
func blocks(path: String, p: Vector3, pad := 0.0) -> bool:
	for l in for_zone(path):
		if Vector2(p.x - l.pos.x, p.z - l.pos.z).length() < l.size + pad:
			return true
	return false


## Put a zone's landmarks in (spiral_floor.gd calls this).
func build(floor_node, path: String):
	_safe.erase(Zones.key_of(floor_node))	# fresh list for this visit
	for l in for_zone(path):
		var node = Node3D.new()
		node.set_script(load(SCRIPT[l.kind]))
		node.info = l
		node.zone_path = path
		node.name = l.id
		node.position = l.pos
		floor_node.add_child(node)


# ---------------- What happened to them (party or personal) ----------------

func _key(path: String, id: String) -> String:
	return "%s|%s" % [path, id]


func state(path: String, id: String) -> Dictionary:
	var k = _key(path, id)
	if Party.active():
		return Party.current.get("landmarks", {}).get(k, {})
	return _personal.get(k, {})


## Merge new facts into a landmark's state (host or solo; joined players' games ask the host).
func set_state(path: String, id: String, changes: Dictionary):
	var k = _key(path, id)
	if Party.active():
		if Net.is_client():
			Net.landmark_state(path, id, changes)
			return
		if not Party.current.has("landmarks"):
			Party.current.landmarks = {}
		var s = Party.current.landmarks.get(k, {})
		s.merge(changes, true)
		Party.current.landmarks[k] = s
		Party.save()
		Net.send_party(Party.current)
	else:
		var s = _personal.get(k, {})
		s.merge(changes, true)
		_personal[k] = s
		_save()


func who() -> Array:
	var names = [Story.player_name]
	if Net.is_online():
		for o in Net.others():
			names.append(o[1])
	return names


# ---------------- Safe ground (neutral towns) ----------------

func add_safe(zone_key: String, center: Vector3, radius: float):
	if not _safe.has(zone_key):
		_safe[zone_key] = []
	_safe[zone_key].append([center, radius])


## Enemies call this: no fighting inside a neutral town.
func in_safe(node) -> bool:
	var list = _safe.get(Zones.key_of(node), [])
	for s in list:
		if Vector2(node.global_position.x - s[0].x, node.global_position.z - s[0].z).length() < s[1]:
			return true
	return false


func safe_center(node):
	for s in _safe.get(Zones.key_of(node), []):
		return s[0]
	return null


# ---------------- Quests (from quest boards in neutral towns) ----------------

## Today's offers at a town: 3 jobs, the same all day.
func offers(path: String, town_id: String) -> Array:
	var n = zone_number(path)
	var q = GameState.zone_quality(path)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(path + town_id + Time.get_date_string_from_system())
	var res = ["ore", "herb", "treesilver", "orchid"][rng.randi() % 4]
	var count = 10 + rng.randi() % 11
	var tier = rng.randi() % 2
	var kills = (30 if tier == 0 else 8) * (1 + n / 4)
	var out = [
		{id = "gather", kind = "gather", res = res, q = q, need = count,
			text = "Bring %d %s" % [count, GameState.resource_name(res, q)], gold = 8 * count * n / 4},
		{id = "hunt", kind = "hunt", tier = tier, need = kills, zone = path,
			text = "Defeat %d %s in %s" % [kills, SkinManager.name_of(["enemy_trash", "enemy_thug"][tier]).to_lower(), GameState.ZONE_NAMES.get(path, path)], gold = kills * (3 if tier == 0 else 10)},
	]
	for l in for_zone(path):
		if l.kind in ["stronghold", "rift", "cavern"]:
			var done = state(path, l.id)
			if done.has("taken") or done.has("closed") or done.has("cleared"):
				continue
			var verb = {"stronghold": "Take", "rift": "Close", "cavern": "Clear out"}[l.kind]
			out.append({id = "lm_" + l.id, kind = "landmark", lm = l.id, zone = path, need = 1,
				text = "%s %s" % [verb, l.name], gold = 120 * n})
			break
	for o in out:
		o.key = "%s|%s|%s|%s" % [path, town_id, Time.get_date_string_from_system(), o.id]
	return out


func quests() -> Array:
	return _quests


func has_quest(key: String) -> bool:
	return _quests.any(func(q): return q.key == key)


func accept(o: Dictionary):
	if has_quest(o.key) or _quests.size() >= 5:
		GameState.notify("You can carry up to 5 jobs at once." if _quests.size() >= 5 else "Already taken.")
		return
	var q = o.duplicate()
	q.have = 0
	_quests.append(q)
	_save()
	GameState.notify("Job taken: " + q.text)


## Gather jobs: hand the resources over from your satchel.
func deliver(q: Dictionary) -> bool:
	var key = "%s:%d" % [q.res, q.q]
	var have = GameState.satchel.get(key, 0)
	if have < q.need:
		GameState.notify("You have %d of %d." % [have, q.need])
		return false
	GameState.satchel[key] -= q.need
	if GameState.satchel[key] <= 0:
		GameState.satchel.erase(key)
	GameState.save_progress()
	q.have = q.need
	_finish(q)
	return true


## Hunt jobs: count kills (Story.on_kill path: enemy.gd -> here).
func on_kill(enemy):
	var path = Zones.path_of(enemy)
	var changed = false
	for q in _quests:
		if q.kind == "hunt" and q.zone == path and "tier" in enemy and enemy.tier == q.tier and q.have < q.need:
			q.have += 1
			changed = true
			if q.have >= q.need:
				GameState.notify("Job done: %s. Collect at any %s." % [q.text, word("board")])
	if changed:
		_save_later = true


## Landmark jobs: done when that landmark is taken/closed/cleared.
func refresh_landmark_jobs():
	for q in _quests:
		if q.kind == "landmark" and q.have < q.need:
			var s = state(q.zone, q.lm)
			if s.has("taken") or s.has("closed") or s.has("cleared"):
				q.have = q.need
				GameState.notify("Job done: %s. Collect at any %s." % [q.text, word("board")])
	_save()


func ready_to_collect(q: Dictionary) -> bool:
	return q.have >= q.need


func collect(q: Dictionary):
	if q.kind == "gather":
		deliver(q)
		return
	if not ready_to_collect(q):
		return
	_finish(q)


func _finish(q: Dictionary):
	_quests.erase(q)
	GameState.gold_banked += q.gold
	GameState.save_progress()
	GameState.gold_changed.emit()
	_save()
	GameState.notify("Paid %d gold (banked) for: %s" % [q.gold, q.text])
	Story.add("Did a job for the townsfolk: %s." % q.text)
	Traits.nudge("bond", 2.0, "helped the townsfolk")


var _save_later := false
var _t := 0.0

func _process(delta):
	_t += delta
	if _t > 5.0:
		_t = 0.0
		if _save_later:
			_save_later = false
			_save()
