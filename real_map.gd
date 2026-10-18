extends Node
## Real-world maps (PROTOTYPE). Address or "lat, lon" -> OpenStreetMap buildings, roads, parks, water -> 3D gray boxes.
## Map data (c) OpenStreetMap contributors (ODbL): credit must be shown on screen. Address search by LocationIQ.
## The LocationIQ key lives in res://geo_key.txt (git ignores it). Later the keys move to Ivan's server.
##
## OFF-LIMITS: we refuse a map if any of these are within SAFETY_RADIUS of the spot:
##   military areas, concentration / prison camps, battlefields, any place or memorial whose name/description
##   mentions an atrocity (BAD_NAME_WORDS), or a place on our own list (real_map_blocklist.json).
##   Ordinary memorials (veterans parks, war memorials, statues) do NOT block a map.
## PRIVACY: the address a player types is never saved, logged or sent to other players.

signal status(text: String)

const KEY_FILE = "res://geo_key.txt"
const BLOCKLIST_FILE = "res://real_map_blocklist.json"
const GEOCODE_URL = "https://us1.locationiq.com/v1/search?key=%s&q=%s&format=json&limit=1"
# Free public map servers: if one is busy or slow, try the next.
const OVERPASS_URLS = ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
const TRIES_PER_SERVER = 2	# a busy server (502/504/429) often answers a few seconds later
const RETRY_WAIT = 4.0
const USER_AGENT = "Exultation-prototype/0.1"
const HALF_SIZE = 300.0			# meters from the center to each edge: a 600 x 600 m map
const SAFETY_RADIUS = 1000.0	# refuse if an off-limits place is this close (meters)
const BAD_NAME_WORDS = "concentration camp|extermination|death camp|massacre|genocide|holocaust|mass grave|gulag|internment camp|konzentrationslager|vernichtungslager"
const LEVEL_HEIGHT = 3.2		# meters per floor when OSM only gives building:levels

var _http: HTTPRequest


func _ready():
	_http = HTTPRequest.new()
	_http.timeout = 90.0
	add_child(_http)


## The whole job. Returns {} if it couldn't (the status signal says why), else
## {name, buildings = [{pts, h}], roads = [{pts, w}], areas = [{pts, kind}]} in meters around (0, 0).
func load_place(query: String) -> Dictionary:
	var where = await _locate(query.strip_edges())
	if where.is_empty():
		return {}
	status.emit("Checking the area...")
	var safety = await _query(_safety_query(where.lat, where.lon), "off-limits check")
	if safety.is_empty():
		return {}
	var why = _off_limits(where.lat, where.lon, safety)
	if why != "":
		status.emit("Sorry, this place can't be used for a map.\nNearby: %s" % why)
		return {}
	status.emit("Downloading buildings and streets (can take 10-30 s)...")
	var data = await _query(_map_query(where.lat, where.lon), "map")
	if data.is_empty():
		return {}
	why = _off_limits(where.lat, where.lon, data)	# the map's own buildings too (a base inside the area)
	if why != "":
		status.emit("Sorry, this place can't be used for a map.\nNearby: %s" % why)
		return {}
	var out = _to_local(where.lat, where.lon, data)
	out.name = where.name
	return out


# ---------------- 1. Where is it? ----------------

func _locate(query: String) -> Dictionary:
	var m = RegEx.create_from_string("^(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)$").search(query)
	if m:	# "39.74, -104.99": no address search needed
		var lat = m.get_string(1).to_float()
		var lon = m.get_string(2).to_float()
		if absf(lat) > 85.0 or absf(lon) > 180.0:
			status.emit("Those coordinates are off the map. Use: latitude, longitude")
			return {}
		return {lat = lat, lon = lon, name = "%.4f, %.4f" % [lat, lon]}
	var key = _key()
	if key == "":
		return {}
	status.emit("Finding the address...")
	var err = _http.request(GEOCODE_URL % [key, query.uri_encode()], ["User-Agent: " + USER_AGENT])
	if err != OK:
		ErrorLog.fail("Real map: couldn't start the address search (error %d)" % err)
		status.emit("Couldn't start the address search.")
		return {}
	var r = await _http.request_completed
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		ErrorLog.warn("Real map: address search failed (result %d, HTTP %d)" % [r[0], r[1]])	# never log the address itself
		status.emit("Couldn't find that address." if r[1] == 404 else "Address search failed (HTTP %d). Check the key / internet." % r[1])
		return {}
	var j = JSON.parse_string(r[3].get_string_from_utf8())
	if typeof(j) != TYPE_ARRAY or j.is_empty():
		status.emit("Couldn't find that address.")
		return {}
	return {lat = str(j[0].lat).to_float(), lon = str(j[0].lon).to_float(), name = str(j[0].get("display_name", ""))}


