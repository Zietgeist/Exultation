extends Node
## Autoload "Account": your saved characters on this PC.
##
## Each character is one name + world + race + class, with its OWN gold, satchel, gear, materials,
## pet, Chronicle, traits, rivals, Trial ladder, fast-travel stops and landmarks.
## Changing race or class means making a new character (the start screen does this).
##
##   user://account.cfg                    the list of characters
##   user://characters/<id>/progress.cfg   ...and the rest of that character's save files
##
## Things for the whole account stay where they were: settings (world/race last picked),
## controls, play time today (the flow clock), parties (shared with friends), mods.
##
## Every system asks Account.path("its_file.cfg") for where to save. With no character picked
## (running a scene straight from the editor) that's the old place, user://its_file.cfg.
## Old single saves are moved into a first character automatically.

const ACCOUNT_PATH = "user://account.cfg"
const DIR = "user://characters"
const PER_CHARACTER = ["progress.cfg", "crafting.cfg", "story.cfg", "traits.cfg", "rivals.cfg",
	"trials.cfg", "travel.cfg", "landmarks.cfg", "classes.cfg", "pet.cfg"]

var characters := {}	# id -> {id, name, skin, race, class, created, last}
var current := ""		# the character being played ("" = none picked yet)


func _ready():
	DirAccess.make_dir_recursive_absolute(DIR)
	var cfg = ConfigFile.new()
	if cfg.load(ACCOUNT_PATH) == OK:
		characters = cfg.get_value("account", "characters", {})
	_move_old_save()
	_hook.call_deferred()


func path(file: String) -> String:
	if current == "":
		return "user://" + file
	return "%s/%s/%s" % [DIR, current, file]


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("account", "characters", characters)
	if cfg.save(ACCOUNT_PATH) != OK:
		ErrorLog.fail("Account: couldn't save " + ACCOUNT_PATH)


## Newest played first.
func list() -> Array:
	var out = characters.values()
	out.sort_custom(func(a, b): return str(a.get("last", "")) > str(b.get("last", "")))
	return out


func create(char_name: String, skin: String, race: String, class_id: String) -> String:
	var id = "c%d%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
	if DirAccess.make_dir_recursive_absolute("%s/%s" % [DIR, id]) != OK:
		ErrorLog.fail("Account: couldn't make a folder for the new character " + id)
	char_name = char_name.strip_edges().substr(0, 24)
	if char_name == "":
		char_name = Story._default_name()
	characters[id] = {"id": id, "name": char_name, "skin": skin, "race": race, "class": class_id,
		"created": Time.get_date_string_from_system(), "last": Time.get_datetime_string_from_system()}
	_save()
	return id


## Play this character: its world, race and class, and all its saved things.
func select(id: String):
	if not characters.has(id):
		ErrorLog.fail("Account: no character with id " + id)
		return
	var c = characters[id]
	current = id
	c.last = Time.get_datetime_string_from_system()
	_save()
	SkinManager.set_skin(c.skin)
	SkinManager.set_race(c.race)
	if SkinManager.current_race != c.race:
		ErrorLog.fail("Account: %s's race '%s' isn't in the %s world any more" % [c.name, c.race, c.skin])
	GameState.player_class = Classes.normalize(c["class"])
	for system in [GameState, Crafting, Story, Traits, Rivals, Trials, Travel, Landmarks, Classes, Helpers]:
		system.load_character()
	if Story.player_name != c.name:	# a new character: its name goes in its own story
		Story.player_name = c.name
		Story._save()
	print("Playing %s (%s %s, %s)" % [c.name, c.race, c["class"], c.skin])


func remove(id: String):
	if not characters.has(id):
		return
	var folder = "%s/%s" % [DIR, id]
	var d = DirAccess.open(folder)
	if d:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(folder)
	characters.erase(id)
	if current == id:
		current = ""
	_save()


# ---------------- Save point: where each character was ----------------

var _place_t := 0.0

func _hook():
	Zones.entered.connect(func(_z): remember_place())


func _process(delta):
	_place_t += delta
	if _place_t > 15.0:
		_place_t = 0.0
		remember_place()


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		remember_place()


## Regular zones only (not a Trial Ground or a cavern: you come back to the zone outside).
func remember_place():
	if current == "" or not characters.has(current) or Zones.player == null or not is_instance_valid(Zones.player):
		return
	var path_now = Zones.local_path()
	if not path_now in GameState.ZONE_ORDER:
		return
	var p = Zones.player.global_position
	characters[current]["place"] = {"scene": path_now, "x": p.x, "y": p.y, "z": p.z}
	_save()


## Where this character should start: its save point, if that zone is still open to it.
func start_scene() -> String:
	var pl = characters.get(current, {}).get("place", {})
	var scene = str(pl.get("scene", "res://Home.tscn"))
	if scene == "" or not pl.has("x") or not ResourceLoader.exists(scene) or not GameState.is_unlocked(scene):
		return "res://Home.tscn"
	GameState.pending_spawn = Vector3(float(pl.get("x")), float(pl.get("y")) + 0.5, float(pl.get("z")))
	return scene


## For the start screen: "Gold 120 · Day 4 · Zone 3 open".
func summary(c: Dictionary) -> String:
	var folder = "%s/%s/" % [DIR, c.id]
	var gold = 0
	var zones = 1
	var cfg = ConfigFile.new()
	if cfg.load(folder + "progress.cfg") == OK:
		gold = int(cfg.get_value("gold", "banked", 0)) + int(cfg.get_value("gold", "carried", 0))
		zones = max(1, cfg.get_value("progress", "unlocked_zones", []).size() - 1)
	var day = 1
	var st = ConfigFile.new()
	if st.load(folder + "story.cfg") == OK:
		var first = str(st.get_value("story", "first_date", ""))
		if first != "":
			day = 1 + int((Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system()) - Time.get_unix_time_from_datetime_string(first)) / 86400)
	return "Gold %d  ·  Day %d  ·  %d zone%s open" % [gold, day, zones, "" if zones == 1 else "s"]


## Before characters existed there was one save in user://. Make it the first character.
func _move_old_save():
	if not characters.is_empty():
		return
	var found = PER_CHARACTER.filter(func(f): return FileAccess.file_exists("user://" + f))
	if not found.has("progress.cfg") and not found.has("crafting.cfg"):
		return
	var st = ConfigFile.new()
	var old_name = ""
	if st.load("user://story.cfg") == OK:
		old_name = st.get_value("story", "name", "")
	var set = ConfigFile.new()
	var skin = "default"
	var race = ""
	if set.load("user://settings.cfg") == OK:
		skin = set.get_value("skin", "id", "default")
		race = set.get_value("skin", "race", "")
	var id = create(old_name if old_name != "" else "Wanderer", skin, race, "dps")
	for f in found:
		var err = DirAccess.rename_absolute("user://" + f, "%s/%s/%s" % [DIR, id, f])
		if err != OK:
			ErrorLog.fail("Account: couldn't move your old save %s into the first character (error %d)" % [f, err])
	print("Account: your old save is now the character ", characters[id].name)
