extends RefCounted
## The Guide (character window, C -> Guide tab): a small wiki of how the game works.
## The words live in res://guide.json (easy to edit). Some topics also have a "live" part that is
## written here from the game's own data (classes, races, materials...), so it's always up to date
## and uses the names of the world (skin) you're playing in.
##
## Tokens in guide.json text:  {el:shadow} element name   {name:enemy_trash} any skin name
##                             {class:tank} class name     {bag_min} {bag_max} minutes to fill the gold bag

const PATH = "res://guide.json"
const GOLD_HEX = "#ffd94d"


## Every topic: [{group, title, text}] with tokens filled in and live parts added.
static func topics() -> Array:
	var f = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		ErrorLog.fail("Guide: can't open %s" % PATH)
		return []
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary or not data.get("topics") is Array:
		ErrorLog.fail("Guide: %s is not valid (needs a \"topics\" list)" % PATH)
		return []
	var out = []
	for t in data.topics:
		var text = _fill(str(t.get("text", "")))
		var live = str(t.get("live", ""))
		if live != "":
			var extra = _live(live)
			text = text + ("\n\n" if text != "" else "") + extra
		out.append({group = str(t.get("group", "Other")), title = str(t.get("title", "?")), text = text})
	return out


# ---------------- Tokens ----------------

static func _fill(text: String) -> String:
	var bag_min = roundi(GameState.BAG_MINUTES_MIN / GameState.GOLD_TEST_SPEED)
	var bag_max = roundi(GameState.BAG_MINUTES_MAX / GameState.GOLD_TEST_SPEED)
	text = text.replace("{bag_min}", str(bag_min)).replace("{bag_max}", str(bag_max))
	var re = RegEx.new()
	re.compile("\\{(el|name|class):([a-z_0-9]+)\\}")
	for m in re.search_all(text):
		var word = m.get_string(2)
		var shown = word
		match m.get_string(1):
			"el": shown = SkinManager.element_label(word)
			"name": shown = SkinManager.name_of(word)
			"class": shown = Classes.label(word)
		text = text.replace(m.get_string(), shown)
	return text


# ---------------- Live parts ----------------

static func _live(id: String) -> String:
	match id:
		"classes": return _classes()
		"elements": return _elements()
		"materials": return _materials()
		"races": return _races()
		"recipes": return _recipes()
		"inn": return _inn()
		"trials": return _trials()
		"traits": return _traits()
		"worlds": return _worlds()
	ErrorLog.warn("Guide: unknown live part '%s' in %s" % [id, PATH])
	return ""


