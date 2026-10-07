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
const MATERIAL_LABELS = {"ingot": "Ingot", "silverbar": "Treesilver bar", "tonic": "Tonic", "essence": "Orchid essence",
	"sigil_precision": "Sigil of Precision", "sigil_numbers": "Sigil of Numbers", "sigil_sorting": "Sigil of Color",
	"sigil_typing": "Sigil of Swiftness", "sigil_logic": "Sigil of Logic"}

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
	"vest": {label = "Vest", shop = "smith", slot = "chest", need = {"ingot": 2}, slots = 2,
		stats = {hardness = 2.0, move = 0.0}, about = "Light chest armor, room to customize."},
	"plate": {label = "Plate", shop = "smith", slot = "chest", need = {"ingot": 4}, slots = 1,
		stats = {hardness = 10.0, move = -0.1}, about = "Heavy chest: tough but 10% slower."},
	"helm": {label = "Helm", shop = "smith", slot = "head", need = {"ingot": 2}, slots = 1,
		stats = {hardness = 3.0, move = 0.0}, about = "Head armor."},
	"pauldrons": {label = "Pauldrons", shop = "smith", slot = "shoulders", need = {"ingot": 2}, slots = 1,
		stats = {hardness = 3.0, move = 0.0}, about = "Shoulder armor."},
	"gloves": {label = "Gloves", shop = "smith", slot = "hands", need = {"ingot": 1}, slots = 1,
		stats = {hardness = 1.0, move = 0.0}, about = "Hand armor."},
	"boots": {label = "Boots", shop = "smith", slot = "feet", need = {"ingot": 1}, slots = 1,
		stats = {hardness = 1.0, move = 0.03}, about = "Foot armor, a little faster."},
	"ring": {label = "Ring", shop = "smith", slot = "ring", need = {"ingot": 1}, slots = 1,
		stats = {hardness = 0.0, move = 0.0}, about = "Small, but every slot counts."},
	"draught": {label = "Draught", shop = "chemist", slot = "potion", need = {"tonic": 1}, slots = 1,
		stats = {heal = 30.0}, about = "A quick heal."},
	"elixir": {label = "Elixir", shop = "chemist", slot = "potion", need = {"essence": 1}, slots = 2,
		stats = {heal = 50.0}, about = "Strong heal, two creative slots."},

}

# ---------- Advanced recipes: one family per trial ability, levels 1-8 ----------
# Level 0 is the shop's basic recipe. Trial level N (Trials.level) teaches level N, which gets much
# stronger every level: power x (1 + 0.5 N + 0.1 N^2) -> I x1.6, II x2.4, IV x4.6, VIII x11.4,
# plus more creative slots and faster attacks. Recipe ids look like "adv:precision:3".
const ADVANCED = {
	"precision": {base = "blade", label = "Masterwork Blade"},
	"numbers": {base = "plate", label = "Tally Plate", move = 0.0},
	"sorting": {base = "ring", label = "Prism Ring"},
	"typing": {base = "boots", label = "Windrunner Boots"},
	"logic": {base = "elixir", label = "Grand Elixir"},
}
const OLD_ADVANCED = {"masterwork_blade": "precision", "tally_plate": "numbers", "prism_ring": "sorting", "windrunner_boots": "typing", "grand_elixir": "logic"}
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

# Gold (banked) for making things: basic = 5 + 3 per quality, advanced = 15 per level + 5 per quality
const BASIC_GOLD = 5
const GOLD_PER_QUALITY = 3
const ADVANCED_GOLD_PER_LEVEL = 15


func advanced_id(ability: String, level: int) -> String:
	return "adv:%s:%d" % [ability, level]


func power(level: int) -> float:
	return 1.0 + 0.5 * level + 0.1 * level * level


