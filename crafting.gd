extends Node
## Crafting: refining raw resources, recipes with creative slots, damage types, and your gear.
## (Autoload "Crafting". Raw resources live in GameState.satchel; everything refined or made lives here.)
##
## HOW RECIPES WORK
##  - A BASE recipe (Blade, Vest, Draught...) needs some main material and gives the item its shape.
##  - Every base also has open SLOTS. Put ANY refined material in a slot.
##  - Each material has ATTRIBUTES. What an attribute does depends on the item:
##      element (radiant, shadow...)  weapon: extra damage of that type   armor: resists that type   potion: short ward
##      hardness                      weapon: more base damage            armor: resists physical
##      swiftness                     weapon: faster attacks              armor: move faster          potion: haste
##      vitality                      weapon: heal a little on each hit   armor: more max health      potion: bigger heal
##    So Sunleaf (radiant) in armor = absorbs radiant damage. In a blade = radiant damage. Mix and match.
##  - Quality multiplies every attribute by 1.25 per level (no upper limit).

signal changed

const SAVE_PATH = "user://crafting.cfg"

# ---------- Damage types ----------
const ELEMENTS = ["physical", "radiant", "shadow", "nature", "storm"]
const ELEMENT_COLORS = {
	"physical": Color(0.8, 0.8, 0.8),
	"radiant": Color(1.0, 0.9, 0.45),
	"shadow": Color(0.6, 0.35, 0.85),
	"nature": Color(0.4, 0.85, 0.35),
	"storm": Color(0.35, 0.8, 1.0),
}
const ATTRIBUTE_WORDS = {
	"physical": "Honed", "radiant": "Radiant", "shadow": "Shadowed", "nature": "Verdant", "storm": "Storm",
	"hardness": "Tempered", "swiftness": "Swift", "vitality": "Living",
}

# ---------- Refining: raw (in satchel) -> refined material ----------
const REFINE = {
	"ore": {to = "ingot", cost = 3, shop = "smith"},
	"treesilver": {to = "silverbar", cost = 1, shop = "smith"},
	"herb": {to = "tonic", cost = 3, shop = "chemist"},
	"orchid": {to = "essence", cost = 1, shop = "chemist"},
}

# Names per quality (add more as zones are added; past the list it shows "Ingot (Quality N)")
const MATERIAL_NAMES = {
	"ingot": ["Copper ingot", "Iron ingot"],
	"silverbar": ["Young Treesilver bar", "Elder Treesilver bar"],
	"tonic": ["Sunleaf tonic", "Moonleaf tonic"],
	"essence": ["Pale Orchid essence", "Storm Orchid essence"],
}
const MATERIAL_LABELS = {"ingot": "Ingot", "silverbar": "Treesilver bar", "tonic": "Tonic", "essence": "Orchid essence"}

# Herbs and orchids change element as quality rises (and keep cycling past the list)
const HERB_ELEMENTS = ["radiant", "shadow", "nature", "storm"]
const ORCHID_ELEMENTS = ["nature", "storm", "radiant", "shadow"]

# ---------- Base recipes ----------
# need: {material: count}  The quality you pick applies to the main material.
const BASES = {
	"blade": {label = "Blade", shop = "smith", slot = "weapon", need = {"ingot": 2}, slots = 2,
		stats = {st = 100.0, aoe = 50.0, cone = 0.3, targets = 4, st_cd = 2.0, aoe_cd = 1.0, reach = 10.0},
		about = "Balanced."},
	"cleaver": {label = "Cleaver", shop = "smith", slot = "weapon", need = {"ingot": 3}, slots = 2,
		stats = {st = 80.0, aoe = 75.0, cone = 0.0, targets = 7, st_cd = 2.4, aoe_cd = 1.3, reach = 9.0},
		about = "Wide, heavy sweeps. Slower."},
	"spear": {label = "Spear", shop = "smith", slot = "weapon", need = {"ingot": 2}, slots = 2,
		stats = {st = 140.0, aoe = 30.0, cone = 0.6, targets = 2, st_cd = 1.8, aoe_cd = 1.0, reach = 14.0},
		about = "Long reach, narrow sweep."},
	"vest": {label = "Vest", shop = "smith", slot = "armor", need = {"ingot": 2}, slots = 2,
		stats = {hardness = 2.0, move = 0.0}, about = "Light armor, room to customize."},
	"plate": {label = "Plate", shop = "smith", slot = "armor", need = {"ingot": 4}, slots = 1,
		stats = {hardness = 10.0, move = -0.1}, about = "Heavy: tough but 10% slower."},
	"draught": {label = "Draught", shop = "chemist", slot = "potion", need = {"tonic": 1}, slots = 1,
		stats = {heal = 30.0}, about = "A quick heal."},
	"elixir": {label = "Elixir", shop = "chemist", slot = "potion", need = {"essence": 1}, slots = 2,
		stats = {heal = 50.0}, about = "Strong heal, two creative slots."},
}