static func _gold(t: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [GOLD_HEX, t]


static func _colored(t: String, c: Color) -> String:
	return "[color=#%s][b]%s[/b][/color]" % [c.to_html(false), t]


static func _attr_name(attr: String) -> String:
	if attr in Crafting.ELEMENTS:
		return SkinManager.element_label(attr)
	return attr.capitalize()


## 3 -> "3", 1.5 -> "1.5", 0.15 -> "0.15"
static func _num(v: float) -> String:
	var t = "%.2f" % v
	while t.ends_with("0"):
		t = t.left(-1)
	return t.trim_suffix(".")


static func _classes() -> String:
	var mine = Classes.normalize(GameState.player_class)
	var parts = []
	for id in Classes.ids():
		var d = Classes.get_def(id)
		var lines = [_gold(Classes.label(id)) + ("   (you)" if id == mine else "") + "  -  " + str(d.get("role", ""))]
		lines.append(str(d.get("about", "")))
		var st = d.get("stats", {})
		var bits = []
		if float(st.get("health", 1.0)) != 1.0:
			bits.append("%+d%% health" % roundi((float(st.health) - 1.0) * 100.0))
		if float(st.get("speed", 1.0)) != 1.0:
			bits.append("%+d%% move speed" % roundi((float(st.speed) - 1.0) * 100.0))
		var en = d.get("energy", {})
		var e = ["refills %s energy a second" % _num(float(en.get("regen", 0.0)))]
		if float(en.get("per_damage_taken", 0.0)) > 0.0:
			e.append("gains energy when hit")
		if float(en.get("per_meter_moved", 0.0)) > 0.0:
			e.append("gains energy by running")
		bits.append("Energy: " + ", ".join(e))
		lines.append(" · ".join(bits))
		for key in Classes.KEYS:
			var s = Classes.skill(id, key)
			if s.is_empty():
				continue
			var cost = int(s.get("cost", 0))
			lines.append("   [b]%s  %s[/b] (%s): %s" % [key, Classes.skill_label(id, key), ("%d energy" % cost) if cost > 0 else "free", str(s.get("about", ""))])
		parts.append("\n".join(lines))
	return "\n\n".join(parts)


static func _elements() -> String:
	var lines = []
	for el in Crafting.ELEMENTS:
		lines.append("• " + _colored(SkinManager.element_label(el), Crafting.ELEMENT_COLORS[el]))
	lines.append("\nEnemies hit with one of these. Armor resists them (see Stats explained). Weapons with a special type add that damage to every hit.")
	lines.append("\n[b]What each zone throws at you[/b] (most common first):")
	for path in GameState.ZONE_ORDER:
		var list = Crafting.ZONE_ELEMENTS.get(path, [])
		var counts = {}
		for el in list:
			counts[el] = counts.get(el, 0) + 1
		var order = counts.keys()
		order.sort_custom(func(a, b): return counts[a] > counts[b])
		var names = order.map(func(el): return _colored(SkinManager.element_label(el), Crafting.ELEMENT_COLORS[el]))
		lines.append("• %s: %s" % [GameState.ZONE_NAMES.get(path, path), ", ".join(names)])
	lines.append("\nBosses always carry their zone's special type.")
	return "\n".join(lines)


static func _materials() -> String:
	var lines = []
	for raw in Crafting.REFINE:
		var r = Crafting.REFINE[raw]
		var a = Crafting.material_attributes(r.to, 1)
		var attrs = []
		for k in a:
			attrs.append("%s %s" % [_attr_name(k), _num(a[k])])
		var shop = "Smith" if r.shop == "smith" else "Chemist"
		lines.append("• %s  (%d %s at the %s): %s" % [_gold(Crafting.material_name(r.to, 1)), r.cost, GameState.resource_name(raw, 1), shop, ", ".join(attrs)])
	lines.append("\nEvery quality level multiplies these by 1.25.")
	var cycles = []
	for mat in ["tonic", "essence", "gem"]:
		var els = []
		for q in range(1, 5):
			for k in Crafting.material_attributes(mat, q):
				if k in Crafting.ELEMENTS and k != "physical":
					els.append(SkinManager.element_label(k))
		cycles.append("%s: %s" % [Crafting.MATERIAL_LABELS.get(mat, mat), " > ".join(els)])
	lines.append("Herbs, orchids and gems carry a [b]different element at each quality[/b] (quality 1 to 4, then it repeats):\n   " + "\n   ".join(cycles))
	return "\n".join(lines)


static func _races() -> String:
	var mine = SkinManager.race().get("id", "")
	var parts = []
	for r in SkinManager.races():
		var slots = []
		for s in r.get("slots", []):
			var n = int(s.get("count", 1))
			var label = str(s.get("label", SkinManager.slot_label(str(s.get("accepts", s.slot)))))
			slots.append(label if n == 1 else "%d %s%s" % [n, label, "" if label.ends_with("s") else "s"])
		parts.append("%s%s\n%s\nSlots: %s" % [_gold(str(r.get("name", r.id))), "   (you)" if r.id == mine else "", str(r.get("about", "")), ", ".join(slots)])
	return "\n\n".join(parts)


static func _recipes() -> String:
	var shops = {"smith": [], "chemist": []}
	for id in Crafting.BASES:
		var b = Crafting.BASES[id]
		var need = []
		for m in b.need:
			need.append("%d %s" % [b.need[m], Crafting.MATERIAL_LABELS.get(m, m)])
		var line = "• %s: %s. Needs %s, %d open slot%s." % [_gold(b.label), str(b.about).trim_suffix("."), " + ".join(need), b.slots, "" if b.slots == 1 else "s"]
		shops.get(b.shop, shops.smith).append(line)
	return "[b]Smith[/b]\n" + "\n".join(shops.smith) + "\n\n[b]Chemist[/b]\n" + "\n".join(shops.chemist)


static func _inn() -> String:
	var lines = []
	for id in GameState.INN_OFFERS:
		var o = GameState.INN_OFFERS[id]
		lines.append("• %s (%d gold): %s" % [_gold(o.name), o.gold, o.about])
	lines.append("• %s (%d gold): room for %d more, up to %d times" % [_gold("Bigger satchel"), GameState.SATCHEL_UPGRADE_GOLD, GameState.SATCHEL_UPGRADE_SIZE, GameState.SATCHEL_UPGRADES_MAX])
	lines.append("\nTreats last until your next rest. Once you rescue the Cook (Zone 2), the Cook makes them instead, and can make them stronger (see Helpers).")
	return "\n".join(lines)


static func _trials() -> String:
	var lines = []
	for id in Trials.TYPES:
		var t = Trials.TYPES[id]
		var lvl = Trials.level(id)
		var status = "level %s" % Trials.ROMAN[lvl] if lvl > 0 else "not started"
		var wait = Trials.wait_text(id)
		if wait == "mastered":
			status += ", mastered"
		elif wait != "":
			status += ", next level opens in " + wait
		elif lvl > 0:
			status += ", next level open now"
		var fam = Crafting.ADVANCED.get(id, {})
		lines.append("• %s: teaches the %s  (%s)" % [_colored(t.name, t.color), fam.get("label", "?"), status])
	return "\n".join(lines)


static func _traits() -> String:
	var parts = []
	for t in Traits.ORDER:
		var info = Traits.TENSIONS[t]
		parts.append("%s  [i](you: %s)[/i]\n[b]%s[/b]: %s\n[b]%s[/b]: %s" % [
			_gold("%s  <->  %s" % [info.left, info.right]), Traits.label(t),
			info.left, info.left_tip.replace("\n", " "), info.right, info.right_tip.replace("\n", " ")])
	return "\n\n".join(parts)


static func _worlds() -> String:
	var ids = SkinManager.skins.keys()
	ids.sort()
	var lines = []
	for id in ids:
		var s = SkinManager.skins[id]
		lines.append("• %s%s: %s" % [_gold(str(s.get("name", id))), "   (playing now)" if id == SkinManager.current_id else "", str(s.get("about", ""))])
	return "\n".join(lines)
