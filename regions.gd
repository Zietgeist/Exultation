extends Node
## Autoload "Regions": what makes the huge zones interesting (design: guide.json "Regions", "Encounters").
##
##   REGIONS (zones REGION_SIDE wide and up: Zone 7 = 2 x 2, Zone 8 = 3 x 3, Zone 9 = 5 x 5, Zone 10 = 8 x 8)
##     The zone is cut into a grid of squares about REGION_SIZE across (~1.5 minutes to walk).
##     Each region has a name ("the Ashen Fells"), its own map type (terrain_generator builds each square
##     from its region's template), its own damage type (enemies there often use it), and a HEART:
##     a set piece around a beacon where the region's boss waits (region_heart.gd, zone_features.gd).
##   ENCOUNTERS (zones BIG_SIDE wide and up: Zone 6 and up)
##     Small things about every POI_SPACING (~30 s of walking): supply caches, story stones,
##     champions with escorts, ambushes (zone_features.gd, poi_node.gd).
##
## Everything here is worked out from the zone (seeded), like landmarks and fast-travel stops, so
## every player sees the same world on every visit and nothing needs sending online.
##
## SAVED PROGRESS (big zones): freed regions and a beaten 1st boss last between play sessions, with
## your party (online) or with you (solo). A freed region stays free: next visit its packs are gone and
## its share still counts toward the 2nd boss. Clearing the zone (both bosses) resets it: the enemies
## regroup, so the zone is a fresh battlefield again. Regions you've walked into stay named on the map.
## Positions are in the zone's own coordinates (its center is 0, 0).

const LAYOUT = preload("res://world_layout.gd")
const MAPS = preload("res://map_templates.gd")

const REGION_SIDE = 1500.0		# zones at least this wide get regions (Zone 7 and up)
const REGION_SIZE = 900.0		# about this wide each
const BIG_SIDE = 1000.0			# zones at least this wide get encounters and the horde director (Zone 6 and up)
const HEART_RADIUS = 40.0		# a heart's set piece fits in this circle (terrain and packs stay out)
const POI_SPACING = 260.0		# one encounter about every 30 seconds of walking
const POI_KINDS = {cache = 30, champion = 25, ambush = 20, stone = 25}	# how often each kind shows up (weights)
const ROAD_HALF_WIDTH = 4.0		# same as terrain_generator.gd

## Fallback names (the skins say these: "regions": {"adjectives": [...], "nouns": {template: [...]}}).
const ADJ = ["Ashen", "Hollow", "Bleak", "Silent", "Sunken", "Broken", "Red", "Grey", "Pale", "Iron", "Thorn",
	"Raven", "Ember", "Frost", "Gloom", "Bright", "Wild", "Lost", "Old", "Salt", "Storm", "Black", "Gold",
	"Far", "Weeping", "Burnt", "Shivering", "Howling", "Crooked", "Bitter", "Drowned", "Whispering"]
const NOUNS = {
	"open_field": ["Fields", "Meadows", "Plains", "Pastures"],
	"rolling_hills": ["Downs", "Fells", "Heights", "Hills"],
	"forest": ["Woods", "Weald", "Thicket", "Wildwood"],
	"river": ["Marsh", "Fens", "Wetlands", "Shallows"],
	"ruins": ["Ruins", "Remnants", "Wreckage", "Rubble"],
	"rails": ["Yards", "Junction", "Sidings", "Depot"],
}
const EPITHETS = ["Bold", "Cruel", "Grim", "Swift", "Mad", "Hungry", "Old", "Scarred", "Tall", "Silent", "Red-Eyed", "Unbroken"]

## Story stones. Tokens: {region} {zone} {trash} {thug} {master} {boss} (names from the skin).
const LORE = [
	"Here the last free folk of {region} held the line for nine days. On the tenth, the {trash} came over the hill.",
	"Carved in a shaky hand: \"The {boss} sleeps lightly. Walk softly in {zone}.\"",
	"A list of names, most of them scratched out. The last one is still fresh.",
	"\"We buried the silver where the beacon burns. Whoever reads this: it's yours now.\"",
	"The {master} came at dusk and asked for nothing. That was the worst part.",
	"A map of {region}, drawn before the {thug} came. The roads on it are gone.",
	"\"Don't follow the lights. The lights follow YOU.\"",
	"Someone kept count of the days here. The marks stop at four hundred and twelve.",
	"A child's drawing of a {boss}, with a tiny figure standing in front of it, holding a stick.",
	"\"If you made it this far, you're braver than we were. Keep going.\"",
	"Old warning, half worn away: \"...never rest in {region} after dark...\"",
	"\"Here lies Old Bram, who fed the {trash} to the river. The river spat him back.\"",
	"A traveler's note: \"Three days through {region} and not one friendly face. Then I met the beacon-keeper.\"",
	"\"Every {thug} you see was once a {trash} that won. Remember that.\"",
	"Carved deep: \"WE WERE HERE FIRST.\"",
	"\"The heart of {region} still beats. Take it back and the land will breathe again.\"",
]

