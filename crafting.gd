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
##  - Quality multiplies every attribute by 1.25 per level (no upper limit), AND the item's own power
##    (weapon damage, armor hardness, potion healing): same recipe, better metal = a stronger item.
##
## WEAPON TYPES: Sword, Saber, Katana, Zweihander, Cleaver, Greataxe, Spear, Halberd, Mace, Dagger.
##   Each one always plays the same way (speed, reach, sweep width); materials decide how strong it is.
##
## THE SHRINE LADDER (trials.gd) alternates, for every trial kind:
##   odd levels  (I, III, V, VII)   a better RECIPE for its family (Precision: every weapon type)
##   even levels (II, IV, VI, VIII) a better MATERIAL: Treasured, then Heirloom, Legendary, Mythic.
##   Special materials are made at the Smith / Chemist from plain ones. They're much stronger and each
##   family carries a SPECIAL EFFECT (gear_fx.gd): Ingot = Sunder, Tulip = Bloom, Gem = Prism,
##   Treesilver = Gale, Orchid = Thornskin. Put them in any creative slot.

signal changed

var SAVE_PATH: String:	# this character's save (Account)
	get:
		return Account.path("crafting.cfg")

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
	"geode": {to = "gem", cost = 2, shop = "smith"},	# caverns only
}

# Names per quality (add more as zones are added; past the list it shows "Ingot (Quality N)")
const MATERIAL_NAMES = {
	"ingot": ["Copper ingot", "Iron ingot", "Silver ingot", "Mithril ingot", "Starmetal ingot", "Adamant ingot", "Orichalcum ingot", "Sunsteel ingot", "Voidsteel ingot"],
	"silverbar": ["Young Treesilver bar", "Elder Treesilver bar", "Ancient Treesilver bar", "Heartwood Treesilver bar", "World Treesilver bar", "Star Treesilver bar", "Dream Treesilver bar", "Crown Treesilver bar", "First Treesilver bar"],
	"tonic": ["Sunleaf tonic", "Moonleaf tonic", "Dawnroot tonic", "Duskbloom tonic", "Starpetal tonic", "Emberleaf tonic", "Frostfern tonic", "Ghostcap tonic", "Worldroot tonic"],
	"essence": ["Pale Orchid essence", "Storm Orchid essence", "Ember Orchid essence", "Frost Orchid essence", "Void Orchid essence", "Sun Orchid essence", "Moon Orchid essence", "Star Orchid essence", "Dawn Orchid essence"],
	"gem": ["Dull gem", "Clouded gem", "Bright gem", "Starlit gem", "Deep gem", "Heart gem", "Abyssal gem", "Prism gem", "Void gem"],
}
const MATERIAL_LABELS = {"gem": "Gem", "ingot": "Ingot", "silverbar": "Treesilver bar", "tonic": "Tonic", "essence": "Orchid essence",
	"sigil_precision": "Sigil of Precision", "sigil_numbers": "Sigil of Numbers", "sigil_sorting": "Sigil of Color",
	"sigil_typing": "Sigil of Swiftness", "sigil_logic": "Sigil of Logic"}

# Herbs and orchids change element as quality rises (and keep cycling past the list)
const HERB_ELEMENTS = ["radiant", "shadow", "nature", "storm"]
const ORCHID_ELEMENTS = ["nature", "storm", "radiant", "shadow"]

# Single strikes hit much harder than sweeps (Oct 2026): strikes for big foes, sweeps for crowds.
const ST_MULT = 1.5
const AOE_MULT = 0.75
const QUALITY_POWER = 1.25	# each quality step: the item itself is this much stronger (and so is every attribute)

