extends Node
## Autoload "Classes": every playable class comes from a .json file. No class is hard-coded.
##
## Built-in classes:  res://classes/*.json
## Mods:              res://mods/classes/*.json  and  user://mods/classes/*.json
## A mod file with the same "id" as a built-in class replaces it.
##
## A class file sets: name, role, about, stats (health/speed multipliers), energy rules,
## and skills on E, Q and F. Each skill names an EFFECT (a building block in skill_runner.gd)
## plus its numbers ("params"). "per_rank" adds to those numbers each rank.
## Advanced mods can point a skill at their own script:  "effect": "script", "script": "res://mods/my_skill.gd"
##
## Skills rank up by USE (practice), not talent points. Ranks are saved per class.
## Skins (worlds) can rename classes and skills: "classes": {"healer": "Cleric"}, "skills": {"life_drain": "Siphon"}

const DIRS := ["res://classes/", "res://mods/classes/", "user://mods/classes/"]
var RANKS_PATH: String:	# this character's save (Account)
	get:
		return Account.path("classes.cfg")
const OLD_IDS := ["dps", "tank", "healer"]	# saves from before classes were files used 0, 1, 2
const KEYS := ["E", "Q", "F"]
const RANK_USES := [0, 10, 30, 70, 150]	# total uses needed for rank 1, 2, 3, 4, 5
const EFFECTS := ["heal_self", "damage_boost", "shield", "blast", "thorns_aura", "drain_aura",
	"mending", "dash", "whirlwind", "totem", "root_field", "turn_chain", "feast", "script"]

signal rank_up(class_id, key, rank)

var classes := {}	# id -> class data
var uses := {}		# "class_id:key" -> times used


func _ready():
	DirAccess.make_dir_recursive_absolute("user://mods/classes/")
	for d in DIRS:
		_load_folder(d)
	if classes.is_empty():
		ErrorLog.fail("No classes found in res://classes/ - the game can't start without them")
	load_character()
	print("Classes: ", ids())


## Skill ranks belong to the character.
func load_character():
	uses = {}
	var cfg = ConfigFile.new()
	if cfg.load(RANKS_PATH) == OK:
		uses = cfg.get_value("ranks", "uses", {})


## Class ids sorted by their "order" number (mods without one go last).
func ids() -> Array:
	var list = classes.keys()
	list.sort_custom(func(a, b): return classes[a].get("order", 99) < classes[b].get("order", 99))
	return list


## Turns an old number (0, 1, 2) or an unknown id into a real class id.
func normalize(id) -> String:
	if id is int or id is float:
		id = OLD_IDS[clampi(int(id), 0, 2)]
	if classes.has(id):
		return id
	if not classes.is_empty():
		ErrorLog.warn("Unknown class '%s' - using '%s'" % [id, ids()[0]])
		return ids()[0]
	return "dps"


func get_def(id: String) -> Dictionary:
	return classes.get(normalize(id), {})


## Name shown to the player: skin name first, then the class file's name.
func label(id: String) -> String:
	var names = SkinManager.section("classes")
	if names is Dictionary and names.has(id):
		return names[id]
	if names is Array:	# old skin style: [dps, tank, healer]
		var i = OLD_IDS.find(id)
		if i >= 0 and i < names.size():
			return names[i]
	return get_def(id).get("name", id.capitalize())


func skill(class_id: String, key: String) -> Dictionary:
	return get_def(class_id).get("skills", {}).get(key, {})


func skill_label(class_id: String, key: String) -> String:
	var s = skill(class_id, key)
	var names = SkinManager.section("skills")
	if names is Dictionary and names.has(s.get("id", "")):
		return names[s.id]
	return s.get("name", key)


# ---------------- Ranks (practice) ----------------

func rank(class_id: String, key: String) -> int:
	var n = uses.get(class_id + ":" + key, 0)
	var r = 1
	for i in range(RANK_USES.size()):
		if n >= RANK_USES[i]:
			r = i + 1
	return r


## "12 / 30 uses to rank 3" (or "max rank")
func rank_progress(class_id: String, key: String) -> String:
	var r = rank(class_id, key)
	if r >= RANK_USES.size():
		return "max rank"
	return "%d / %d uses to rank %d" % [uses.get(class_id + ":" + key, 0), RANK_USES[r], r + 1]


func record_use(class_id: String, key: String):
	var k = class_id + ":" + key
	var before = rank(class_id, key)
	uses[k] = uses.get(k, 0) + 1
	var after = rank(class_id, key)
	if after > before:
		rank_up.emit(class_id, key, after)
		GameState.notify("%s reached rank %d!" % [skill_label(class_id, key), after])
	var cfg = ConfigFile.new()
	cfg.set_value("ranks", "uses", uses)
	cfg.save(RANKS_PATH)


## A skill's numbers at the current rank: params + per_rank x (rank - 1).
func params_at_rank(class_id: String, key: String) -> Dictionary:
	var s = skill(class_id, key)
	var p = s.get("params", {}).duplicate()
	var r = rank(class_id, key)
	var per = s.get("per_rank", {})
	for k in per:
		p[k] = p.get(k, 0.0) + per[k] * (r - 1)
	return p


# ---------------- Loading ----------------

func _load_folder(path: String):
	var dir = DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path + file))
		if not data is Dictionary:
			ErrorLog.fail("Class file has a mistake (bad JSON) and was skipped: " + path + file)
			continue
		if _check(data, path + file):
			if classes.has(data.id):
				print("Class '%s' replaced by %s" % [data.id, path + file])
			classes[data.id] = data


## Loud checks so a broken mod says exactly what's wrong.
func _check(c: Dictionary, where: String) -> bool:
	if not c.has("id") or not c.has("skills"):
		ErrorLog.fail("Class file needs an \"id\" and \"skills\": " + where)
		return false
	var ok = true
	for key in KEYS:
		if not c.skills.has(key):
			ErrorLog.fail("Class '%s' has no %s skill (%s)" % [c.id, key, where])
			ok = false
			continue
		var s = c.skills[key]
		var effect = s.get("effect", "")
		if not effect in EFFECTS:
			ErrorLog.fail("Class '%s' skill %s: unknown effect '%s'. Known: %s (%s)" % [c.id, key, effect, ", ".join(EFFECTS), where])
			ok = false
		elif effect == "script" and not ResourceLoader.exists(s.get("script", "")):
			ErrorLog.fail("Class '%s' skill %s: script not found '%s' (%s)" % [c.id, key, s.get("script", ""), where])
			ok = false
		if not s.has("id"):
			s.id = c.id + "_" + key.to_lower()
	return ok
