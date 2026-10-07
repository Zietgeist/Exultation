extends RefCounted
## Where every zone sits in the world (the Golden Ratio spiral), in world units (1 floor tile = 10).
## Rect2(x, z, width, depth): x grows east, z grows south. Home is at (0, 0).
##
## Gates between zones are worked out from this table: any two zones that share an edge get a gate
## in the middle of the shared part. So adding a zone here (and its scene) is enough to connect it.
## A gate is locked until the zone behind it is unlocked (door.gd).
##
##              +----------- Zone 6 (110 x 110) -----------+
##              |                                          |
##              +-------------+--------+-------------------+
##              |             | Zone 2 |                   |
##              |   Zone 5    +--+-----+      Zone 3       |
##              |  (68 x 68)  |Z1| Home|     (26 x 26)     |
##              |             +--+-----+-------------------+
##              |             |        Zone 4 (42 x 42)    |
##              +-------------+----------------------------+
## ...and on around: Zone 7 east (178 x 178), Zone 8 south (288), Zone 9 west (466),
## Zone 10 north (754 x 754 tiles = 7540 units: crossing it on foot takes over 12 minutes).

const ZONES = {
	"res://Home.tscn": Rect2(0, 0, 100, 100),
	"res://Zone1.tscn": Rect2(-60, 0, 60, 100),
	"res://Zone2.tscn": Rect2(-60, -160, 160, 160),
	"res://Zone3.tscn": Rect2(100, -160, 260, 260),
	"res://Zone4.tscn": Rect2(-60, 100, 420, 420),
	"res://Zone5.tscn": Rect2(-740, -160, 680, 680),
	"res://Zone6.tscn": Rect2(-740, -1260, 1100, 1100),
	"res://Zone7.tscn": Rect2(360, -1260, 1780, 1780),
	"res://Zone8.tscn": Rect2(-740, 520, 2880, 2880),
	"res://Zone9.tscn": Rect2(-5400, -1260, 4660, 4660),
	"res://Zone10.tscn": Rect2(-5400, -8800, 7540, 7540),
}

const GATE_WIDTH = 12.0


## Fog squares get bigger in huge zones (so there are never more than ~90,000 of them).
static func fog_cell(path: String) -> float:
	var r = rect(path)
	return max(4.0, max(r.size.x, r.size.y) / 300.0)


static func rect(path: String) -> Rect2:
	if not ZONES.has(path):
		ErrorLog.fail("world_layout: no rectangle for zone " + path)
		return Rect2(0, 0, 100, 100)
	return ZONES[path]


## Half the zone's size (x, z): the floor spans -half .. +half around the zone's center.
static func half_size(path: String) -> Vector2:
	return rect(path).size / 2.0


## Gates in this zone, in the zone's own coordinates (its center is 0, 0):
## [{side "n"/"s"/"e"/"w", to (scene path), pos (Vector3 on the wall), along (offset along the wall)}]
static func gates(path: String) -> Array:
	var me = rect(path)
	var c = me.get_center()
	var out = []
	for other in ZONES:
		if other == path:
			continue
		var o = ZONES[other]
		var g = null
		if is_equal_approx(o.end.y, me.position.y):	# other is north of me
			g = _span(me.position.x, me.end.x, o.position.x, o.end.x)
			if g != null:
				out.append({side = "n", to = other, along = g - c.x, pos = Vector3(g - c.x, 0, -me.size.y / 2.0)})
		elif is_equal_approx(o.position.y, me.end.y):	# south
			g = _span(me.position.x, me.end.x, o.position.x, o.end.x)
			if g != null:
				out.append({side = "s", to = other, along = g - c.x, pos = Vector3(g - c.x, 0, me.size.y / 2.0)})
		elif is_equal_approx(o.end.x, me.position.x):	# west
			g = _span(me.position.y, me.end.y, o.position.y, o.end.y)
			if g != null:
				out.append({side = "w", to = other, along = g - c.y, pos = Vector3(-me.size.x / 2.0, 0, g - c.y)})
		elif is_equal_approx(o.position.x, me.end.x):	# east
			g = _span(me.position.y, me.end.y, o.position.y, o.end.y)
			if g != null:
				out.append({side = "e", to = other, along = g - c.y, pos = Vector3(me.size.x / 2.0, 0, g - c.y)})
	return out


## Middle of the overlap of [a0, a1] and [b0, b1], or null if they don't overlap enough for a gate.
static func _span(a0: float, a1: float, b0: float, b1: float):
	var lo = max(a0, b0)
	var hi = min(a1, b1)
	if hi - lo < GATE_WIDTH + 4.0:
		return null
	return (lo + hi) / 2.0
