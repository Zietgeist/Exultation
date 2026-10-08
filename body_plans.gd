extends RefCounted
## Body plans for the paper doll in the character window (paper_doll.gd).
## Each race in a skin's JSON can describe its body with a "body" block, so new races with
## different limbs just need data, not code:
##
##   "body": {"plan": "humanoid", "build": 1.0, "height": 1.0, "arms": 2, "legs": 2,
##            "tail": false, "wings": false, "lean": 0.0, "mech": false, "color": "#8a7f74"}
##
##   plan    "humanoid" (default) or "tree" (rooted, branching: Ents)
##   build   width (elf 0.8, dwarf 1.3)        height  leg length (dwarf 0.75)
##   arms    2, 4 or 6 (each extra right hand can hold another weapon, if the race has
##           a weapon slot with count 2+)
##   legs    2, 4 (centaur-like), or 0 (a tail if "tail", else it floats)
##   tail / wings   extra limbs. A race can give them their own slots ("tail", "wings").
##   lean    0..1 hunched (Bitten)               mech    metal joints (Cyborg)
##
## A plan gives: parts to draw (in a 0..1 square, x centered at 0.5) and anchors: where each
## gear slot sits on the body, and which side its tile goes on (L / R). Slots with many small
## spots (rings, implants, an Ent's leaves) get a PATH, and the spots are spread along it.
## Any slot a plan doesn't know goes in a row under the doll, so nothing is ever lost.

const DEFAULT_COLOR = Color(0.55, 0.5, 0.47)


static func plan_for(race: Dictionary) -> Dictionary:
	var b = race.get("body", {})
	if str(b.get("plan", "humanoid")) == "tree":
		return _tree(b)
	return _humanoid(b)


static func body_color(race: Dictionary) -> Color:
	var c = race.get("body", {}).get("color", "")
	return Color.from_string(c, DEFAULT_COLOR) if c is String and c != "" else DEFAULT_COLOR


# ---------------- Humanoid (and its many variations) ----------------

static func _humanoid(b: Dictionary) -> Dictionary:
	var w = float(b.get("build", 1.0))
	var h = float(b.get("height", 1.0))
	var arms = clampi(int(b.get("arms", 2)), 2, 6)
	var legs = int(b.get("legs", 2))
	var lean = float(b.get("lean", 0.0))
	var parts = []
	var anchors = {}
	var head = Vector2(0.5, 0.12 + lean * 0.07)
	var top = 0.22 + lean * 0.03
	var hip = 0.5
	var foot_y = min(0.97, hip + 0.42 * h)
	var lw = 0.045 * clamp(w, 0.8, 1.4)	# limb width

	if b.get("wings", false):
		for sd in [-1, 1]:
			parts.append({t = "poly", pts = [Vector2(0.5 + sd * 0.06, top + 0.04), Vector2(0.5 + sd * 0.44, 0.02),
				Vector2(0.5 + sd * 0.4, 0.3), Vector2(0.5 + sd * 0.12, top + 0.16)], shade = -0.15})
		anchors.wings = {pts = [Vector2(0.86, 0.1)], side = "R"}
	# Legs (drawn before the body)
	var left_foot = Vector2(0.5 - 0.07 * w, foot_y)
	if legs == 2:
		for sd in [-1, 1]:
			parts.append({t = "limb", a = Vector2(0.5 + sd * 0.055 * w, hip), b = Vector2(0.5 + sd * 0.075 * w, foot_y), w = lw * 1.25})
	elif legs >= 4:
		for sd in [-1, 1]:
			for k in [0.04, 0.13]:
				parts.append({t = "limb", a = Vector2(0.5 + sd * k * w, hip), b = Vector2(0.5 + sd * (k + 0.04) * w, foot_y), w = lw * 1.1})
		left_foot = Vector2(0.5 - 0.17 * w, foot_y)
	elif b.get("tail", false):
		var tail = [Vector2(0.5, hip), Vector2(0.56, hip + 0.15), Vector2(0.44, hip + 0.3), Vector2(0.6, foot_y)]
		for i in tail.size() - 1:
			parts.append({t = "limb", a = tail[i], b = tail[i + 1], w = lw * (1.6 - i * 0.4)})
		left_foot = tail[-1]
		anchors.tail = {pts = [tail[-1]], side = "R"}
	else:	# floats
		parts.append({t = "poly", pts = [Vector2(0.5 - 0.09 * w, hip), Vector2(0.5 + 0.09 * w, hip), Vector2(0.5, hip + 0.2)]})
		parts.append({t = "glow", c = Vector2(0.5, hip + 0.28), r = 0.05})
		left_foot = Vector2(0.5, hip + 0.22)
	# Torso
	parts.append({t = "poly", pts = [Vector2(0.5 - 0.12 * w, top), Vector2(0.5 + 0.12 * w, top),
		Vector2(0.5 + 0.09 * w, hip), Vector2(0.5 - 0.09 * w, hip)]})
	parts.append({t = "limb", a = Vector2(0.5, head.y + 0.05), b = Vector2(0.5, top + 0.01), w = 0.04})	# neck
	# Arms: pairs, each a little lower
	var right_hands = []
	var left_hands = []
	for k in range(arms / 2):
		var sy = top + 0.02 + 0.075 * k
		for sd in [-1, 1]:
			var sh = Vector2(0.5 + sd * 0.12 * w, sy)
			var el = Vector2(0.5 + sd * (0.2 + 0.03 * k) * w, sy + 0.13)
			var hand = Vector2(0.5 + sd * (0.25 + 0.035 * k) * w, sy + 0.26)
			parts.append({t = "limb", a = sh, b = el, w = lw})
			parts.append({t = "limb", a = el, b = hand, w = lw * 0.9})
			parts.append({t = "circle", c = hand, r = lw * 0.75})
			if b.get("mech", false):
				parts.append({t = "joint", c = el, r = lw * 0.7})
				parts.append({t = "joint", c = sh, r = lw * 0.8})
			(right_hands if sd == 1 else left_hands).append(hand)
	parts.append({t = "circle", c = head, r = 0.07})
	if b.get("mech", false):
		parts.append({t = "joint", c = head + Vector2(0.03, -0.01), r = 0.018, glow = true})
		parts.append({t = "joint", c = Vector2(0.5, (top + hip) / 2.0), r = 0.03, glow = true})

	anchors.head = {pts = [head], side = "R"}
	anchors.chest = {pts = [Vector2(0.5, (top + hip) / 2.0)], side = "R"}
	anchors.weapon = {pts = right_hands, side = "R"}
	anchors.shoulders = {pts = [Vector2(0.5 - 0.12 * w, top)], side = "L"}
	anchors.hands = {pts = left_hands, side = "L"}
	anchors.feet = {pts = [left_foot], side = "L"}
	# Rings: around the left hand(s). Implants: down the body and out the arms.
	var lh = left_hands[0]
	var ring_path = [lh + Vector2(0.06, -0.08), lh + Vector2(0.05, 0.05), lh + Vector2(-0.04, 0.08)]
	for extra in left_hands.slice(1):
		ring_path.append(extra + Vector2(-0.05, 0.03))
	anchors.ring = {path = ring_path, side = "L", small = true}
	anchors.implant = {path = [head + Vector2(-0.03, 0.02), Vector2(0.5, top + 0.05), Vector2(0.5, hip - 0.04),
		Vector2(0.5 - 0.04 * w, hip + 0.12), left_foot + Vector2(0.03, -0.08)], side = "L", small = true}
	return {parts = parts, anchors = anchors}