## Plain words for why a download didn't finish (HTTP 0 means one of these).
func _result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS: return "answered with an error"
		HTTPRequest.RESULT_TIMEOUT: return "timed out"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE: return "couldn't connect"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: return "secure connection failed"
		HTTPRequest.RESULT_CONNECTION_ERROR: return "connection dropped"
	return "error %d" % result


func _key() -> String:
	if not FileAccess.file_exists(KEY_FILE):
		ErrorLog.fail("Real map: no geo_key.txt in the game folder (LocationIQ key)")
		status.emit("No map key found (geo_key.txt).")
		return ""
	return FileAccess.get_file_as_string(KEY_FILE).strip_edges()


# ---------------- 2. Download the area (and everything off-limits around it) ----------------

## Two small downloads instead of one big one (the free servers refused the big one):
## 1) everything that could make the place off-limits (1 km each way), checked BEFORE
## 2) the map itself (buildings, roads, parks, water).
## Name checks ("massacre"...) are done here on your PC, not on the server (much lighter for it).
func _safety_query(lat: float, lon: float) -> String:
	var a = "%f,%f,%f,%f" % _bbox(lat, lon, SAFETY_RADIUS)
	return """[out:json][timeout:40];
(
  nwr["landuse"="military"]({A});
  way["military"]({A});
  relation["military"]({A});
  nwr["amenity"="prison_camp"]({A});
  nwr["abandoned:amenity"="prison_camp"]({A});
  nwr["prison_camp"]({A});
  nwr["concentration_camp"]({A});
  nwr["historic"]({A});
  nwr["memorial"]({A});
);
out tags center;""".replace("{A}", a)


func _map_query(lat: float, lon: float) -> String:
	var b = "%f,%f,%f,%f" % _bbox(lat, lon, HALF_SIZE)
	return """[out:json][timeout:90];
(
  way["building"]({B});
  way["highway"]({B});
  way["leisure"~"^(park|garden|playground|pitch)$"]({B});
  way["landuse"~"^(grass|forest|meadow|recreation_ground|village_green)$"]({B});
  way["natural"~"^(water|wood)$"]({B});
);
out tags geom;""".replace("{B}", b)


## Send one query, trying each server (and a busy one twice). {} if they all fail.
func _query(q: String, what: String) -> Dictionary:
	var r = []
	var ok = false
	for i in range(OVERPASS_URLS.size()):
		for attempt in range(TRIES_PER_SERVER):
			if i > 0 or attempt > 0:
				status.emit("Map server busy, trying again (server %d of %d)..." % [i + 1, OVERPASS_URLS.size()])
			var err = _http.request(OVERPASS_URLS[i], ["User-Agent: " + USER_AGENT, "Content-Type: application/x-www-form-urlencoded"],
				HTTPClient.METHOD_POST, "data=" + q.uri_encode())
			if err != OK:
				ErrorLog.fail("Real map: couldn't start the %s download (error %d)" % [what, err])
				status.emit("Couldn't start the map download.")
				return {}
			r = await _http.request_completed
			ok = r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200
			if ok:
				break
			ErrorLog.warn("Real map: %s, server %d try %d failed (%s, HTTP %d): %s" % [what, i + 1, attempt + 1, _result_name(r[0]), r[1], _server_says(r[3])])
			if not (r[1] in [429, 502, 503, 504]):
				break	# not "busy": this server won't do better on a retry, try the next one
			await get_tree().create_timer(RETRY_WAIT).timeout
		if ok:
			break
	if not ok:
		status.emit("All map servers are busy (%s). Try again in a minute." % _result_name(r[0]))
		return {}
	var j = JSON.parse_string(r[3].get_string_from_utf8())
	if typeof(j) != TYPE_DICTIONARY or not j.has("elements"):
		ErrorLog.fail("Real map: the map server sent something unreadable (%s)" % what)
		status.emit("Map download failed (bad data).")
		return {}
	return j


## The error line from a map server's reply (they answer errors as a web page).
func _server_says(body: PackedByteArray) -> String:
	var text = body.get_string_from_utf8()
	var m = RegEx.create_from_string("Error</strong>:\\s*([^<]+)").search(text)
	if m:
		return m.get_string(1).strip_edges().substr(0, 200)
	return text.strip_edges().replace("\n", " ").substr(0, 120)