var _cache := {}		# path + skin -> {grid, regions, pois}
var done := {}			# YOUR finished encounters this play session: "path|id" -> true (caches, stones)
var entered := {}		# regions you've walked into (saved): "path|region id" -> true
var _personal := {}		# solo progress (saved): path -> {freed = {region id: date}, bosses = 0}

var SAVE_PATH: String:	# this character's save (Account)
	get:
		return Account.path("regions.cfg")


func _ready():
	load_character()


func load_character():
	done = {}
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		entered = cfg.get_value("regions", "entered", {})
		_personal = cfg.get_value("regions", "progress", {})
	else:
		entered = {}
		_personal = {}


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("regions", "entered", entered)
	cfg.set_value("regions", "progress", _personal)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Regions: couldn't save " + SAVE_PATH)


# ---------------- Saved progress (party or personal) ----------------

## {freed = {region id: date}, bosses = n} for a zone (the party's when playing with friends).
func progress(path: String) -> Dictionary:
	if Party.active():
		return Party.current.get("regions", {}).get(path, {})
	return _personal.get(path, {})


func freed(path: String) -> Dictionary:
	return progress(path).get("freed", {})


func bosses_down(path: String) -> int:
	return int(progress(path).get("bosses", 0))


## Host or solo: remember a freed region / a beaten zone boss. Joined players' games leave it to the host.
func record(path: String, freed_id := "", bosses := -1):
	if Party.active() and Net.is_client():
		return
	var p = progress(path).duplicate(true)
	if freed_id != "":
		var f = p.get("freed", {})
		f[freed_id] = Time.get_date_string_from_system()
		p.freed = f
	if bosses >= 0:
		p.bosses = bosses
	if bosses >= 2:	# zone cleared: it resets, the enemies regroup for next time
		p = {}
	_store(path, p)


func _store(path: String, p: Dictionary):
	if Party.active():
		if not Party.current.has("regions"):
			Party.current.regions = {}
		Party.current.regions[path] = p
		Party.save()
		Net.send_party(Party.current)
	else:
		_personal[path] = p
		_save()


## You walked into a region (saved, so the map keeps its name).
func mark_entered(path: String, id: String):
	entered[path + "|" + id] = true
	_save()


# ---------------- Which zones get what ----------------

func _side(path: String) -> float:
	if not LAYOUT.ZONES.has(path) or path == "res://Home.tscn":
		return 0.0
	var s = LAYOUT.rect(path).size
	return minf(s.x, s.y)


func has_regions(path: String) -> bool:
	return _side(path) >= REGION_SIDE


func is_big(path: String) -> bool:
	return _side(path) >= BIG_SIDE


# ---------------- Regions ----------------

## The regions of a zone: [{id, i, cell, rect, heart, name, template, element, color}] ([] for smaller zones).
func for_zone(path: String) -> Array:
	return _data(path).regions


## {cols, rows, cell (Vector2 size), half} of the region grid (cols = 0 for zones without regions).
func grid(path: String) -> Dictionary:
	return _data(path).grid


## The region a spot is in ({} if the zone has none).
func at(path: String, pos: Vector3) -> Dictionary:
	var d = _data(path)
	var g = d.grid
	if g.cols == 0:
		return {}
	var cx = clampi(floori((pos.x + g.half.x) / g.cell.x), 0, g.cols - 1)
	var cz = clampi(floori((pos.z + g.half.y) / g.cell.y), 0, g.rows - 1)
	return d.regions[cz * g.cols + cx]


func by_id(path: String, id: String) -> Dictionary:
	for r in for_zone(path):
		if r.id == id:
			return r
	return {}


## Is this spot inside a region's heart? (terrain and packs keep out). pad = extra room.
func in_heart(path: String, p: Vector3, pad := 0.0) -> bool:
	for r in for_zone(path):
		if Vector2(p.x - r.heart.x, p.z - r.heart.z).length() < HEART_RADIUS + pad:
			return true
	return false


## Encounters of a zone: [{id, kind, pos, region}] ([] for smaller zones).
func pois_for_zone(path: String) -> Array:
	return _data(path).pois


func is_done(path: String, id: String) -> bool:
	return done.has(path + "|" + id)


