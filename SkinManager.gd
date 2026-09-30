extends Node
## Holds the current skin: colors and names for each game ID.
## Game code asks SkinManager instead of hard-coding looks.
## Built-in skins live in res://skins/. Players can add their own .json skins to user://skins/.
## Anything missing from a skin falls back to the Default skin.
## Press F9 in game to switch skins (test key).

signal skin_changed

const BUILTIN_DIR := "res://skins/"
const PLAYER_DIR := "user://skins/"
const SETTINGS_PATH := "user://settings.cfg"

var skins := {}	# skin id -> skin data (Dictionary)
var current_id := "default"


func _ready():
	DirAccess.make_dir_recursive_absolute(PLAYER_DIR)
	_load_folder(BUILTIN_DIR)
	_load_folder(PLAYER_DIR)
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		current_id = cfg.get_value("skin", "id", "default")
	if not skins.has(current_id):
		current_id = "default"
	print("Skin: ", skin_name(), "  (skins found: ", skins.keys(), ")")


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		next_skin()


## Color for a game ID, e.g. color("enemy_trash")
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
	current_id = id
	var cfg = ConfigFile.new()
	cfg.set_value("skin", "id", id)
	cfg.save(SETTINGS_PATH)
	print("Skin changed to: ", skin_name())
	skin_changed.emit()


func next_skin():
	var ids = skins.keys()
	ids.sort()
	var i = ids.find(current_id)
	set_skin(ids[(i + 1) % ids.size()])


func _lookup(section: String, id: String):
	var current = skins.get(current_id, {}).get(section, {})
	if current.has(id):
		return current[id]
	var fallback = skins.get("default", {}).get(section, {})
	return fallback.get(id, null)


func _load_folder(path: String):
	var dir = DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".json"):
			var text = FileAccess.get_file_as_string(path + file)
			var data = JSON.parse_string(text)
			if data is Dictionary:
				skins[file.get_basename()] = data
			else:
				print("Skin file has a mistake and was skipped: ", path + file)