## A recipe by id: a basic one from BASES, or an advanced one built from its family and level.
func recipe(id: String) -> Dictionary:
	if BASES.has(id):
		return BASES[id]
	if OLD_ADVANCED.has(id):	# early test saves
		id = advanced_id(OLD_ADVANCED[id], 1)
	if _adv_cache.has(id):
		return _adv_cache[id]
	var bits = id.split(":")
	if bits.size() != 3 or bits[0] != "adv" or not ADVANCED.has(bits[1]):
		ErrorLog.fail("Unknown recipe id: " + id)
		return BASES.blade
	var ability = bits[1]
	var level = clampi(int(bits[2]), 1, 8)
	var fam = ADVANCED[ability]
	var b = BASES[fam.base].duplicate(true)
	var m = power(level)
	var st = b.stats
	for k in ["st", "aoe", "hardness", "heal"]:
		if st.has(k):
			st[k] = st[k] * m
	for k in ["st_cd", "aoe_cd"]:
		if st.has(k):
			st[k] = st[k] * (1.0 - min(0.3, 0.04 * level))
	if st.has("targets"):
		st.targets = st.targets + int(level / 2.0)
	if fam.base == "ring":
		st.hardness = 1.0 * level
	if fam.base == "boots":
		st.move = 0.03 + 0.015 * level
	if fam.has("move"):
		st.move = fam.move
	b.slots = mini(b.slots + 1 + int(level / 2.0), 6)
	b.label = "%s %s" % [fam.label, ROMAN[level]]
	b.about = "Level %d recipe (from %s trials): power x%.1f, %d creative slots." % [level, ability.capitalize(), m, b.slots]
	b.advanced = true
	b.ability = ability
	b.level = level
	_adv_cache[id] = b
	return b

var _adv_cache = {}


## Recipe ids a shop shows: its basic ones, plus the best advanced level you've earned.
func shop_recipes(shop: String) -> Array:
	var out = []
	for id in BASES:
		if BASES[id].shop == shop:
			out.append(id)
	for ability in ADVANCED:
		var l = Trials.level(ability)
		if l > 0:
			var id = advanced_id(ability, l)
			if recipe(id).shop == shop:
				out.append(id)
	return out


## Gold it costs to make (paid from banked gold).
func gold_cost(id: String, q: int) -> int:
	var b = recipe(id)
	if b.get("advanced", false):
		return ADVANCED_GOLD_PER_LEVEL * b.level + 5 * q
	return BASIC_GOLD + GOLD_PER_QUALITY * q


# ---------- What you own (saved) ----------
var stash = {}		# "material:quality" -> count
var items = []		# crafted gear and potions (each a Dictionary)
var equipped = {}	# race slot id -> [item ids] (-1 = empty). Which slots exist depends on your RACE (from the skin).
const ARMOR_SLOTS = ["head", "shoulders", "chest", "hands", "feet", "ring"]
var next_id = 1
var patterns = []	# advanced recipes you've learned (from your first Sigil of each kind)


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		stash = cfg.get_value("crafting", "stash", {})
		items = cfg.get_value("crafting", "items", [])
		equipped = cfg.get_value("crafting", "equipped", {})
		next_id = cfg.get_value("crafting", "next_id", 1)
		patterns = cfg.get_value("crafting", "patterns", [])
	_upgrade_old_save()
	ensure_slots()
	SkinManager.skin_changed.connect(ensure_slots)


## Older saves had one "armor" slot holding a single id.
func _upgrade_old_save():
	for it in items:
		if it.slot == "armor":
			it.slot = "chest"
	for k in equipped.keys():
		if typeof(equipped[k]) == TYPE_INT:
			var id = equipped[k]
			equipped.erase(k)
			if id != -1:
				equipped["chest" if k == "armor" else k] = [id]


func save():
	var cfg = ConfigFile.new()
	cfg.set_value("crafting", "stash", stash)
	cfg.set_value("crafting", "items", items)
	cfg.set_value("crafting", "equipped", equipped)
	cfg.set_value("crafting", "next_id", next_id)
	cfg.set_value("crafting", "patterns", patterns)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Could not save crafting to " + SAVE_PATH)
	changed.emit()


# ---------- Materials ----------

func material_name(mat: String, q: int) -> String:
	var skinned = SkinManager.list_name("materials", mat, q)
	if skinned != null:
		return skinned
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


## Recipes a shop shows: every basic one, plus advanced ones you've learned.
func knows(base_id: String) -> bool:
	var b = recipe(base_id)
	return not b.get("advanced", false) or Trials.level(b.ability) >= b.level


func learn(base_id: String):
	if not patterns.has(base_id):
		patterns.append(base_id)
		save()


func add_material(mat: String, q: int, n: int):
	var key = "%s:%d" % [mat, q]
	stash[key] = stash.get(key, 0) + n
	save()


func is_sigil(mat: String) -> bool:
	return mat.begins_with("sigil_")


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
	Traits.on_refine()	# Keeper
	return true


# ---------- Crafting ----------