func mark_done(path: String, id: String):
	done[path + "|" + id] = true


## A region's label with "the": "the Ashen Fells".
func the(r: Dictionary) -> String:
	return "the " + r.name if not r.is_empty() else ""


func template_label(r: Dictionary) -> String:
	return MAPS.label(r.template) if not r.is_empty() else ""


## A story stone's words for this encounter (same every time).
func lore(path: String, poi: Dictionary) -> String:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(path + poi.id + "lore")
	var text = LORE[rng.randi() % LORE.size()]
	var r = at(path, poi.pos)
	var words = {
		"region": r.name if not r.is_empty() else GameState.ZONE_NAMES.get(path, "these lands"),
		"zone": GameState.ZONE_NAMES.get(path, "these lands"),
		"trash": SkinManager.name_of("enemy_trash"), "thug": SkinManager.name_of("enemy_thug_one"),
		"master": SkinManager.name_of("enemy_master_one"), "boss": SkinManager.name_of("enemy_boss_one"),
	}
	for k in words:
		text = text.replace("{%s}" % k, words[k])
	return text


## "Grask the Grim"-style title for a champion (same every time for the same encounter).
func champion_title(path: String, poi: Dictionary, tier: int) -> String:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(path + poi.id + "champion")
	var ids = ["enemy_trash_one", "enemy_thug_one", "enemy_master_one"]
	return "%s the %s" % [SkinManager.name_of(ids[clampi(tier, 0, 2)]), EPITHETS[rng.randi() % EPITHETS.size()]]


func boss_title(r: Dictionary) -> String:
	return "%s Lord of %s" % [SkinManager.name_of("enemy_master_one"), the(r)]


# ---------------- Working it out (seeded) ----------------

func _data(path: String) -> Dictionary:
	var ck = path + "|" + SkinManager.current_id
	if not _cache.has(ck):
		_cache[ck] = _build(path)
	return _cache[ck]


func _build(path: String) -> Dictionary:
	var out = {grid = {cols = 0, rows = 0, cell = Vector2.ZERO, half = Vector2.ZERO}, regions = [], pois = []}
	if not is_big(path):
		return out
	var half = LAYOUT.half_size(path)
	var avoid = _avoid_list(path)
	var roads = _roads(path)
	if has_regions(path):
		var cols = maxi(2, roundi(half.x * 2.0 / REGION_SIZE))
		var rows = maxi(2, roundi(half.y * 2.0 / REGION_SIZE))
		out.grid = {cols = cols, rows = rows, cell = Vector2(half.x * 2.0 / cols, half.y * 2.0 / rows), half = half}
		out.regions = _make_regions(path, out.grid, avoid, roads)
	for r in out.regions:
		avoid.append([r.heart, HEART_RADIUS + 40.0])
	out.pois = _make_pois(path, half, avoid, roads, out)
	return out


## Spots everything must keep away from: gates, landmarks, fast-travel stops, the middle. [[pos, radius]]
func _avoid_list(path: String) -> Array:
	var avoid = [[Vector3.ZERO, 70.0]]
	for g in LAYOUT.gates(path):
		avoid.append([Vector3(g.pos.x, 0, g.pos.z), 70.0])
	for l in Landmarks.for_zone(path):
		avoid.append([l.pos, l.size + 30.0])
	for s in Travel.grid_stations(path):
		avoid.append([s.pos, 20.0])
	return avoid


func _clear_of(p: Vector3, avoid: Array, roads: Array, r: float) -> bool:
	for a in avoid:
		if Vector2(p.x - a[0].x, p.z - a[0].z).length() < a[1] + r:
			return false
	for seg in roads:
		var q = Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), seg[0], seg[1])
		if q.distance_to(Vector3(p.x, 0, p.z)) < ROAD_HALF_WIDTH + r:
			return false
	return true


## The gate roads, worked out the same way as terrain_generator.gd _plan_roads (gate -> middle,
## bending around landmarks), so hearts and encounters never sit on one.
func _roads(path: String) -> Array:
	var out = []
	for g in LAYOUT.gates(path):
		var pts = [Vector3(g.pos.x, 0, g.pos.z), Vector3.ZERO]
		for l in Landmarks.for_zone(path):
			var c = Vector3(l.pos.x, 0, l.pos.z)
			var room = l.size + 8.0 + ROAD_HALF_WIDTH + 2.0
			var a = pts[pts.size() - 2]
			var b = pts[pts.size() - 1]
			var close = Geometry3D.get_closest_point_to_segment(c, a, b)
			if close.distance_to(c) >= room:
				continue
			var along = (b - a).normalized()
			var side = Vector3(-along.z, 0, along.x)
			if (close - c).dot(side) < 0.0:
				side = -side
			pts.insert(pts.size() - 1, c + side * room)
		for i in range(pts.size() - 1):
			out.append([pts[i], pts[i + 1]])
	return out