# ---------- Base recipes ----------
# need: {material: count}  The quality you pick applies to the main material.
const BASES = {
	# Weapons (cone: lower = a wider sweep; auto_sweep: auto-attack sweeps once this many are close)
	"blade": {label = "Sword", shop = "smith", slot = "weapon", need = {"ingot": 2}, slots = 2,
		stats = {st = 100.0, aoe = 50.0, cone = 0.3, targets = 4, st_cd = 2.0, aoe_cd = 1.0, reach = 10.0, auto_sweep = 3},
		about = "Balanced. Auto-attack sweeps at 3+ enemies."},
	"saber": {label = "Saber", shop = "smith", slot = "weapon", need = {"ingot": 2}, slots = 2,
		stats = {st = 85.0, aoe = 45.0, cone = 0.1, targets = 5, st_cd = 1.6, aoe_cd = 0.9, reach = 9.0, auto_sweep = 3},
		about = "Quick, wide slashes. Auto-attack sweeps at 3+ enemies."},
	"katana": {label = "Katana", shop = "smith", slot = "weapon", need = {"ingot": 2}, slots = 2,
		stats = {st = 110.0, aoe = 40.0, cone = 0.4, targets = 3, st_cd = 1.6, aoe_cd = 1.1, reach = 11.0, auto_sweep = 4},
		about = "Fast, hard strikes and a narrow sweep. Auto-attack sweeps at 4+ enemies."},
	"zweihander": {label = "Zweihander", shop = "smith", slot = "weapon", need = {"ingot": 4}, slots = 2,
		stats = {st = 140.0, aoe = 90.0, cone = -0.2, targets = 7, st_cd = 2.8, aoe_cd = 1.8, reach = 13.0, auto_sweep = 2},
		about = "Huge and slow: the widest, longest sweeps. Auto-attack sweeps at 2+ enemies."},
	"cleaver": {label = "Cleaver", shop = "smith", slot = "weapon", need = {"ingot": 3}, slots = 2,
		stats = {st = 80.0, aoe = 75.0, cone = 0.0, targets = 7, st_cd = 2.4, aoe_cd = 1.3, reach = 9.0, auto_sweep = 2},
		about = "Wide, heavy sweeps. Slower. Auto-attack sweeps at just 2+ enemies."},
	"spear": {label = "Spear", shop = "smith", slot = "weapon", need = {"ingot": 2}, slots = 2,
		stats = {st = 140.0, aoe = 30.0, cone = 0.6, targets = 2, st_cd = 1.8, aoe_cd = 1.0, reach = 14.0, auto_sweep = 5},
		about = "Long reach, narrow sweep. Auto-attack only sweeps at 5+ enemies: it mostly strikes."},
	"greataxe": {label = "Greataxe", shop = "smith", slot = "weapon", need = {"ingot": 4}, slots = 2,
		stats = {st = 125.0, aoe = 100.0, cone = -0.1, targets = 9, st_cd = 3.0, aoe_cd = 2.0, reach = 10.0, auto_sweep = 2},
		about = "Crushing, slow sweeps that cut through a crowd. Auto-attack sweeps at 2+ enemies."},
	"halberd": {label = "Halberd", shop = "smith", slot = "weapon", need = {"ingot": 3}, slots = 2,
		stats = {st = 130.0, aoe = 65.0, cone = 0.2, targets = 5, st_cd = 2.2, aoe_cd = 1.4, reach = 15.0, auto_sweep = 3},
		about = "Long reach AND a solid sweep, but slow. Auto-attack sweeps at 3+ enemies."},
	"mace": {label = "Mace", shop = "smith", slot = "weapon", need = {"ingot": 3}, slots = 2,
		stats = {st = 115.0, aoe = 55.0, cone = 0.3, targets = 4, st_cd = 2.2, aoe_cd = 1.2, reach = 9.0, auto_sweep = 3, stun_chance = 0.15},
		about = "Heavy blows: strikes have a 15% chance to stun for a second. Auto-attack sweeps at 3+ enemies."},
	"dagger": {label = "Dagger", shop = "smith", slot = "weapon", need = {"ingot": 1}, slots = 2,
		stats = {st = 70.0, aoe = 30.0, cone = 0.5, targets = 2, st_cd = 1.0, aoe_cd = 0.7, reach = 7.0, auto_sweep = 5},
		about = "The fastest strikes, short reach. Auto-attack only sweeps at 5+ enemies."},
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
	# Skill rings (Oct 2026): small boosts to your skills that stack, made for races with lots of ring slots (Ents have 20).
	"thorn_ring": {label = "Thorn Ring", shop = "smith", slot = "ring", need = {"ingot": 2}, slots = 1,
		stats = {hardness = 0.0, move = 0.0, thorns_damage = 0.05}, about = "+5% Thorns damage. Stacks with every ring you wear."},
	"bramble_ring": {label = "Bramble Ring", shop = "smith", slot = "ring", need = {"silverbar": 1}, slots = 1,
		stats = {hardness = 0.0, move = 0.0, thorns_reach = 0.03}, about = "+3% Thorns ring size (all three rings). Stacks."},
	"deeproot_ring": {label = "Deep Root Ring", shop = "smith", slot = "ring", need = {"silverbar": 1, "ingot": 1}, slots = 1,
		stats = {hardness = 0.0, move = 0.0, planted_damage = 0.08}, about = "+8% Thorns damage while you stand still. Stacks."},
	"bark_ring": {label = "Bark Ring", shop = "smith", slot = "ring", need = {"ingot": 1, "silverbar": 1}, slots = 1,
		stats = {hardness = 0.0, move = 0.0, shield_absorb = 0.08}, about = "+8% Shield strength. Stacks."},
	"sap_ring": {label = "Sap Ring", shop = "smith", slot = "ring", need = {"silverbar": 2}, slots = 1,
		stats = {hardness = 0.0, move = 0.0, self_heal = 0.08}, about = "+8% Self Heal. Stacks."},
	# Wings: never sold. Scarlet's Wings come from beating Daddy in Zone 2 (daddy.gd, grant_wings).
	"scarlet_wings": {label = "Scarlet's Wings", shop = "", slot = "wings", need = {}, slots = 0,
		stats = {hardness = 0.0, move = 0.0, flight = 5.0},
		about = "Scarlet's gift. Hold Shift to fly over walls, water and enemies for a few seconds. Nothing can hurt you up there, but you can't attack."},
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
	"precision": {base = "blade", label = "Masterwork Blade", any_weapon = true},	# Masterwork <any weapon>
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


## "adv:precision:3" (the family's own base) or "adv:precision:3:katana" (Precision: any weapon type).
func advanced_id(ability: String, level: int, weapon := "") -> String:
	if weapon != "" and weapon != ADVANCED[ability].base:
		return "adv:%s:%d:%s" % [ability, level, weapon]
	return "adv:%s:%d" % [ability, level]


## Weapon type ids, in shop order.
func weapon_types() -> Array:
	return BASES.keys().filter(func(id): return BASES[id].slot == "weapon")


# ---------- The shrine ladder: recipes on odd levels, special materials on even levels ----------
const TIER_WORDS = ["", "Treasured", "Heirloom", "Legendary", "Mythic"]
const TREASURE = {precision = "ingot", numbers = "essence", sorting = "gem", typing = "silverbar", logic = "tonic"}	# trial kind -> its special material
const TREASURE_NICK = {ingot = "Ingot", tonic = "Tulip", gem = "Gem", silverbar = "Treesilver", essence = "Orchid"}
const FX = {ingot = "sunder", tonic = "bloom", gem = "prism", silverbar = "gale", essence = "thornskin"}	# each special material's effect (gear_fx.gd)
const FX_WORDS = {sunder = "Sundering", bloom = "Blooming", prism = "Prismatic", gale = "Galeborn", thornskin = "Thorned"}


## The best recipe level a trial kind has taught you: I, III, V, VII (0 = none yet).
func recipe_level(ability: String) -> int:
	var l = Trials.level(ability)
	return l if l % 2 == 1 else l - 1


## The best special material a trial kind has taught you: 1 Treasured (level II) ... 4 Mythic (VIII). 0 = none.
func material_tier(ability: String) -> int:
	return int(Trials.level(ability) / 2)


## What earning level `level` of a trial kind gives you (for the Sigil message).
func ladder_reward_text(ability: String, level: int) -> String:
	if level % 2 == 1:
		var fam = ADVANCED[ability]
		var what = "Masterwork weapons %s (any weapon type)" % ROMAN[level] if fam.get("any_weapon", false) else recipe(advanced_id(ability, level)).label
		return "New recipe: %s." % what
	var base = TREASURE[ability]
	return "New material: %s %s (make it at the %s from %d %s)." % [TIER_WORDS[level / 2], TREASURE_NICK[base],
		"Smith" if _refine_shop(base) == "smith" else "Chemist", treasure_cost(level / 2), MATERIAL_LABELS.get(base, base)]


func is_treasured(mat: String) -> bool:
	return mat.length() > 3 and mat[0] == "t" and mat[1].is_valid_int() and mat[2] == "_"


func treasure_cost(tier: int) -> int:
	return 2 + 2 * tier		# plain units of the same quality: 4, 6, 8, 10


func treasure_gold(tier: int) -> int:
	return 10 * tier


func _refine_shop(material: String) -> String:
	for raw in REFINE:
		if REFINE[raw].to == material:
			return REFINE[raw].shop
	return ""


## Special materials this shop can make right now: [{ability, base, q, tier, have, cost, gold, name, result, fx}]
func treasure_options(shop: String) -> Array:
	var out = []
	for ability in TREASURE:
		var tier = material_tier(ability)
		var base = TREASURE[ability]
		if tier < 1 or _refine_shop(base) != shop:
			continue
		for e in stash_list():
			if e.mat != base:
				continue
			out.append({ability = ability, base = base, q = e.q, tier = tier, have = e.count, cost = treasure_cost(tier),
				gold = treasure_gold(tier), name = e.name, result = material_name("t%d_%s" % [tier, base], e.q), fx = FX[base]})
	return out


## Make one special material from plain ones (banked gold too). Returns true if made.
func make_treasure(base: String, q: int, tier: int) -> bool:
	if stash_count(base, q) < treasure_cost(tier) or not GameState.spend_gold(treasure_gold(tier)):
		return false
	_take(base, q, treasure_cost(tier))
	var key = "t%d_%s:%d" % [tier, base, q]
	stash[key] = stash.get(key, 0) + 1
	save()
	Traits.on_refine()	# Keeper
	return true


## A readable name for an attribute: "Hardness", "Shadow", "Sunder".
func attr_label(k: String) -> String:
	if k.begins_with("fx_"):
		return k.substr(3).capitalize()
	if k in ELEMENTS:
		return SkinManager.element_label(k)
	return k.capitalize()


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
	if bits.size() < 3 or bits.size() > 4 or bits[0] != "adv" or not ADVANCED.has(bits[1]):
		ErrorLog.fail("Unknown recipe id: " + id)
		return BASES.blade
	var ability = bits[1]
	var level = clampi(int(bits[2]), 1, 8)
	var fam = ADVANCED[ability]
	var base_id = fam.base
	if bits.size() == 4:
		if not fam.get("any_weapon", false) or not BASES.has(bits[3]) or BASES[bits[3]].slot != "weapon":
			ErrorLog.fail("Unknown recipe id: " + id)
			return BASES.blade
		base_id = bits[3]
	var b = BASES[base_id].duplicate(true)
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
		st.move = 0.03 + 0.015 * level	# (walking through enemies moved to wings: flying)
	if fam.has("move"):
		st.move = fam.move
	b.slots = mini(b.slots + 1 + int(level / 2.0), 6)
	b.label = "%s %s" % [("Masterwork " + BASES[base_id].label) if fam.get("any_weapon", false) else fam.label, ROMAN[level]]
	b.weapon_type = base_id
	b.about = "Level %d recipe (from %s trials): power x%.1f, %d creative slots." % [level, ability.capitalize(), m, b.slots]
	b.advanced = true
	b.ability = ability
	b.level = level
	_adv_cache[id] = b
	return b

var _adv_cache = {}


## Recipe ids a shop shows: its basic ones, plus the best recipe level the shrines have taught you
## (odd levels: I, III, V, VII). Precision's Masterwork recipe works for every weapon type.
func shop_recipes(shop: String) -> Array:
	var out = []
	for id in BASES:
		if BASES[id].shop == shop:
			out.append(id)
	for ability in ADVANCED:
		var l = recipe_level(ability)
		if l <= 0:
			continue
		if ADVANCED[ability].get("any_weapon", false):
			for w in weapon_types():
				if BASES[w].shop == shop:
					out.append(advanced_id(ability, l, w))
		elif recipe(advanced_id(ability, l)).shop == shop:
			out.append(advanced_id(ability, l))
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
	load_character()
	SkinManager.skin_changed.connect(ensure_slots)


func load_character():
	stash = {}
	items = []
	equipped = {}
	next_id = 1
	patterns = []
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		stash = cfg.get_value("crafting", "stash", {})
		items = cfg.get_value("crafting", "items", [])
		equipped = cfg.get_value("crafting", "equipped", {})
		next_id = cfg.get_value("crafting", "next_id", 1)
		patterns = cfg.get_value("crafting", "patterns", [])
	_upgrade_old_save()
	ensure_slots()
	changed.emit()


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
	if is_treasured(mat):	# "Treasured Tulip (Moonleaf)"
		var base = mat.substr(3)
		var words = material_name(base, q).split(" ")
		return "%s %s (%s)" % [TIER_WORDS[clampi(int(mat[1]), 1, 4)], TREASURE_NICK.get(base, base.capitalize()), " ".join(words.slice(0, maxi(1, words.size() - 1)))]
	var skinned = SkinManager.list_name("materials", mat, q)
	if skinned != null:
		return skinned
	var names = MATERIAL_NAMES.get(mat, [])
	if q >= 1 and q <= names.size():
		return names[q - 1]
	return "%s (Quality %d)" % [MATERIAL_LABELS.get(mat, mat), q]


## Attributes of ONE unit of a refined material. This is the "logic" table.
func material_attributes(mat: String, q: int) -> Dictionary:
	if is_treasured(mat):	# special material: the plain one x (1 + tier), plus its family's special effect
		var tier = clampi(int(mat[1]), 1, 4)
		var base = mat.substr(3)
		var t = material_attributes(base, q)
		for k in t:
			t[k] *= 1.0 + tier
		t["fx_" + FX.get(base, "sunder")] = tier * (1.0 + 0.1 * (q - 1))
		return t
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
		"gem":			# from cavern geodes: hard, and a strong element (great in creative slots)
			a = {hardness = 2.0}
			a[ORCHID_ELEMENTS[q % ORCHID_ELEMENTS.size()]] = 6.0
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
	var keys = GameState.satchel.keys()
	for k in GameState.storehouse:	# banked raw resources refine too
		if not k in keys:
			keys.append(k)
	keys.sort()
	for key in keys:
		var bits = key.split(":")
		var raw = bits[0]
		var q = int(bits[1])
		if not REFINE.has(raw) or REFINE[raw].shop != shop:
			continue
		var have = GameState.raw_count(key)
		out.append({raw = raw, q = q, have = have, cost = REFINE[raw].cost, to = REFINE[raw].to,
			name = GameState.resource_name(raw, q), result = material_name(REFINE[raw].to, q)})
	return out


func refine(raw: String, q: int) -> bool:
	var key = "%s:%d" % [raw, q]
	var cost = REFINE[raw].cost
	if not GameState.take_raw(key, cost):
		return false
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
	var fx_word = ""
	for k in attrs:
		if k.begins_with("fx_"):
			fx_word = FX_WORDS.get(k.substr(3), "")
	if fx_word != "":	# a special material outshines everything else in the name
		title = fx_word + " " + title
	elif strongest != "":
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


## Daddy is down (daddy.gd): your first wings. Returns false if you already have them.
func grant_wings() -> bool:
	if items.any(func(it): return it.base == "scarlet_wings"):
		return false
	var item = {base = "scarlet_wings", slot = "wings", quality = 1, name = "Scarlet's Wings", attrs = {},
		made_from = ["a gift for beating Daddy"]}
	Story.stamp_crafted(item, "scarlet_wings")
	item.id = next_id
	next_id += 1
	item.made_on = Time.get_date_string_from_system()
	item.made_in = GameState.ZONE_NAMES.get("res://Zone2.tscn", "Zone 2")
	items.append(item)
	var rs = slot_for(item)	# straight onto your back
	if rs and equipped.has(rs.slot) and equipped[rs.slot].has(-1):
		equipped[rs.slot][equipped[rs.slot].find(-1)] = item.id
	save()
	return true


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
## slot_id / at: put it in that exact spot (the paper doll). Returns false if your race can't wear it there.
func equip(id: int, slot_id := "", at := -1) -> bool:
	var it = item_by_id(id)
	if it == null or is_equipped(id):
		return false
	var rs = slot_for(it)
	if slot_id != "":
		rs = null
		for r in SkinManager.race_slots():
			if r.slot == slot_id and r.accepts == it.slot:
				rs = r
	if rs == null:
		return false
	var arr = equipped[rs.slot]
	var spot = arr.find(-1)
	if at >= 0 and at < arr.size():
		spot = at
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


## One attribute (swiftness, vitality...) added up across EVERYTHING worn, weapon included.
func gear_attr(attr: String) -> float:
	var total = 0.0
	for it in equipped_items():
		if it.slot != "potion":
			total += it.attrs.get(attr, 0.0)
	return total


## Skill-ring stats (thorns_damage, shield_absorb...) added up across everything worn.
## Returns a bonus share: 0.25 means +25%.
func gear_stat(key: String) -> float:
	if not SKILL_STATS.has(key):
		ErrorLog.fail("gear_stat: unknown skill stat " + key)
		return 0.0
	var total = 0.0
	for it in equipped_items():
		if it.slot != "potion":
			total += float(recipe(it.base).stats.get(key, 0.0))
	return total

const SKILL_STATS = {
	"thorns_damage": "Thorns damage", "thorns_reach": "Thorns ring size", "planted_damage": "Thorns damage while standing still",
	"shield_absorb": "Shield strength", "self_heal": "Self Heal",
}


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
	var phase_mobs = false
	var flight = 0.0
	for it in equipped_items():
		if it.slot == "weapon" or it.slot == "potion":
			continue
		var stats = recipe(it.base).stats
		hardness += stats.hardness * pow(QUALITY_POWER, maxi(0, int(it.get("quality", 1)) - 1))
		move += stats.move
		if stats.get("phase_mobs", false):
			phase_mobs = true
		flight = maxf(flight, float(stats.get("flight", 0.0)))	# wings
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
	e.phase_mobs = phase_mobs
	e.flight = flight
	e.fx = {}
	for k in a:
		if k.begins_with("fx_"):
			e.fx[k.substr(3)] = a[k]
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
	var qp = pow(QUALITY_POWER, maxi(0, int(item.get("quality", 1)) - 1))	# better metal, stronger item
	var e = {fx = {}}
	for k in a:	# special effects (from special materials), any item but potions
		if k.begins_with("fx_") and item.slot != "potion":
			e.fx[k.substr(3)] = e.fx.get(k.substr(3), 0.0) + a[k]
	match item.slot:
		"weapon":
			var hard = a.get("hardness", 0.0)
			e.st = (s.st * qp + hard * 6.0 + a.get("physical", 0.0) * 5.0) * ST_MULT
			e.aoe = (s.aoe * qp + hard * 3.0 + a.get("physical", 0.0) * 2.5) * AOE_MULT
			e.stun_chance = float(s.get("stun_chance", 0.0))
			e.cone = s.cone
			e.targets = s.targets
			e.reach = s.reach
			e.auto_sweep = int(s.get("auto_sweep", 3))
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
			var phys = s.hardness * qp + a.get("hardness", 0.0) + a.get("physical", 0.0)
			e.resist["physical"] = phys / (phys + 20.0)
			for el in ELEMENTS:
				if el != "physical" and a.get(el, 0.0) > 0.0:
					e.resist[el] = a[el] / (a[el] + 20.0)
			e.move = s.move + a.get("swiftness", 0.0) * 0.02
			e.max_health = a.get("vitality", 0.0) * 4.0
		"wings":
			e.flight = float(s.get("flight", 0.0))
		"potion":
			e.heal = s.heal * qp + a.get("vitality", 0.0) * 8.0
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
			lines.append("Hit %d / Sweep %d   (reach %d, sweep up to %d)" % [e.st, e.aoe, e.reach * 2, e.targets])	# strikes reach 2x (player REACH_MULT)
			lines.append("Attack time %.1fs / %.1fs" % [e.st_cd, e.aoe_cd])
			for el in e.element_bonus:
				lines.append("+%d %s damage per hit" % [e.element_bonus[el], SkinManager.element_label(el)])
			if e.lifesteal > 0.0:
				lines.append("Heals %.1f per hit" % e.lifesteal)
			if e.stun_chance > 0.0:
				lines.append("Strikes: %d%% chance to stun" % roundi(e.stun_chance * 100))
			lines.append_array(preload("res://gear_fx.gd").describe(e.fx))
		"head", "shoulders", "chest", "hands", "feet", "ring":
			for el in e.resist:
				lines.append("Resists %d%% %s" % [roundi(e.resist[el] * 100), SkinManager.element_label(el)])
			if e.move != 0.0:
				lines.append("Move speed %+d%%" % roundi(e.move * 100))
			if recipe(item.base).stats.get("phase_mobs", false):
				lines.append("Walk through enemies")
			if e.max_health > 0.0:
				lines.append("+%d max health" % e.max_health)
			lines.append_array(preload("res://gear_fx.gd").describe(e.fx))
			var rs = recipe(item.base).stats
			for k in SKILL_STATS:
				if rs.get(k, 0.0) > 0.0:
					lines.append("+%d%% %s" % [roundi(rs[k] * 100), SKILL_STATS[k]])
		"wings":
			lines.append("Hold Shift to fly for %ds (refills on the ground)" % roundi(e.flight))
			lines.append("Up there: over walls, water and enemies, and nothing can hurt you (no attacking)")
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
const REGION_ELEMENT_SHARE = 0.5	# zones with regions: this share of enemies use their region's element
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
## In a zone with regions, pass where it stands: half the time it uses its region's element.
func roll_enemy_element(scene_path: String, is_boss: bool, pos = null) -> String:
	if pos != null and not is_boss and randf() < REGION_ELEMENT_SHARE:
		var r = Regions.at(scene_path, pos)
		if not r.is_empty():
			return r.element
	var list = ZONE_ELEMENTS.get(scene_path, ["physical", "physical", ELEMENTS[1 + randi() % 4]])
	if is_boss:
		var special = list.filter(func(x): return x != "physical")
		if special.size() > 0:
			return special[randi() % special.size()]
	return list[randi() % list.size()]
