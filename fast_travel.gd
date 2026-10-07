extends Node
## Autoload "Travel": fast travel between waystations, so big zones aren't a long walk.
##
##   - Big zones (Zone 3 and up) have waystations: one just inside each gate, plus a grid across
##     the zone (about one every 200 units). Home has one too.
##   - Walk up to a waystation to wake it up (it's remembered). Step onto it to open the travel
##     list: any waystation you've found, in any zone you've unlocked, plus Home.
##   - Looks depend on the world (skin "fast_travel"):
##       portal  (Fantasy)  a standing stone ring
##       rail    (Zombie)   an elevated train stop; tracks on pillars run between the stops
##       tube    (Sci-Fi)   a transit pad; glass vacuum tubes run between the pads
##
## Station spots are worked out from world_layout.gd (not random), so they're the same every visit
## and you can travel to a zone that isn't loaded. Found stations are saved in user://travel.cfg.

const LAYOUT = preload("res://world_layout.gd")
const SAVE_PATH = "user://travel.cfg"
const MIN_ZONE_SIZE = 200.0		# zones smaller than this walk fine without stations
const GRID_SPACING = 200.0
const MAX_GRID = 6				# at most 6 x 6 stops in a zone (plus one by each gate)
const GATE_INSET = 16.0			# gate stations sit this far inside the gate
const HOME_SPOT = Vector3(-32, 0, 32)
const WAKE_RANGE = 10.0

var found := {}		# zone path -> [station ids]


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		found = cfg.get_value("travel", "found", {})


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("travel", "found", found)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Travel: couldn't save " + SAVE_PATH)


## How this world travels: "portal", "rail" or "tube".
func style() -> String:
	var s = SkinManager.section("fast_travel")
	if s is String:
		return s
	return {"zombie": "rail", "scifi": "tube"}.get(SkinManager.props_style(), "portal")


func station_name() -> String:
	return SkinManager.name_of("waystation")


## Every station in a zone: [{id, pos (zone coordinates), label}]. Same every time.
func stations_for(path: String) -> Array:
	if path == "res://Home.tscn":
		return [{id = "home", pos = HOME_SPOT, label = "Home"}]
	var out = grid_stations(path)
	var zname = GameState.ZONE_NAMES.get(path, path.get_file().get_basename())
	for l in Landmarks.for_zone(path):	# towns, monuments, caverns, and strongholds you've taken
		var spot = Landmarks.station_spot(l)
		if spot == null or (l.kind == "stronghold" and not Landmarks.state(path, l.id).has("taken")):
			continue
		out.append({id = "lm:" + l.id, pos = spot, label = "%s, %s" % [zname, Landmarks.station_label(l)]})
	return out


## The gate stops and the grid (no landmarks).
func grid_stations(path: String) -> Array:
	if not LAYOUT.ZONES.has(path) or path == "res://Home.tscn":
		return []
	var half = LAYOUT.half_size(path)
	if min(half.x, half.y) * 2.0 < MIN_ZONE_SIZE:
		return []
	var zname = GameState.ZONE_NAMES.get(path, path.get_file().get_basename())
	var out = []
	for g in LAYOUT.gates(path):
		var inward = -Vector3(g.pos.x, 0, g.pos.z).normalized()
		match g.side:
			"n": inward = Vector3(0, 0, 1)
			"s": inward = Vector3(0, 0, -1)
			"e": inward = Vector3(-1, 0, 0)
			"w": inward = Vector3(1, 0, 0)
		out.append({id = "gate:" + g.to.get_file().get_basename(), pos = g.pos + inward * GATE_INSET,
			label = "%s, by the %s gate" % [zname, GameState.ZONE_NAMES.get(g.to, "?")]})
	var nx = clampi(roundi(half.x * 2.0 / GRID_SPACING), 1, MAX_GRID)	# huge zones: stops farther apart
	var nz = clampi(roundi(half.y * 2.0 / GRID_SPACING), 1, MAX_GRID)
	for i in nx:
		for j in nz:
			var p = Vector3(-half.x + (i + 0.5) * half.x * 2.0 / nx, 0, -half.y + (j + 0.5) * half.y * 2.0 / nz)
			if out.any(func(s): return s.pos.distance_to(p) < 60.0):
				continue
			out.append({id = "grid:%d:%d" % [i, j], pos = p, label = "%s, %s" % [zname, _compass(p, half)]})
	return out


func _compass(p: Vector3, half: Vector2) -> String:
	var ns = "north" if p.z < -half.y * 0.33 else ("south" if p.z > half.y * 0.33 else "")
	var ew = "west" if p.x < -half.x * 0.33 else ("east" if p.x > half.x * 0.33 else "")
	if ns == "" and ew == "":
		return "center"
	return ns + ew if ns != "" and ew != "" else ns + ew


func is_found(path: String, id: String) -> bool:
	return path == "res://Home.tscn" or id in found.get(path, [])


func discover(path: String, id: String, label: String):
	if is_found(path, id):
		return
	if not found.has(path):
		found[path] = []
	found[path].append(id)
	_save()
	GameState.notify("%s found: %s. Step on it to travel." % [station_name(), label])
	Story.once("first_station", "Found your first %s. The long walks are over." % station_name().to_lower())


## Places you can go from here: [{path, id, pos, label}], Home first, then by zone.
func destinations() -> Array:
	var out = []
	for path in ["res://Home.tscn"] + GameState.ZONE_ORDER:
		if not GameState.is_unlocked(path) or not ResourceLoader.exists(path):
			continue
		for s in stations_for(path):
			if is_found(path, s.id):
				out.append({path = path, id = s.id, pos = s.pos, label = s.label})
	return out


## Go. Arrive next to the station, not on it (so the list doesn't pop right back up).
func go_to(d: Dictionary):
	var spot = d.pos + Vector3(0, 1, 5)
	Net.go(d.path, "", spot)