## Can this base be made at this quality with what's in the stash?
func can_make_base(base_id: String, q: int, extra_slots: Array = []) -> bool:
	var needed = {}
	for mat in recipe(base_id).need:
		needed["%s:%d" % [mat, q]] = recipe(base_id).need[mat]
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
		for mat in recipe(base_id).need:
			if entry.mat == mat and entry.count >= recipe(base_id).need[mat] and not qs.has(entry.q):
				qs.append(entry.q)
	qs.sort()
	return qs


## Work out an item WITHOUT making it (used for the preview and for crafting).
func design(base_id: String, q: int, slot_mats: Array) -> Dictionary:
	var base = recipe(base_id)
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
	if not GameState.spend_gold(gold_cost(base_id, q)):
		GameState.notify("Not enough banked gold (%d needed)" % gold_cost(base_id, q))
		return null
	for mat in recipe(base_id).need:
		_take(mat, q, recipe(base_id).need[mat])
	for s in slot_mats:
		_take(s.mat, s.q, 1)
	var item = design(base_id, q, slot_mats)
	for k in item.attrs:	# Keeper: what you make comes out a little stronger
		item.attrs[k] *= Traits.craft_mult()
	Traits.on_craft(item.name)
	item.id = next_id
	next_id += 1
	# Gear memory: what it was made from, where, and when
	item.made_on = Time.get_date_string_from_system()
	item.made_in = GameState.ZONE_NAMES.get(GameState.ZONE_ORDER[min(q, GameState.ZONE_ORDER.size() - 1)], "Zone %d" % (q + 1))
	Story.stamp_crafted(item, base_id)	# who made it, the recipe's story, and a fresh life record
	items.append(item)
	# New gear goes straight onto an empty slot if your race has one
	var rs = slot_for(item)
	if rs and equipped.has(rs.slot) and equipped[rs.slot].has(-1):
		equipped[rs.slot][equipped[rs.slot].find(-1)] = item.id
	save()
	return item


## Unworn gear can be given to a party member (online). Worn gear is bound.
func can_give(it: Dictionary) -> bool:
	return not it.has("bound_to") and not is_equipped(it.id)


func give(id: int, to_id: int) -> bool:
	var it = item_by_id(id)
	if it == null or not can_give(it):
		GameState.notify("Worn gear is bound to you and can't be given.")
		return false
	var to_name = Net.name_of(to_id)
	if not it.has("story"):
		it.story = {}
	it.story.given_to = to_name
	items.erase(it)
	save()
	Net.give_item(to_id, it)
	Story.add("Gave %s to %s." % [Story.display_name(it), to_name])
	Traits.on_gave_gear(to_name)
	GameState.notify("Gave %s to %s" % [it.name, to_name])
	return true


## A friend gave me something.
func receive_item(it: Dictionary, from_name: String):
	it.id = next_id
	next_id += 1
	if not it.has("story"):
		it.story = {}
	it.story.given_to = Story.player_name
	it.story.given_by = from_name
	it.erase("bound_to")
	items.append(it)
	save()
	Story.add("%s gave you %s." % [from_name, Story.display_name(it)])
	GameState.notify("%s gave you %s!" % [from_name, it.name])


func item_by_id(id: int):
	for it in items:
		if it.id == id:
			return it
	return null


## Make sure every slot your race has exists, and drop anything your race can't wear.
func ensure_slots():
	# Everything currently worn, in order (so switching race or world keeps what still fits)
	var worn = []
	for k in equipped:
		for id in equipped[k]:
			if id != -1 and item_by_id(id) != null and not worn.has(id):
				worn.append(id)
	var fresh = {}
	for rs in SkinManager.race_slots():
		var arr = []
		arr.resize(rs.count)
		arr.fill(-1)
		var spot = 0
		for id in worn.duplicate():
			if spot >= rs.count:
				break
			if item_by_id(id).slot == rs.accepts:
				arr[spot] = id
				spot += 1
				worn.erase(id)
		fresh[rs.slot] = arr
	equipped = fresh


## Where an item could go for this race: [race slot id, accepts]
func slot_for(item: Dictionary):
	for rs in SkinManager.race_slots():
		if rs.accepts == item.slot:
			return rs
	return null


func is_equipped(id: int) -> bool:
	for k in equipped:
		if equipped[k].has(id):
			return true
	return false


## Put an item on. Fills an empty spot; if all are full, swaps out the first one.
## Returns false if your race can't wear this kind of item.
func equip(id: int) -> bool:
	var it = item_by_id(id)
	if it == null or is_equipped(id):
		return false
	var rs = slot_for(it)
	if rs == null:
		return false
	var arr = equipped[rs.slot]
	var spot = arr.find(-1)
	arr[0 if spot == -1 else spot] = id
	if not it.has("bound_to"):	# worn gear is yours for good (it can't be given away after this)
		it.bound_to = Story.player_name
	Story.on_equip(it)
	save()
	return true


