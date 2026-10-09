extends RefCounted
## Simple icons, drawn with shapes (no image files yet). Used by item tiles (item_tile.gd),
## the paper doll and the inventory. Later these can be swapped for painted art per skin:
## kind_of() gives one name per kind of thing, so one image per name is all that's needed.
##
##   draw(ci, kind, rect, color): draws icon `kind` inside `rect` on CanvasItem `ci`.
##   Kinds: blade cleaver spear fists head shoulders chest plate hands feet ring implant potion
##          ore herb treesilver orchid geode ingot silverbar tonic essence gem sigil gold satchel

const QUALITY_COLORS = [	# border color by quality (zone it came from)
	Color(0.55, 0.55, 0.55), Color(0.85, 0.85, 0.85), Color(0.35, 0.85, 0.35), Color(0.35, 0.6, 1.0),
	Color(0.7, 0.4, 1.0), Color(1.0, 0.6, 0.2), Color(1.0, 0.35, 0.35), Color(1.0, 0.85, 0.3), Color(0.4, 1.0, 0.95),
]


static func quality_color(q: int) -> Color:
	return QUALITY_COLORS[clampi(q, 0, QUALITY_COLORS.size() - 1)]


## What icon an item uses (advanced recipes use their base's icon).
static func kind_of(it: Dictionary) -> String:
	var base = str(it.get("base", ""))
	if base.begins_with("adv:"):
		base = Crafting.ADVANCED.get(base.get_slice(":", 1), {}).get("base", "blade")
	match base:
		"blade", "cleaver", "spear", "plate", "ring":
			return base
		"vest":
			return "chest"
		"helm":
			return "head"
		"pauldrons":
			return "shoulders"
		"gloves":
			return "hands"
		"boots":
			return "feet"
		"draught", "elixir":
			return "potion"
	return str(it.get("slot", "ring"))


## The color an item shows: its strongest element, else plain metal.
static func item_color(it: Dictionary) -> Color:
	var best = ""
	var best_v = 0.0
	for el in Crafting.ELEMENTS:
		var v = it.get("attrs", {}).get(el, 0.0)
		if el != "physical" and v > best_v:
			best = el
			best_v = v
	return Crafting.ELEMENT_COLORS[best] if best != "" else Color(0.82, 0.82, 0.86)


## The icon for an empty gear slot of this kind.
static func slot_kind(accepts: String) -> String:
	return {"weapon": "blade", "head": "head", "shoulders": "shoulders", "chest": "chest", "hands": "hands",
		"feet": "feet", "ring": "ring", "implant": "implant"}.get(accepts, "ring")