# ---------- What you own (saved) ----------
var stash = {}		# "material:quality" -> count
var items = []		# crafted gear and potions (each a Dictionary)
var equipped = {"weapon": -1, "armor": -1}	# item ids
var next_id = 1


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		stash = cfg.get_value("crafting", "stash", {})
		items = cfg.get_value("crafting", "items", [])
		equipped = cfg.get_value("crafting", "equipped", equipped)
		next_id = cfg.get_value("crafting", "next_id", 1)


func save():
	var cfg = ConfigFile.new()
	cfg.set_value("crafting", "stash", stash)
	cfg.set_value("crafting", "items", items)
	cfg.set_value("crafting", "equipped", equipped)
	cfg.set_value("crafting", "next_id", next_id)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Could not save crafting to " + SAVE_PATH)
	changed.emit()


# ---------- Materials ----------

func material_name(mat: String, q: int) -> String:
	var names = MATERIAL_NAMES.get(mat, [])
	if q >= 1 and q <= names.size():
		return names[q - 1]
	return "%s (Quality %d)" % [MATERIAL_LABELS.get(mat, mat), q]


## Attributes of ONE unit of a refined material. This is the "logic" table.
func material_attributes(mat: String, q: int) -> Dictionary:
	var a = {}
	match mat:
		"ingot":		# metal: hard, a little physical bite (more as quality rises)
			a = {hardness = 3.0, physical = 1.0 + 0.5 * (q - 1)}
		"silverbar":	# light living metal: speed and nature
			a = {swiftness = 4.0, nature = 1.5}
		"tonic":		# herb: carries an element, a little life
			a = {vitality = 1.0}
			a[HERB_ELEMENTS[(q - 1) % HERB_ELEMENTS.size()]] = 4.0
		"essence":		# rare flower: lots of life and an element
			a = {vitality = 5.0}
			a[ORCHID_ELEMENTS[(q - 1) % ORCHID_ELEMENTS.size()]] = 2.0
	var scale = pow(1.25, q - 1)
	for k in a:
		a[k] *= scale
	return a


func stash_count(mat: String, q: int) -> int:
	return stash.get("%s:%d" % [mat, q], 0)


func _take(mat: String, q: int, n: int):
	var key = "%s:%d" % [mat, q]
	stash[key] = stash.get(key, 0) - n
	if stash[key] <= 0:
		stash.erase(key)


## All refined materials you have: [{mat, q, count, name}]
func stash_list() -> Array:
	var out = []
	var keys = stash.keys()
	keys.sort()
	for key in keys:
		var bits = key.split(":")
		out.append({mat = bits[0], q = int(bits[1]), count = stash[key], name = material_name(bits[0], int(bits[1]))})
	return out


# ---------- Refining ----------

## Raw resources this shop can refine right now: [{raw, q, have, cost, to, name, result}]
func refine_options(shop: String) -> Array:
	var out = []
	for key in GameState.satchel:
		var bits = key.split(":")
		var raw = bits[0]
		var q = int(bits[1])
		if not REFINE.has(raw) or REFINE[raw].shop != shop:
			continue
		var have = GameState.satchel[key]
		out.append({raw = raw, q = q, have = have, cost = REFINE[raw].cost, to = REFINE[raw].to,
			name = GameState.resource_name(raw, q), result = material_name(REFINE[raw].to, q)})
	return out