func unequip(id: int):
	for k in equipped:
		var i = equipped[k].find(id)
		if i != -1:
			equipped[k][i] = -1
	save()


func equipped_weapon():
	for k in equipped:
		for id in equipped[k]:
			var it = item_by_id(id)
			if it and it.slot == "weapon":
				return it
	return null


func equipped_items() -> Array:
	var out = []
	for k in equipped:
		for id in equipped[k]:
			var it = item_by_id(id)
			if it:
				out.append(it)
	return out


## Everything your worn armor pieces add up to (all slots, all rings).
func armor_totals() -> Dictionary:
	var a = {}
	var hardness = 0.0
	var move = 0.0
	for it in equipped_items():
		if it.slot == "weapon" or it.slot == "potion":
			continue
		var stats = recipe(it.base).stats
		hardness += stats.hardness
		move += stats.move
		for k in it.attrs:
			a[k] = a.get(k, 0.0) + it.attrs[k]
	var e = {resist = {}}
	var phys = hardness + a.get("hardness", 0.0) + a.get("physical", 0.0)
	if phys > 0.0:
		e.resist["physical"] = phys / (phys + 20.0)
	for el in ELEMENTS:
		if el != "physical" and a.get(el, 0.0) > 0.0:
			e.resist[el] = a[el] / (a[el] + 20.0)
	e.move = move + a.get("swiftness", 0.0) * 0.02
	e.max_health = a.get("vitality", 0.0) * 4.0
	return e


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
	var base = recipe(item.base)
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
		"head", "shoulders", "chest", "hands", "feet", "ring":
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
				lines.append("+%d %s damage per hit" % [e.element_bonus[el], SkinManager.element_label(el)])
			if e.lifesteal > 0.0:
				lines.append("Heals %.1f per hit" % e.lifesteal)
		"head", "shoulders", "chest", "hands", "feet", "ring":
			for el in e.resist:
				lines.append("Resists %d%% %s" % [roundi(e.resist[el] * 100), SkinManager.element_label(el)])
			if e.move != 0.0:
				lines.append("Move speed %+d%%" % roundi(e.move * 100))
			if e.max_health > 0.0:
				lines.append("+%d max health" % e.max_health)
		"potion":
			lines.append("Heals %d" % e.heal)
			for el in e.ward:
				lines.append("Ward: resist %d%% %s for 30s" % [roundi(e.ward[el] * 100), SkinManager.element_label(el)])
			if e.haste > 0.0:
				lines.append("Haste +%d%% for 30s" % roundi(e.haste * 100))
	lines.append_array(Story.item_lines(item))
	if item.has("made_from"):
		var made = "Made from " + ", ".join(item.made_from)
		if item.has("made_on"):
			made += "  (%s, %s quality)" % [item.made_on, item.made_in]
		lines.append(made)
	var where = slot_for(item)
	if item.slot != "potion" and where == null:
		lines.append("(Your race can't wear this.)")
	return "\n".join(lines)


# ---------- Enemy damage types per zone ----------
const ZONE_ELEMENTS = {
	"res://Zone1.tscn": ["physical"],
	"res://Zone2.tscn": ["physical", "physical", "physical", "radiant"],
	"res://Zone3.tscn": ["physical", "physical", "shadow", "storm"],
	"res://Zone4.tscn": ["physical", "nature", "storm", "radiant"],
	"res://Zone5.tscn": ["physical", "shadow", "nature", "storm"],
	"res://Zone6.tscn": ["radiant", "shadow", "nature", "storm"],
	"res://Zone7.tscn": ["storm", "storm", "shadow", "radiant"],
	"res://Zone8.tscn": ["nature", "nature", "shadow", "storm"],
	"res://Zone9.tscn": ["shadow", "shadow", "radiant", "nature"],
	"res://Zone10.tscn": ["radiant", "shadow", "nature", "storm"],
}

## Pick a damage type for an enemy in this zone. Bosses always carry the zone's element.
func roll_enemy_element(scene_path: String, is_boss: bool) -> String:
	var list = ZONE_ELEMENTS.get(scene_path, ["physical", "physical", ELEMENTS[1 + randi() % 4]])
	if is_boss:
		var special = list.filter(func(x): return x != "physical")
		if special.size() > 0:
			return special[randi() % special.size()]
	return list[randi() % list.size()]