static func draw(ci: CanvasItem, kind: String, r: Rect2, c: Color):
	var p = func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size	# 0..1 inside the rect
	var s = min(r.size.x, r.size.y)
	var dark = c.darkened(0.45)
	match kind:
		"blade":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.78, 0.12), p.call(0.88, 0.22), p.call(0.38, 0.72), p.call(0.28, 0.62)]), c)
			ci.draw_line(p.call(0.2, 0.55), p.call(0.45, 0.8), dark, s * 0.08)
			ci.draw_line(p.call(0.32, 0.68), p.call(0.14, 0.86), Color(0.5, 0.33, 0.2), s * 0.09)
		"cleaver":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.12), p.call(0.82, 0.12), p.call(0.82, 0.5), p.call(0.3, 0.42)]), c)
			ci.draw_line(p.call(0.4, 0.45), p.call(0.3, 0.88), Color(0.5, 0.33, 0.2), s * 0.1)
		"spear":
			ci.draw_line(p.call(0.18, 0.88), p.call(0.7, 0.3), Color(0.55, 0.38, 0.22), s * 0.07)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.88, 0.1), p.call(0.78, 0.4), p.call(0.6, 0.25)]), c)
		"fists":
			ci.draw_circle(p.call(0.5, 0.55), s * 0.25, c)
			for i in 4:
				ci.draw_circle(p.call(0.32 + i * 0.12, 0.33), s * 0.07, c.lightened(0.1))
		"head":
			ci.draw_arc(p.call(0.5, 0.58), s * 0.32, PI, TAU, 16, c, s * 0.14)
			ci.draw_rect(Rect2(p.call(0.16, 0.56), Vector2(0.68, 0.1) * r.size), c)
			ci.draw_line(p.call(0.5, 0.3), p.call(0.5, 0.78), dark, s * 0.06)
		"shoulders":
			ci.draw_arc(p.call(0.3, 0.6), s * 0.2, PI, TAU, 12, c, s * 0.14)
			ci.draw_arc(p.call(0.7, 0.6), s * 0.2, PI, TAU, 12, c, s * 0.14)
		"chest", "plate":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.22, 0.18), p.call(0.38, 0.12), p.call(0.5, 0.22), p.call(0.62, 0.12),
				p.call(0.78, 0.18), p.call(0.74, 0.86), p.call(0.26, 0.86)]), c)
			if kind == "plate":
				for y in [0.4, 0.58, 0.76]:
					ci.draw_line(p.call(0.28, y), p.call(0.72, y), dark, s * 0.04)
		"hands":
			ci.draw_rect(Rect2(p.call(0.3, 0.42), Vector2(0.4, 0.42) * r.size), c)
			for i in 4:
				ci.draw_line(p.call(0.34 + i * 0.1, 0.42), p.call(0.34 + i * 0.1, 0.2), c, s * 0.07)
			ci.draw_line(p.call(0.3, 0.55), p.call(0.16, 0.42), c, s * 0.08)
		"feet":
			ci.draw_rect(Rect2(p.call(0.3, 0.16), Vector2(0.24, 0.5) * r.size), c)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.62), p.call(0.82, 0.68), p.call(0.82, 0.84), p.call(0.3, 0.84)]), c)
		"ring":
			ci.draw_arc(p.call(0.5, 0.58), s * 0.24, 0, TAU, 20, c, s * 0.09)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.14), p.call(0.62, 0.28), p.call(0.5, 0.4), p.call(0.38, 0.28)]), c.lightened(0.3))
		"implant":
			ci.draw_rect(Rect2(p.call(0.25, 0.25), Vector2(0.5, 0.5) * r.size), c)
			for i in 3:
				var t = 0.33 + i * 0.17
				ci.draw_line(p.call(t, 0.1), p.call(t, 0.25), c, s * 0.05)
				ci.draw_line(p.call(t, 0.75), p.call(t, 0.9), c, s * 0.05)
			ci.draw_rect(Rect2(p.call(0.38, 0.38), Vector2(0.24, 0.24) * r.size), dark)
		"potion", "tonic", "essence":
			ci.draw_circle(p.call(0.5, 0.62), s * 0.27, c)
			ci.draw_rect(Rect2(p.call(0.42, 0.14), Vector2(0.16, 0.26) * r.size), c.lightened(0.2))
			ci.draw_rect(Rect2(p.call(0.38, 0.1), Vector2(0.24, 0.08) * r.size), Color(0.55, 0.38, 0.22))
			ci.draw_circle(p.call(0.42, 0.56), s * 0.07, Color(1, 1, 1, 0.5))
		"ore":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.15, 0.7), p.call(0.3, 0.3), p.call(0.6, 0.2), p.call(0.85, 0.45), p.call(0.75, 0.82), p.call(0.35, 0.86)]), Color(0.4, 0.38, 0.36))
			for d in [[0.4, 0.45], [0.62, 0.6], [0.45, 0.7]]:
				ci.draw_circle(p.call(d[0], d[1]), s * 0.07, c)
		"herb":
			ci.draw_line(p.call(0.5, 0.9), p.call(0.5, 0.35), Color(0.3, 0.6, 0.2), s * 0.06)
			for side in [-1, 1]:
				for y in [0.35, 0.55]:
					ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, y + 0.12), p.call(0.5 + side * 0.32, y - 0.05), p.call(0.5 + side * 0.12, y + 0.18)]), c)
			ci.draw_circle(p.call(0.5, 0.25), s * 0.1, c.lightened(0.2))
		"treesilver":
			ci.draw_rect(Rect2(p.call(0.4, 0.15), Vector2(0.2, 0.75) * r.size), c)
			ci.draw_line(p.call(0.5, 0.45), p.call(0.8, 0.25), c, s * 0.08)
			ci.draw_line(p.call(0.5, 0.6), p.call(0.22, 0.42), c, s * 0.08)
		"orchid":
			for i in 5:
				var a = i * TAU / 5.0 - PI / 2.0
				ci.draw_circle(p.call(0.5 + cos(a) * 0.2, 0.45 + sin(a) * 0.2), s * 0.14, c)
			ci.draw_circle(p.call(0.5, 0.45), s * 0.1, Color(1, 0.95, 0.6))
			ci.draw_line(p.call(0.5, 0.65), p.call(0.5, 0.92), Color(0.3, 0.6, 0.2), s * 0.06)
		"geode":
			ci.draw_circle(p.call(0.5, 0.52), s * 0.36, Color(0.45, 0.42, 0.4))
			ci.draw_circle(p.call(0.5, 0.52), s * 0.24, c.darkened(0.3))
			for i in 6:
				var a = i * TAU / 6.0
				ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.52), p.call(0.5 + cos(a) * 0.22, 0.52 + sin(a) * 0.22), p.call(0.5 + cos(a + 0.5) * 0.22, 0.52 + sin(a + 0.5) * 0.22)]), c if i % 2 == 0 else c.lightened(0.3))
		"ingot", "silverbar":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.25, 0.35), p.call(0.75, 0.35), p.call(0.9, 0.7), p.call(0.1, 0.7)]), c)
			ci.draw_line(p.call(0.25, 0.35), p.call(0.75, 0.35), c.lightened(0.4), s * 0.05)
		"gem":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.25), p.call(0.7, 0.25), p.call(0.88, 0.42), p.call(0.5, 0.88), p.call(0.12, 0.42)]), c)
			ci.draw_line(p.call(0.12, 0.42), p.call(0.88, 0.42), c.lightened(0.4), s * 0.04)
		"sigil":
			ci.draw_arc(p.call(0.5, 0.5), s * 0.36, 0, TAU, 24, c, s * 0.06)
			for k in 2:	# two triangles: a star
				var tri = PackedVector2Array()
				for i in 3:
					var a = deg_to_rad(-90.0 + 120.0 * i + 180.0 * k)
					tri.append(p.call(0.5 + cos(a) * 0.26, 0.5 + sin(a) * 0.26))
				ci.draw_colored_polygon(tri, c if k == 0 else c.lightened(0.3))
		"gold":
			ci.draw_circle(p.call(0.42, 0.58), s * 0.26, Color(0.85, 0.65, 0.15))
			ci.draw_circle(p.call(0.58, 0.44), s * 0.26, Color(1.0, 0.82, 0.3))
			ci.draw_arc(p.call(0.58, 0.44), s * 0.17, 0, TAU, 16, Color(0.8, 0.6, 0.1), s * 0.04)
		"satchel":
			ci.draw_rect(Rect2(p.call(0.18, 0.35), Vector2(0.64, 0.5) * r.size), Color(0.55, 0.38, 0.22))
			ci.draw_arc(p.call(0.5, 0.36), s * 0.2, PI, TAU, 12, Color(0.45, 0.3, 0.18), s * 0.07)
			ci.draw_rect(Rect2(p.call(0.18, 0.35), Vector2(0.64, 0.16) * r.size), Color(0.45, 0.3, 0.18))
		# ---- buffs (buff_bar.gd) ----
		"meal":
			ci.draw_arc(p.call(0.5, 0.45), s * 0.32, 0, PI, 16, c, s * 0.1)
			ci.draw_line(p.call(0.18, 0.45), p.call(0.82, 0.45), c, s * 0.08)
			for x in [0.38, 0.5, 0.62]:
				ci.draw_line(p.call(x, 0.35), p.call(x + 0.04, 0.15), Color(1, 1, 1, 0.6), s * 0.04)
		"sleep":
			ci.draw_circle(p.call(0.45, 0.5), s * 0.3, c)
			ci.draw_circle(p.call(0.6, 0.4), s * 0.27, Color(0.08, 0.08, 0.1))
			ci.draw_string(ThemeDB.fallback_font, p.call(0.62, 0.42), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.35), c)
		"ward", "shield":
			var pts = PackedVector2Array([p.call(0.5, 0.12), p.call(0.84, 0.25), p.call(0.78, 0.62), p.call(0.5, 0.9), p.call(0.22, 0.62), p.call(0.16, 0.25)])
			if kind == "shield":
				ci.draw_colored_polygon(pts, c)
			else:
				pts.append(pts[0])
				ci.draw_polyline(pts, c, s * 0.08)
		"boost":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.1), p.call(0.85, 0.5), p.call(0.62, 0.5), p.call(0.62, 0.9), p.call(0.38, 0.9), p.call(0.38, 0.5), p.call(0.15, 0.5)]), c)
		"thorns":
			for i in 8:
				var a = i * TAU / 8.0
				ci.draw_line(p.call(0.5, 0.5), p.call(0.5 + cos(a) * 0.4, 0.5 + sin(a) * 0.4), c, s * 0.07)
			ci.draw_circle(p.call(0.5, 0.5), s * 0.16, c)
		"whirl":
			ci.draw_arc(p.call(0.5, 0.5), s * 0.34, 0, PI * 1.6, 20, c, s * 0.08)
			ci.draw_arc(p.call(0.5, 0.5), s * 0.18, PI, PI * 2.6, 16, c, s * 0.08)
		"drain", "vow":
			ci.draw_circle(p.call(0.5, 0.62), s * 0.25, c)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.12), p.call(0.72, 0.52), p.call(0.28, 0.52)]), c)
		"totem":
			ci.draw_rect(Rect2(p.call(0.38, 0.15), Vector2(0.24, 0.72) * r.size), c)
			ci.draw_rect(Rect2(p.call(0.26, 0.28), Vector2(0.48, 0.1) * r.size), c.lightened(0.3))
		"patient":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.25, 0.12), p.call(0.75, 0.12), p.call(0.5, 0.5)]), c)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.5), p.call(0.75, 0.88), p.call(0.25, 0.88)]), c.darkened(0.3))
		"driven":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.08), p.call(0.78, 0.55), p.call(0.66, 0.9), p.call(0.34, 0.9), p.call(0.22, 0.55)]), c)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.45), p.call(0.62, 0.72), p.call(0.5, 0.88), p.call(0.38, 0.72)]), Color(1, 0.95, 0.6))
		_:
			ci.draw_circle(p.call(0.5, 0.5), s * 0.3, c)