func refine(raw: String, q: int) -> bool:
	var key = "%s:%d" % [raw, q]
	var cost = REFINE[raw].cost
	if GameState.satchel.get(key, 0) < cost:
		return false
	GameState.satchel[key] -= cost
	if GameState.satchel[key] <= 0:
		GameState.satchel.erase(key)
	GameState.save_progress()
	var out_key = "%s:%d" % [REFINE[raw].to, q]
	stash[out_key] = stash.get(out_key, 0) + 1
	save()
	return true


# ---------- Crafting ----------

## Can this base be made at this quality with what's in the stash?
func can_make_base(base_id: String, q: int, extra_slots: Array = []) -> bool:
	var needed = {}
	for mat in BASES[base_id].need:
		needed["%s:%d" % [mat, q]] = BASES[base_id].need[mat]
	for s in extra_slots:
		var k = "%s:%d" % [s.mat, s.q]
		needed[k] = needed.get(k, 0) + 1
	for k in needed:
		if stash.get(k, 0) < needed[k]:
			return false
	return true


## Qualities the main material is available in for a base.
func base_qualities(base_id: String) -> Array:
	var qs = []
	for entry in stash_list():
		for mat in BASES[base_id].need:
			if entry.mat == mat and entry.count >= BASES[base_id].need[mat] and not qs.has(entry.q):
				qs.append(entry.q)
	qs.sort()
	return qs


## Work out an item WITHOUT making it (used for the preview and for crafting).
func design(base_id: String, q: int, slot_mats: Array) -> Dictionary:
	var base = BASES[base_id]
	var attrs = {}
	var made_from = []
	for mat in base.need:
		var unit = material_attributes(mat, q)
		for k in unit:	# main material counts half per unit; slots count fully (that's where creativity pays)
			attrs[k] = attrs.get(k, 0.0) + unit[k] * base.need[mat] * 0.5
		made_from.append("%d %s" % [base.need[mat], material_name(mat, q)])
	var strongest = ""
	var strongest_val = 0.0
	for s in slot_mats:
		var unit = material_attributes(s.mat, s.q)
		for k in unit:
			attrs[k] = attrs.get(k, 0.0) + unit[k]
			if unit[k] > strongest_val:
				strongest = k
				strongest_val = unit[k]
		made_from.append(material_name(s.mat, s.q))
	var words = material_name(base.need.keys()[0], q).split(" ")
	var main_name = " ".join(words.slice(0, max(1, words.size() - 1)))	# "Copper ingot" -> "Copper"
	var title = "%s %s" % [main_name, base.label]
	if strongest != "":
		title = ATTRIBUTE_WORDS.get(strongest, "") + " " + title
	return {base = base_id, slot = base.slot, quality = q, name = title, attrs = attrs, made_from = made_from}


func craft(base_id: String, q: int, slot_mats: Array):
	if not can_make_base(base_id, q, slot_mats):
		return null
	for mat in BASES[base_id].need:
		_take(mat, q, BASES[base_id].need[mat])
	for s in slot_mats:
		_take(s.mat, s.q, 1)
	var item = design(base_id, q, slot_mats)
	item.id = next_id
	next_id += 1
	# Gear memory: what it was made from, where, and when
	item.made_on = Time.get_date_string_from_system()
	item.made_in = GameState.ZONE_NAMES.get(GameState.ZONE_ORDER[min(q, GameState.ZONE_ORDER.size() - 1)], "Zone %d" % (q + 1))
	items.append(item)
	# First weapon/armor you make gets equipped automatically
	if item.slot in equipped and equipped[item.slot] == -1:
		equipped[item.slot] = item.id
	save()
	return item


func item_by_id(id: int):
	for it in items:
		if it.id == id:
			return it
	return null


func equip(id: int):
	var it = item_by_id(id)
	if it and it.slot in equipped:
		equipped[it.slot] = id
		save()


func potions() -> Array:
	return items.filter(func(it): return it.slot == "potion")


## Drink the oldest potion: returns its effects (or null if none).
func drink_potion():
	var ps = potions()
	if ps.is_empty():
		return null
	var p = ps[0]
	items.erase(p)
	save()
	return effects(p)


# ---------- What an item actually does ----------