# ---------------- 3. Off-limits check ----------------

## "" = fine. Otherwise a short reason ("military area").
func _off_limits(lat: float, lon: float, data: Dictionary) -> String:
	for site in _blocklist():
		if _dist_m(lat, lon, float(site.lat), float(site.lon)) < float(site.radius_m) + SAFETY_RADIUS:
			return "a protected site"
	var bad_name = RegEx.create_from_string("(?i)(" + BAD_NAME_WORDS + ")")
	for e in data.elements:
		var t = e.get("tags", {})
		var area = e.get("type", "") != "node"	# small points (a recruiting office, a plaque) don't count; areas do
		if t.get("landuse", "") == "military" or (area and t.has("military")):
			return "a military area" + _named(t)
		if t.get("amenity", "") == "prison_camp" or t.get("abandoned:amenity", "") == "prison_camp" \
				or t.get("prison_camp", "") == "concentration_camp" or t.has("concentration_camp"):
			return "a camp site" + _named(t)
		if t.get("historic", "") == "battlefield":
			return "a battlefield" + _named(t)
		# Ordinary memorials (veterans, war memorials, statues) are fine. A memorial or place is only
		# off-limits if its words point at an atrocity (camp, massacre, genocide, mass grave...).
		for k in ["name", "name:en", "description", "inscription", "subject", "memorial:subject", "memorial:type", "memorial"]:
			if bad_name.search(str(t.get(k, ""))):
				return "an atrocity site or its memorial" + _named(t)
	return ""


## ": <name>" so testers can see WHAT blocked the map (a public place name, never the player's address).
func _named(t: Dictionary) -> String:
	return ": " + str(t.name) if t.has("name") else ""


func _blocklist() -> Array:
	if not FileAccess.file_exists(BLOCKLIST_FILE):
		ErrorLog.fail("Real map: real_map_blocklist.json is missing")
		return []
	var j = JSON.parse_string(FileAccess.get_file_as_string(BLOCKLIST_FILE))
	if typeof(j) != TYPE_DICTIONARY or typeof(j.get("sites")) != TYPE_ARRAY:
		ErrorLog.fail("Real map: real_map_blocklist.json is broken (needs {\"sites\": [...]})")
		return []
	return j.sites


# ---------------- 4. Lat/lon -> meters ----------------

## North is -Z (up on screen), east is +X.
func _to_local(lat0: float, lon0: float, data: Dictionary) -> Dictionary:
	var out = {buildings = [], roads = [], areas = []}
	for e in data.elements:
		if not e.has("geometry"):
			continue
		var t = e.get("tags", {})
		var pts = PackedVector2Array()
		for g in e.geometry:
			pts.append(_local(lat0, lon0, float(g.lat), float(g.lon)))
		var closed = pts.size() >= 4 and pts[0].distance_to(pts[pts.size() - 1]) < 0.01
		if t.has("building"):
			if closed:
				pts.remove_at(pts.size() - 1)
				out.buildings.append({pts = pts, h = _height(t)})
		elif t.has("highway"):
			out.roads.append({pts = pts, w = _road_width(str(t.highway))})
		elif closed:
			pts.remove_at(pts.size() - 1)
			out.areas.append({pts = pts, kind = "water" if t.get("natural", "") == "water" else "green"})
	return out


func _local(lat0: float, lon0: float, lat: float, lon: float) -> Vector2:
	return Vector2((lon - lon0) * 111320.0 * cos(deg_to_rad(lat0)), -(lat - lat0) * 110540.0)


func _bbox(lat: float, lon: float, half: float) -> Array:
	var dlat = half / 110540.0
	var dlon = half / (111320.0 * cos(deg_to_rad(lat)))
	return [lat - dlat, lon - dlon, lat + dlat, lon + dlon]	# south, west, north, east


func _dist_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	return _local(lat1, lon1, lat2, lon2).length()	# fine for short distances


func _height(t: Dictionary) -> float:
	if t.has("height"):
		var h = str(t.height).to_float()
		if h > 0.0:
			return h
	if t.has("building:levels"):
		var l = str(t["building:levels"]).to_float()
		if l > 0.0:
			return l * LEVEL_HEIGHT + 1.0
	match str(t.building):
		"garage", "garages", "shed", "carport", "roof":
			return 3.0
		"house", "detached", "semidetached_house", "bungalow":
			return 6.0
	return 8.0	# no info: a 2-3 floor building