func _make_regions(path: String, g: Dictionary, avoid: Array, roads: Array) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(path + "regions")
	var templates = MAPS.allowed().filter(func(t): return t != "island")	# an island sea is a whole-zone thing
	if templates.is_empty():
		templates = ["open_field"]
	var specials = Crafting.ZONE_ELEMENTS.get(path, []).filter(func(e): return e != "physical")
	if specials.is_empty():
		specials = Crafting.ELEMENTS.slice(1)
	var used_names = {}
	var words = _words()
	var out = []
	for cz in g.rows:
		for cx in g.cols:
			var i = out.size()
			var rect = Rect2(-g.half.x + cx * g.cell.x, -g.half.y + cz * g.cell.y, g.cell.x, g.cell.y)
			var template = templates[rng.randi() % templates.size()]
			if i > 0 and template == out[i - 1].template and templates.size() > 1:	# neighbors in a row differ more often
				template = templates[rng.randi() % templates.size()]
			var nouns = words.nouns.get(template, NOUNS.get(template, NOUNS.open_field))
			var nm = ""
			for attempt in 20:
				nm = "%s %s" % [words.adjectives[rng.randi() % words.adjectives.size()], nouns[rng.randi() % nouns.size()]]
				if not used_names.has(nm):
					break
			used_names[nm] = true
			var element = specials[rng.randi() % specials.size()]
			# Heart: somewhere in the middle 60% of the square, clear of gates, roads, landmarks and stops
			var inner = rect.grow(-minf(rect.size.x, rect.size.y) * 0.2)
			var heart = Vector3(inner.get_center().x, 0, inner.get_center().y)
			var placed = false
			for attempt in 200:
				var p = Vector3(rng.randf_range(inner.position.x, inner.end.x), 0, rng.randf_range(inner.position.y, inner.end.y))
				if _clear_of(p, avoid, roads, HEART_RADIUS + 10.0):
					heart = p
					placed = true
					break
			if not placed:
				ErrorLog.warn("Regions: no clear spot for the heart of %s in %s; using the middle of its square" % [nm, path])
			out.append({id = "r%d" % i, i = i, cell = Vector2i(cx, cz), rect = rect, heart = heart, name = nm,
				template = template, element = element, color = Crafting.ELEMENT_COLORS[element]})
	return out


## Region name words from the world skin (falls back to the lists above).
func _words() -> Dictionary:
	var w = SkinManager.section("regions")
	if not (w is Dictionary and w.get("adjectives") is Array and not w.adjectives.is_empty() and w.get("nouns") is Dictionary):
		ErrorLog.warn("Skin '%s' has no \"regions\" names (adjectives, nouns); using the built-in ones" % SkinManager.current_id)
		return {adjectives = ADJ, nouns = NOUNS}
	return w


func _make_pois(path: String, half: Vector2, avoid: Array, roads: Array, data: Dictionary) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(path + "encounters")
	var total = 0
	for k in POI_KINDS:
		total += POI_KINDS[k]
	var out = []
	var cols = maxi(1, floori(half.x * 2.0 / POI_SPACING))
	var rows = maxi(1, floori(half.y * 2.0 / POI_SPACING))
	var cw = half.x * 2.0 / cols
	var ch = half.y * 2.0 / rows
	for cz in rows:
		for cx in cols:
			var p = Vector3.ZERO
			var ok = false
			for attempt in 8:
				p = Vector3(-half.x + (cx + rng.randf_range(0.2, 0.8)) * cw, 0, -half.y + (cz + rng.randf_range(0.2, 0.8)) * ch)
				if absf(p.x) < half.x - 30.0 and absf(p.z) < half.y - 30.0 and _clear_of(p, avoid, roads, 14.0):
					ok = true
					break
			if not ok:
				continue
			var pick = rng.randi() % total
			var kind = "cache"
			for k in POI_KINDS:
				if pick < POI_KINDS[k]:
					kind = k
					break
				pick -= POI_KINDS[k]
			var rid = ""
			if data.grid.cols > 0:
				var gx = clampi(floori((p.x + half.x) / data.grid.cell.x), 0, data.grid.cols - 1)
				var gz = clampi(floori((p.z + half.y) / data.grid.cell.y), 0, data.grid.rows - 1)
				rid = data.regions[gz * data.grid.cols + gx].id
			out.append({id = "p%d" % out.size(), kind = kind, pos = p, region = rid})
	return out