func effects(item: Dictionary) -> Dictionary:
	var a = item.attrs
	var base = BASES[item.base]
	var s = base.stats
	var e = {}
	match item.slot:
		"weapon":
			var hard = a.get("hardness", 0.0)
			e.st = s.st + hard * 6.0 + a.get("physical", 0.0) * 5.0
			e.aoe = s.aoe + hard * 3.0 + a.get("physical", 0.0) * 2.5
			e.cone = s.cone
			e.targets = s.targets
			e.reach = s.reach
			var speed = 1.0 / (1.0 + a.get("swiftness", 0.0) * 0.04)
			e.st_cd = s.st_cd * speed
			e.aoe_cd = s.aoe_cd * speed
			e.element_bonus = {}	# extra damage of each type, per hit
			for el in ELEMENTS:
				if el != "physical" and a.get(el, 0.0) > 0.0:
					e.element_bonus[el] = a[el] * 5.0
			e.lifesteal = a.get("vitality", 0.0) * 0.4
		"armor":
			e.resist = {}
			var phys = s.hardness + a.get("hardness", 0.0) + a.get("physical", 0.0)
			e.resist["physical"] = phys / (phys + 20.0)
			for el in ELEMENTS:
				if el != "physical" and a.get(el, 0.0) > 0.0:
					e.resist[el] = a[el] / (a[el] + 20.0)
			e.move = s.move + a.get("swiftness", 0.0) * 0.02
			e.max_health = a.get("vitality", 0.0) * 4.0
		"potion":
			e.heal = s.heal + a.get("vitality", 0.0) * 8.0
			e.ward = {}		# short resistances (30 s)
			for el in ELEMENTS:
				if a.get(el, 0.0) > 0.0:
					e.ward[el] = a[el] / (a[el] + 10.0)
			e.haste = a.get("swiftness", 0.0) * 0.03
	return e


## Plain-English summary of an item, for the shop screens.
func describe(item: Dictionary) -> String:
	var e = effects(item)
	var lines = []
	match item.slot:
		"weapon":
			lines.append("Hit %d / Sweep %d   (reach %d, sweep up to %d)" % [e.st, e.aoe, e.reach, e.targets])
			lines.append("Attack time %.1fs / %.1fs" % [e.st_cd, e.aoe_cd])
			for el in e.element_bonus:
				lines.append("+%d %s damage per hit" % [e.element_bonus[el], el])
			if e.lifesteal > 0.0:
				lines.append("Heals %.1f per hit" % e.lifesteal)
		"armor":
			for el in e.resist:
				lines.append("Resists %d%% %s" % [roundi(e.resist[el] * 100), el])
			if e.move != 0.0:
				lines.append("Move speed %+d%%" % roundi(e.move * 100))
			if e.max_health > 0.0:
				lines.append("+%d max health" % e.max_health)
		"potion":
			lines.append("Heals %d" % e.heal)
			for el in e.ward:
				lines.append("Ward: resist %d%% %s for 30s" % [roundi(e.ward[el] * 100), el])
			if e.haste > 0.0:
				lines.append("Haste +%d%% for 30s" % roundi(e.haste * 100))
	if item.has("made_from"):
		var made = "Made from " + ", ".join(item.made_from)
		if item.has("made_on"):
			made += "  (%s, %s quality)" % [item.made_on, item.made_in]
		lines.append(made)
	return "\n".join(lines)


# ---------- Enemy damage types per zone ----------
const ZONE_ELEMENTS = {
	"res://Zone1.tscn": ["physical"],
	"res://Zone2.tscn": ["physical", "physical", "physical", "radiant"],
	"res://Zone3.tscn": ["physical", "physical", "shadow", "storm"],
}

## Pick a damage type for an enemy in this zone. Bosses always carry the zone's element.
func roll_enemy_element(scene_path: String, is_boss: bool) -> String:
	var list = ZONE_ELEMENTS.get(scene_path, ["physical", "physical", ELEMENTS[1 + randi() % 4]])
	if is_boss:
		var special = list.filter(func(x): return x != "physical")
		if special.size() > 0:
			return special[randi() % special.size()]
	return list[randi() % list.size()]