# ---------------- Tree (Ents): trunk, roots, branches, a crown of leaves ----------------

static func _tree(b: Dictionary) -> Dictionary:
	var w = float(b.get("build", 1.0))
	var parts = []
	for r in [Vector2(0.22, 0.96), Vector2(0.5, 0.98), Vector2(0.78, 0.96)]:
		parts.append({t = "limb", a = Vector2(0.5, 0.8), b = r, w = 0.04 * w})
	parts.append({t = "poly", pts = [Vector2(0.5 - 0.08 * w, 0.28), Vector2(0.5 + 0.08 * w, 0.28),
		Vector2(0.5 + 0.11 * w, 0.86), Vector2(0.5 - 0.11 * w, 0.86)]})
	var tips = [Vector2(0.16, 0.24), Vector2(0.84, 0.22), Vector2(0.5, 0.08)]
	parts.append({t = "limb", a = Vector2(0.5, 0.42), b = tips[0], w = 0.04 * w})
	parts.append({t = "limb", a = Vector2(0.5, 0.38), b = tips[1], w = 0.04 * w})
	parts.append({t = "limb", a = Vector2(0.5, 0.3), b = tips[2], w = 0.045 * w})
	for c in [Vector2(0.2, 0.2), Vector2(0.35, 0.1), Vector2(0.5, 0.06), Vector2(0.65, 0.1), Vector2(0.8, 0.18)]:
		parts.append({t = "leaf", c = c, r = 0.09})
	parts.append({t = "eyes", c = Vector2(0.5, 0.4), r = 0.015})
	var anchors = {
		weapon = {pts = [tips[1]], side = "R"},
		head = {pts = [Vector2(0.5, 0.06)], side = "R"},
		chest = {pts = [Vector2(0.5, 0.6)], side = "L"},
		ring = {path = [Vector2(0.12, 0.26), Vector2(0.22, 0.12), Vector2(0.38, 0.04), Vector2(0.62, 0.04), Vector2(0.78, 0.12), Vector2(0.9, 0.26)], side = "L", small = true},
		implant = {path = [Vector2(0.5, 0.35), Vector2(0.5, 0.8)], side = "L", small = true},
	}
	return {parts = parts, anchors = anchors}


# ---------------- Spreading small spots along a path ----------------

## n points spread evenly along a polyline.
static func spread(path: Array, n: int) -> Array:
	if n <= 0 or path.is_empty():
		return []
	if path.size() == 1 or n == 1:
		return [path[0]] if n == 1 else range(n).map(func(_i): return path[0])
	var lengths = []
	var total = 0.0
	for i in path.size() - 1:
		var l = path[i].distance_to(path[i + 1])
		lengths.append(l)
		total += l
	var out = []
	for k in n:
		var d = total * k / float(n - 1)
		var i = 0
		while i < lengths.size() - 1 and d > lengths[i]:
			d -= lengths[i]
			i += 1
		out.append(path[i].lerp(path[i + 1], clamp(d / max(lengths[i], 0.0001), 0.0, 1.0)))
	return out