func _road_width(kind: String) -> float:
	match kind:
		"motorway", "trunk", "primary":
			return 12.0
		"secondary", "tertiary":
			return 9.0
		"residential", "unclassified", "living_street", "service":
			return 6.0
	return 2.0	# footway, path, cycleway, steps...


# ---------------- 5. Build the 3D gray-box map ----------------

func build(data: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.name = "RealMap"
	# ground
	var g = HALF_SIZE * 2.6
	var ground = StaticBody3D.new()
	var gm = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(g, g)
	gm.mesh = plane
	gm.material_override = _mat(Color(0.55, 0.55, 0.5))
	ground.add_child(gm)
	var gc = CollisionShape3D.new()
	var gbox = BoxShape3D.new()
	gbox.size = Vector3(g, 0.2, g)
	gc.shape = gbox
	gc.position.y = -0.1
	ground.add_child(gc)
	root.add_child(ground)
	# parks and water (flat)
	for kind in ["green", "water"]:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any = false
		for a in data.areas:
			if a.kind == kind:
				any = _flat_polygon(st, a.pts, 0.02 if kind == "green" else 0.03) or any
		if any:
			_add_mesh(root, st.commit(), Color(0.35, 0.6, 0.3) if kind == "green" else Color(0.25, 0.45, 0.75), true)
	# roads (flat strips)
	var rs = SurfaceTool.new()
	rs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in data.roads:
		for i in range(r.pts.size() - 1):
			_strip(rs, r.pts[i], r.pts[i + 1], r.w, 0.05 if r.w > 3.0 else 0.06)
	if not data.roads.is_empty():
		_add_mesh(root, rs.commit(), Color(0.3, 0.3, 0.32), true)
	# buildings: one mesh + one collision shape for all of them
	if not data.buildings.is_empty():
		var bs = SurfaceTool.new()
		bs.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in data.buildings:
			_building(bs, b.pts, b.h)
		var mesh = bs.commit()
		_add_mesh(root, mesh, Color(0.8, 0.79, 0.76))
		var body = StaticBody3D.new()
		var col = CollisionShape3D.new()
		var shape = mesh.create_trimesh_shape()
		shape.backface_collision = true	# walls block from both sides, whichever way OSM drew them
		col.shape = shape
		body.add_child(col)
		root.add_child(body)
	return root


## A good place to stand: the middle, or the nearest road point that isn't inside a building.
func free_spot(data: Dictionary) -> Vector3:
	var best = Vector2.ZERO
	if _inside_building(data, best):
		var best_d = INF
		for r in data.roads:
			for p in r.pts:
				if p.length() < best_d and not _inside_building(data, p):
					best = p
					best_d = p.length()
	return Vector3(best.x, 1.5, best.y)


static func _inside_building(data: Dictionary, p: Vector2) -> bool:
	for b in data.buildings:
		if Geometry2D.is_point_in_polygon(p, b.pts):
			return true
	return false


func _building(st: SurfaceTool, pts: PackedVector2Array, h: float):
	var center = Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	# walls
	for i in range(pts.size()):
		var a = pts[i]
		var b = pts[(i + 1) % pts.size()]
		var d = b - a
		if d.length() < 0.01:
			continue
		var n = Vector3(d.y, 0, -d.x).normalized()
		if Vector3((a + b).x / 2.0 - center.x, 0, (a + b).y / 2.0 - center.y).dot(n) < 0.0:
			n = -n	# face outward
		for v in [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y), Vector3(a.x, 0, a.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y)]:
			st.set_normal(n)
			st.add_vertex(v)
	_flat_polygon(st, pts, h)	# roof


func _flat_polygon(st: SurfaceTool, pts: PackedVector2Array, y: float) -> bool:
	var idx = Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return false	# a shape OSM drew crossed over itself: skip its top
	for i in idx:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(pts[i].x, y, pts[i].y))
	return true


func _strip(st: SurfaceTool, a: Vector2, b: Vector2, w: float, y: float):
	var d = b - a
	if d.length() < 0.01:
		return
	var s = Vector2(-d.y, d.x).normalized() * w / 2.0
	for p in [a + s, b + s, b - s, a + s, b - s, a - s]:
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, y, p.y))


func _add_mesh(root: Node3D, mesh: Mesh, c: Color, flat := false):
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, flat)
	if flat:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## flat = roads, parks, water: no lighting (OSM draws them either way round, and lit from
## underneath they came out black).
func _mat(c: Color, flat := false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	if flat:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED	# OSM shapes come in either winding
	return m
