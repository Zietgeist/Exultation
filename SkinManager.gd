extends Node
## Holds the current skin: colors and names for each game ID.
## Game code asks SkinManager instead of hard-coding looks.
## A skin is a whole WORLD: enemy names and colors, class names, damage type names,
## resource names and looks (props), and the playable RACES with their gear slots.
## Built-in skins live in res://skins/. Players can add their own .json skins to user://skins/.
## Anything missing from a skin falls back to the Default skin.
## Press F9 in game to switch skins (test key).

signal skin_changed

const BUILTIN_DIR := "res://skins/"
const PLAYER_DIR := "user://skins/"
const SETTINGS_PATH := "user://settings.cfg"

var skins := {}	# skin id -> skin data (Dictionary)
var current_id := "default"
var current_race := ""	# race id within the current skin
var race_by_skin := {}	# skin id -> the race you last picked in it (switching worlds and back keeps your race)
var _materials := {}	# id -> shared material (one per color, so hundreds of enemies share it)


func _ready():
	DirAccess.make_dir_recursive_absolute(PLAYER_DIR)
	_load_folder(BUILTIN_DIR)
	_load_folder(PLAYER_DIR, true)
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		current_id = cfg.get_value("skin", "id", "default")
		current_race = cfg.get_value("skin", "race", "")
		race_by_skin = cfg.get_value("skin", "race_by_skin", {})
	if not skins.has(current_id):
		current_id = "default"
	_check_race()
	print("Skin: ", skin_name(), "  (skins found: ", skins.keys(), ")")


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		next_skin()


## Color for a game ID, e.g. color("enemy_trash")
## One shared material per game ID (much faster than a new material for every enemy).
func material(id: String, fallback := Color.WHITE) -> StandardMaterial3D:
	if not _materials.has(id):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color(id, fallback)
		_materials[id] = mat
	return _materials[id]


## Same as material(), plus a glow showing the enemy's damage type.
func element_material(id: String, fallback: Color, element: String, glow: Color) -> StandardMaterial3D:
	var key = id + ":" + element
	if not _materials.has(key):
		var mat = StandardMaterial3D.new()
		mat.albedo_color = color(id, fallback)
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = 0.6
		_materials[key] = mat
	return _materials[key]


func color(id: String, fallback := Color.WHITE) -> Color:
	var hex = _lookup("colors", id)
	if hex == null:
		return fallback
	return Color(hex)


## Display name for a game ID, e.g. name_of("enemy_boss")
func name_of(id: String) -> String:
	var n = _lookup("names", id)
	if n == null:
		return id
	return n


func skin_name() -> String:
	return skins.get(current_id, {}).get("name", current_id)


func set_skin(id: String):
	if not skins.has(id):
		return
	if current_race != "":
		race_by_skin[current_id] = current_race
	current_id = id
	current_race = race_by_skin.get(id, current_race)	# back to the race you had in this world
	_check_race()
	_save_settings()
	print("Skin changed to: ", skin_name())
	_materials.clear()
	skin_changed.emit()


func next_skin():
	var ids = skins.keys()
	ids.sort()
	var i = ids.find(current_id)
	set_skin(ids[(i + 1) % ids.size()])
	GameState.notify("World: %s  ·  Race: %s   (F9 is a test key)" % [skin_name(), race().name])


func _save_settings():
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("skin", "id", current_id)
	cfg.set_value("skin", "race", current_race)
	cfg.set_value("skin", "race_by_skin", race_by_skin)
	cfg.save(SETTINGS_PATH)


# ---------------- World data from the skin ----------------

## Everything about one section, from the current skin (falling back to Default).
func section(name: String):
	var v = skins.get(current_id, {}).get(name, null)
	if v == null:
		v = skins.get("default", {}).get(name, null)
	return v


func skin_about(id := "") -> String:
	return skins.get(id if id != "" else current_id, {}).get("about", "")


## "fantasy", "zombie" or "scifi": which look trees, hills and resource nodes use.
func props_style() -> String:
	var p = section("props")
	return p if p != null else "fantasy"


## Class display name in this world (classes live in ClassManager; old number ids still work).
func class_label(id) -> String:
	return Classes.label(Classes.normalize(id))


func element_label(element: String) -> String:
	var names = section("elements")
	if names != null and names.has(element):
		return names[element]
	return element.capitalize()


## A name from a per-quality list, e.g. list_name("resources", "ore", 1) -> "Copper ore"
func list_name(section_name: String, type: String, quality: int):
	var lists = section(section_name)
	if lists == null or not lists.has(type):
		return null
	var names = lists[type]
	if quality >= 1 and quality <= names.size():
		return names[quality - 1]
	return null


func slot_label(slot: String) -> String:
	var labels = section("slot_labels")
	if labels != null and labels.has(slot):
		return labels[slot]
	return slot.capitalize()


# ---------------- Races ----------------

func races() -> Array:
	var r = section("races")
	return r if r != null else []


func race() -> Dictionary:
	for r in races():
		if r.id == current_race:
			return r
	return races()[0] if races().size() > 0 else {"id": "none", "name": "Adventurer", "slots": [{"slot": "weapon", "count": 1}, {"slot": "chest", "count": 1}]}


func set_race(id: String):
	current_race = id
	_check_race()
	race_by_skin[current_id] = current_race
	_save_settings()
	skin_changed.emit()


## Gear slots for the current race: [{slot, accepts, count, label}]
func race_slots() -> Array:
	var out = []
	for s in race().slots:
		out.append({slot = s.slot, accepts = s.get("accepts", s.slot), count = int(s.get("count", 1)),
			label = s.get("label", slot_label(s.get("accepts", s.slot)))})
	return out


func _check_race():
	for r in races():
		if r.id == current_race:
			return
	var was = current_race
	current_race = races()[0].id if races().size() > 0 else ""
	if was != "":	# loud: your race changed under you
		ErrorLog.warn("SkinManager: race '%s' isn't in the %s world, so you're a %s now" % [was, skin_name(), current_race])


func _fill_races(data: Dictionary, builtin: Dictionary):
	var old = {}
	for r in builtin.get("races", []):
		old[r.id] = r
	for r in data.get("races", []):
		if r is Dictionary and old.has(r.get("id", "")):
			for k in old[r.id]:
				if not r.has(k):
					r[k] = old[r.id][k]


func _lookup(sec: String, id: String):
	var current = skins.get(current_id, {}).get(sec, {})
	if current.has(id):
		return current[id]
	var fallback = skins.get("default", {}).get(sec, {})
	return fallback.get(id, null)


## player = a player's own skins (user://skins/). One with the same name as a built-in world
## replaces it, but anything its races leave out (like the new "body" shapes) comes from the built-in race.
func _load_folder(path: String, player := false):
	var dir = DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".json"):
			var text = FileAccess.get_file_as_string(path + file)
			var data = JSON.parse_string(text)
			if data is Dictionary:
				var id = file.get_basename()
				if player and skins.has(id):
					ErrorLog.warn("SkinManager: your own skin %s%s replaces the built-in one" % [path, file])
					_fill_races(data, skins[id])
				skins[id] = data
			else:
				ErrorLog.fail("Skin file has a mistake and was skipped: " + path + file)
