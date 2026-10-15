extends Node

var player_class = "dps"	# a class id from classes/*.json

# Orb Container
var orb_container: int = 0
var orb_capacity: int = 20
var orb_overfill_timer: float = 0.0
var is_overfilled: bool = false
var orbs_collected = 0
var orb_slots = 10
var current_zone = "Home"
var previous_scene = ""	# the zone we just came from (used to place the player at the right door)
var deaths = 0
var input_locked = false	# a trial is open: your character stands still (typing won't walk you around)
var ui_open = false	# a shop window is open (the player ignores attack/ability input)


## True while you're typing in a text box (a note, a name): WASD types letters instead of walking.
func typing() -> bool:
	var f = get_tree().root.gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _process(delta: float) -> void:
	_tick_gold(delta)
	if is_overfilled:
		orb_overfill_timer -= delta
		if orb_overfill_timer <= 0.0:
			orb_container = orb_capacity
			is_overfilled = false
			orb_overfill_timer = 0.0
			
func collect_orb(cost: int) -> void:
	if orbs_collected + cost <= orb_slots:
		orbs_collected += cost
		print("Orbs collected: ", orbs_collected, "/", orb_slots)


# ---------------- Zone progress ----------------
# Zones in spiral order. Killing BOSSES_TO_UNLOCK bosses in a zone unlocks the next one.
signal zone_unlocked(scene_path)

const ZONE_ORDER = ["res://Zone1.tscn", "res://Zone2.tscn", "res://Zone3.tscn", "res://Zone4.tscn", "res://Zone5.tscn", "res://Zone6.tscn", "res://Zone7.tscn", "res://Zone8.tscn", "res://Zone9.tscn", "res://Zone10.tscn"]
const ZONE_NAMES = {
	"res://Home.tscn": "Home",
	"res://Zone1.tscn": "Zone 1",
	"res://Zone2.tscn": "Zone 2",
	"res://Zone3.tscn": "Zone 3",
	"res://Zone4.tscn": "Zone 4",
	"res://Zone5.tscn": "Zone 5",
	"res://Zone6.tscn": "Zone 6",
	"res://Zone7.tscn": "Zone 7",
	"res://Zone8.tscn": "Zone 8",
	"res://Zone9.tscn": "Zone 9",
	"res://Zone10.tscn": "Zone 10",
}
const BOSSES_TO_UNLOCK = 2
var PROGRESS_PATH: String:	# this character's save (Account)
	get:
		return Account.path("progress.cfg")

# Zone size and obstacle density
const BASE_ZONE_AREA = 6000.0	# Zone 1 floor: 60 x 100
const OBSTACLE_DENSITY = 0.7	# Zone 1 has 70% of the original obstacle count
const MAX_OBSTACLE_MULT = 16.0	# about twice Zone 3's terrain, however big the zone
var _obstacle_mults = {}	# floor node -> this visit's obstacle roll


## How big the current zone is compared to Zone 1 (Zone 1 = 1.0)
func zone_area_scale(node = null) -> float:
	var floor_node = Zones.first(node, "map_floor") if node else Zones.local_first("map_floor")
	if floor_node == null:
		ErrorLog.fail("zone_area_scale: no map floor found (floor must be in group map_floor)")
		return 1.0
	var half = floor_node.get_half_size()
	return content_scale((half.x * 2.0) * (half.y * 2.0) / BASE_ZONE_AREA)


## Up to Zone 3's size (about 12x Zone 1), enemies and terrain grow with the floor area.
## Past that they grow more slowly (area ^ 0.6), so huge zones are roomier, not endless.
## With BIG_ZONE_DENSITY: Zone 4 ~15x Zone 1, Zone 6 ~49x, Zone 10 ~490x (capped by the spawner).
const CONTENT_KNEE = 12.0
func content_scale(area_scale: float) -> float:
	if area_scale <= CONTENT_KNEE:
		return area_scale
	return CONTENT_KNEE * pow(area_scale / CONTENT_KNEE, 0.6) * BIG_ZONE_DENSITY


const BIG_ZONE_DENSITY = 0.75	# Zone 4 and up: 25% less crowded


## How many obstacles to make, compared to the original counts.
## Zone 1: exactly 70%. Other zones: same density for their size, +/- 20% random.
func obstacle_multiplier(node = null) -> float:
	var floor_node = Zones.first(node, "map_floor") if node else Zones.local_first("map_floor")
	if floor_node != null and _obstacle_mults.has(floor_node):
		return _obstacle_mults[floor_node]	# same zone visit: obstacles and terrain share one roll
	var mult = min(OBSTACLE_DENSITY * zone_area_scale(node), MAX_OBSTACLE_MULT)	# huge zones: more open ground (keeps them fast)
	if floor_node == null or floor_node.get_script().resource_path != "res://zone1floor.gd":
		mult *= randf_range(0.8, 1.2)
	if floor_node:
		_obstacle_mults[floor_node] = mult
	return mult

var personal_unlocked = ["res://Home.tscn", "res://Zone1.tscn"]	# your own (solo) progress
var unlocked_zones = personal_unlocked	# what's open in THIS game: yours, or your party's (party.gd)


func _ready():
	load_character()
	bag_full.connect(_on_bag_full)


## Fresh start for a character, then whatever it has saved (Account.select calls this too).
func load_character():
	personal_unlocked = ["res://Home.tscn", "res://Zone1.tscn"]
	unlocked_zones = personal_unlocked
	gold_carried = 0
	gold_banked = 0
	satchel = {}
	storehouse = {}
	satchel_upgrades = 0
	buffs = {}
	deaths = 0
	zone_memory = {}
	zone_marks = {}
	zone_templates = {}
	return_scene = ""
	return_position = null
	pending_spawn = null
	var cfg = ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		# Each character keeps its unlocked zones (to test from scratch, make a new character).
		personal_unlocked = cfg.get_value("progress", "unlocked_zones", personal_unlocked)
		unlocked_zones = personal_unlocked
		gold_carried = cfg.get_value("gold", "carried", 0)
		gold_banked = cfg.get_value("gold", "banked", 0)
		satchel = cfg.get_value("resources", "satchel", {})
		storehouse = cfg.get_value("resources", "storehouse", {})
		satchel_upgrades = cfg.get_value("resources", "satchel_upgrades", 0)
		buffs = cfg.get_value("inn", "buffs", {})


func save_progress():
	var cfg = ConfigFile.new()
	cfg.set_value("progress", "unlocked_zones", personal_unlocked)
	cfg.set_value("gold", "carried", gold_carried)
	cfg.set_value("gold", "banked", gold_banked)
	cfg.set_value("resources", "satchel", satchel)
	cfg.set_value("resources", "storehouse", storehouse)
	cfg.set_value("resources", "satchel_upgrades", satchel_upgrades)
	cfg.set_value("inn", "buffs", buffs)
	if cfg.save(PROGRESS_PATH) != OK:
		ErrorLog.fail("Could not save progress to " + PROGRESS_PATH)


func is_unlocked(scene_path: String) -> bool:
	return scene_path in unlocked_zones


## What the player must do to open this zone, e.g. "Defeat 2 bosses in Zone 1"
func unlock_hint(scene_path: String) -> String:
	var i = ZONE_ORDER.find(scene_path)
	if i <= 0:
		return "Locked"
	return "Defeat %d bosses in %s" % [BOSSES_TO_UNLOCK, ZONE_NAMES.get(ZONE_ORDER[i - 1], "the previous zone")]


## Called by the spawner each time a boss dies in the current zone.
func on_boss_killed(bosses_killed_here: int, here := ""):
	if bosses_killed_here < BOSSES_TO_UNLOCK:
		return
	if here == "":
		here = Zones.local_path()
	var i = ZONE_ORDER.find(here)
	if i == -1:
		return
	Party.zone_cleared(here)
	if i + 1 >= ZONE_ORDER.size():	# the last zone: the journey's end
		if not Party.active():
			notify("You have cleared %s. You are a Legend of the Spiral!" % ZONE_NAMES.get(here, here))
			Story.once("legend_solo", "Cleared %s alone. A Legend of the Spiral." % ZONE_NAMES.get(here, here))
		return
	unlock(ZONE_ORDER[i + 1])


func reset_zone_progress():
	personal_unlocked = ["res://Home.tscn", "res://Zone1.tscn"]
	unlocked_zones = personal_unlocked
	save_progress()
	print("Zone progress reset: only Home and Zone 1 are open.")
	zone_unlocked.emit("")	# doors refresh their color and label


func unlock(scene_path: String):
	if is_unlocked(scene_path):
		return
	unlocked_zones.append(scene_path)	# (the party's list when playing as a party)
	unlock_personal(scene_path)
	save_progress()
	print("UNLOCKED: ", ZONE_NAMES.get(scene_path, scene_path))
	Party.zone_unlocked(scene_path)
	zone_unlocked.emit(scene_path)


## Zones opened with a party also open in your own progress.
func unlock_personal(scene_path: String):
	if not scene_path in personal_unlocked:
		personal_unlocked.append(scene_path)
		save_progress()


## Play with a party's open zones (list), or your own again (null).
func use_party(list):
	unlocked_zones = list if list != null else personal_unlocked
	zone_unlocked.emit("")	# doors refresh


# Test key (only in debug builds): Shift + F10 = unlock the next zone
func _unhandled_input(event):
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 and event.shift_pressed:
		for z in ZONE_ORDER:
			if not is_unlocked(z):
				unlock(z)
				return


# ---------------- Gold: the Pomodoro bag ----------------
# Gold drops from kills, paced by TIME so the bag fills in about 20-25 minutes of play.
# A full bag opens a portal home. Depositing at the Home shrine starts the 5-minute rest.
signal gold_changed
signal bag_full

const GOLD_CAPACITY = 100
const BAG_MINUTES_MIN = 20.0
const BAG_MINUTES_MAX = 25.0
const MAX_GOLD_PER_ORB = 4
const MAX_GOLD_BUDGET = 8.0	# don't let gold pile up while standing around
const GOLD_TEST_SPEED = 2.0	# TESTING: gold comes 2x faster (bag fills in ~10-12 min). Set back to 1.0 for real play.

var gold_carried = 0
var gold_banked = 0
var _gold_budget = 0.0
var _bag_minutes = randf_range(BAG_MINUTES_MIN, BAG_MINUTES_MAX)

# Fast travel
var return_scene = ""		# zone to go back to after resting
var return_position = null	# exact spot we left from
var pending_spawn = null	# where the player should appear in the next scene


func is_bag_full() -> bool:
	return gold_carried >= GOLD_CAPACITY


func _tick_gold(delta):
	if current_zone == "Home" or is_bag_full():
		return
	_gold_budget = min(_gold_budget + delta * GOLD_TEST_SPEED * GOLD_CAPACITY / (_bag_minutes * 60.0), MAX_GOLD_BUDGET)


## Called when an enemy dies. Returns how much gold its orb holds (0 = no gold orb).
func take_gold_drop() -> int:
	if is_bag_full():
		return 0
	var amount = mini(floori(_gold_budget), MAX_GOLD_PER_ORB)
	if amount <= 0:
		return 0
	_gold_budget -= amount
	return amount


func add_gold(amount: int):
	if is_bag_full():
		return
	gold_carried = mini(gold_carried + amount, GOLD_CAPACITY)
	gold_changed.emit()
	if is_bag_full():
		print("Gold bag full! A portal home has opened.")
		save_progress()
		bag_full.emit()


## Bank everything you're carrying. Returns how much was deposited.
func deposit_gold() -> int:
	var amount = gold_carried
	if amount <= 0:
		return 0
	if not buffs.is_empty():	# Inn treats last one flow session
		buffs.clear()
		buffs_changed.emit()
	gold_banked += amount
	gold_carried = 0
	_gold_budget = 0.0
	_bag_minutes = randf_range(BAG_MINUTES_MIN, BAG_MINUTES_MAX)
	save_progress()
	gold_changed.emit()
	return amount


func _on_bag_full():
	spawn_home_portal.call_deferred()


## Put a gold portal home next to the player (only out in a zone, only one at a time).
func spawn_home_portal():
	if current_zone == "Home" or not is_bag_full():
		return
	if Zones.local_first("home_portal") != null:
		return
	var player = Zones.player
	if player == null or Zones.local_root() == null:
		return
	var portal = load("res://portal.gd").new()
	portal.add_to_group("home_portal")
	portal.target_scene = "res://Home.tscn"
	portal.target_position = HOME_ARRIVAL
	portal.label_text = "Bag full!\nPortal Home"
	var toward_center = -player.global_position
	toward_center.y = 0
	portal.position = player.global_position + toward_center.normalized() * 4.0
	portal.position.y = 0
	portal.before_travel = func():
		return_scene = Zones.path_of(player)
		return_position = player.global_position
	Zones.local_root().add_child(portal)

const HOME_ARRIVAL = Vector3(0, 1, 8)	# next to the Deposit Shrine


# ---------------- Zone memory (this play session only) ----------------
# Leaving a zone and coming back keeps its kill counts and its map layout.
# Quitting the game starts fresh.
var zone_memory = {}	# scene path -> {spawner = {...}, obstacles = [...], terrain = [...]}


## Save a loaded zone's state (Zones calls this when a zone is unloaded).
func remember_zone(z):
	if z == null or z.path == "res://Home.tscn" or z.root == null:
		return
	var memory = {}
	var parts = {"spawner": "zone_spawner", "obstacles": "zone_obstacles", "terrain": "zone_terrain", "fog": "zone_fog"}
	for part in parts:
		var node = Zones.first(z.root, parts[part])
		if node:
			memory[part] = node.save_state()
	zone_memory[z.path] = memory


## Old name: save the local player's zone.
func remember_current_zone():
	remember_zone(Zones.local_zone())


## What a zone part saved last time (or null if this is the first visit this session).
func saved_zone_part(node: Node, part: String):
	if node.owner == null:
		ErrorLog.fail("saved_zone_part: %s has no owner scene, can't look up its memory" % node.name)
		return null
	var memory = zone_memory.get(node.owner.scene_file_path, {})
	return memory.get(part, null)


## Speed multiplier at a spot: 1.0 normally, lower inside a slow patch (ditch).
const HILL_SPEED = 0.25	# climbing over a hill / rubble pile: a quarter speed (player and enemies)


## Is this body standing on (or climbing) a hill? Call after its move_and_slide().
func on_hill(body: CharacterBody3D) -> bool:
	for i in range(body.get_slide_collision_count()):
		var c = body.get_slide_collision(i).get_collider()
		if c and c.is_in_group("hill"):
			return true
	return false


func slow_factor_at(world_pos: Vector3, node = null) -> float:
	var d = ditch_at(world_pos, node)
	return d.get_slow_factor() if d else 1.0


## The slow patch at a spot, or null.
func ditch_at(world_pos: Vector3, node = null):
	for d in (Zones.all(node, "ditch") if node else Zones.local_all("ditch")):
		if d.contains(world_pos):
			return d
	return null


# ---------------- Notices (big gold message on screen) ----------------
signal notice(text)

# ---------------- Map templates ----------------
var zone_templates = {}	# scene path -> template id, picked once per play session

func zone_template(scene_path: String) -> String:
	if not zone_templates.has(scene_path):
		zone_templates[scene_path] = preload("res://map_templates.gd").pick(scene_path)
	return zone_templates[scene_path]


## Everyone in the party (just you for now; other players join this group in multiplayer).
func party(node = null) -> Array:
	return Zones.all(node, "party") if node else get_tree().get_nodes_in_group("party")


## Feedback: the Send feedback buttons open this Discord invite (to the play-test feedback channel).
## Players @mention the bot there. While it is "", the buttons say "not set up yet".
const FEEDBACK_URL = "https://discord.gg/t7upqEdbx"

func open_feedback():
	if FEEDBACK_URL == "":
		ErrorLog.warn("Feedback link isn't set: put the Discord invite in GameState.FEEDBACK_URL")
		notify("The feedback link isn't set up yet.")
		return
	var err = OS.shell_open(FEEDBACK_URL)
	if err != OK:
		ErrorLog.fail("Couldn't open the feedback link (error %d): %s" % [err, FEEDBACK_URL])


func notify(text: String):
	print(text)
	notice.emit(text)


# ---------------- Map data ----------------
# Where each zone sits in the Golden Ratio spiral (x, z, width, depth in world units; Home is 0,0 to 100,100).
## Where each zone sits on the world map (x, z, width, depth): see world_layout.gd.
const ZONE_LAYOUT = preload("res://world_layout.gd").ZONES

var zone_marks = {}	# scene path -> [{kind = "death"/"boss", p = position, info = who}] (this play session)


## info: who killed you (death) or which boss fell (boss). Shown when you hover the mark on the map.
func add_mark(kind: String, pos: Vector3, node = null, info := ""):
	var path = Zones.path_of(node) if node else Zones.local_path()
	if path == "":
		return
	if not zone_marks.has(path):
		zone_marks[path] = []
	zone_marks[path].append({kind = kind, p = pos, info = info})


## A zone is cleared once both of its bosses are down (or the next zone was unlocked earlier).
func is_zone_cleared(path: String) -> bool:
	var i = ZONE_ORDER.find(path)
	if i != -1 and i + 1 < ZONE_ORDER.size() and is_unlocked(ZONE_ORDER[i + 1]):
		return true
	var z = Zones.get_zone(path)
	if z:
		var sp = Zones.first(z.root, "zone_spawner")
		return sp != null and sp.bosses_killed >= BOSSES_TO_UNLOCK
	var mem = zone_memory.get(path, {}).get("spawner", null)
	return mem != null and mem.bosses_killed >= BOSSES_TO_UNLOCK


# ---------------- Resources (gathered in the wild) ----------------
# Each resource is just a TYPE and a QUALITY number. Quality = zone number - 1
# (Zone 2 = 1, Zone 3 = 2, ... no upper limit). To add more qualities, add names below;
# anything past the list still works and shows as "<type> (Quality N)".
const RESOURCE_INFO = {
	"ore": {label = "Ore", color = Color(0.75, 0.5, 0.3), names = ["Copper ore", "Iron ore", "Silver ore", "Mithril ore", "Starmetal ore", "Adamant ore", "Orichalcum ore", "Sunsteel ore", "Voidsteel ore"]},
	"herb": {label = "Herb", color = Color(0.5, 0.85, 0.3), names = ["Sunleaf", "Moonleaf", "Dawnroot", "Duskbloom", "Starpetal", "Emberleaf", "Frostfern", "Ghostcap", "Worldroot"]},
	"treesilver": {label = "Treesilver", color = Color(0.82, 0.86, 0.92), names = ["Young Treesilver", "Elder Treesilver", "Ancient Treesilver", "Heartwood Treesilver", "World Treesilver", "Star Treesilver", "Dream Treesilver", "Crown Treesilver", "First Treesilver"]},
	"orchid": {label = "Cliff Orchid", color = Color(0.9, 0.45, 0.8), names = ["Pale Cliff Orchid", "Storm Cliff Orchid", "Ember Cliff Orchid", "Frost Cliff Orchid", "Void Cliff Orchid", "Sun Cliff Orchid", "Moon Cliff Orchid", "Star Cliff Orchid", "Dawn Cliff Orchid"]},
	"geode": {label = "Geode", color = Color(0.55, 0.85, 0.95), names = ["Dull geode", "Clouded geode", "Bright geode", "Starlit geode", "Deep geode", "Heart geode", "Abyssal geode", "Prism geode", "Void geode"]},  # caverns only
}

var satchel = {}	# "type:quality" -> count (saved between plays)
var storehouse = {}	# raw resources banked at Home (no limit): "type:quality" -> count


## The bank empties your satchel too: everything raw goes to the storehouse at Home.
## The Smith and Chemist refine straight from it. Returns how many were stored.
func store_satchel() -> int:
	var n = 0
	for k in satchel:
		if satchel[k] > 0:
			storehouse[k] = storehouse.get(k, 0) + satchel[k]
			n += satchel[k]
	satchel.clear()
	if n > 0:
		save_progress()
	return n


## Raw resources of one kind you can refine: satchel + storehouse.
func raw_count(key: String) -> int:
	return satchel.get(key, 0) + storehouse.get(key, 0)


## Use up raw resources: the satchel first (frees space), then the storehouse.
func take_raw(key: String, n: int) -> bool:
	if raw_count(key) < n:
		return false
	var from_satchel = mini(n, satchel.get(key, 0))
	if from_satchel > 0:
		satchel[key] -= from_satchel
		if satchel[key] <= 0:
			satchel.erase(key)
	var rest = n - from_satchel
	if rest > 0:
		storehouse[key] -= rest
		if storehouse[key] <= 0:
			storehouse.erase(key)
	save_progress()
	return true


## Resource quality for a zone: 0 means no resources there (Zone 1).
func zone_quality(scene_path: String) -> int:
	return max(0, ZONE_ORDER.find(scene_path))


func resource_name(type: String, quality: int) -> String:
	var skinned = SkinManager.list_name("resources", type, quality)
	if skinned != null:
		return skinned
	var names = RESOURCE_INFO[type].names
	if quality >= 1 and quality <= names.size():
		return names[quality - 1]
	return "%s (Quality %d)" % [RESOURCE_INFO[type].label, quality]


## Put gathered resources in the satchel. Returns false if it's full.
func add_resource(type: String, quality: int, amount := 1) -> bool:
	if satchel_count() + amount > satchel_capacity():
		return false
	var key = "%s:%d" % [type, quality]
	satchel[key] = satchel.get(key, 0) + amount
	save_progress()
	return true


# ---------------- Satchel size ----------------
const SATCHEL_BASE = 40
const SATCHEL_UPGRADE_SIZE = 20
const SATCHEL_UPGRADE_GOLD = 60
const SATCHEL_UPGRADES_MAX = 3
var satchel_upgrades = 0

func satchel_capacity() -> int:
	return SATCHEL_BASE + SATCHEL_UPGRADE_SIZE * satchel_upgrades

func satchel_count() -> int:
	var n = 0
	for k in satchel:
		n += satchel[k]
	return n

func buy_satchel_upgrade() -> bool:
	if satchel_upgrades >= SATCHEL_UPGRADES_MAX or not spend_gold(SATCHEL_UPGRADE_GOLD):
		return false
	satchel_upgrades += 1
	save_progress()
	return true


# ---------------- Spending banked gold ----------------
signal buffs_changed

## Inn treats: bought with banked gold, last until your next rest (the next time you bank gold).
const INN_OFFERS = {
	"meal": {name = "Hearty meal", gold = 6, about = "+15% damage"},				# was 25
	"sleep": {name = "A good night's sleep", gold = 10, about = "+50% energy regen"},	# was 40
	"tonic": {name = "Tamsin's tonic", gold = 8, about = "+20% max health"},			# was 30
}
var buffs = {}	# offer id -> true

func spend_gold(n: int) -> bool:
	if n <= 0:
		return true
	if gold_banked < n:
		return false
	gold_banked -= n
	save_progress()
	gold_changed.emit()
	return true

func has_buff(id: String) -> bool:
	return buffs.has(id)

func buy_buff(id: String) -> bool:
	if has_buff(id) or not spend_gold(INN_OFFERS[id].gold):
		return false
	buffs[id] = true
	save_progress()
	buffs_changed.emit()
	return true


## Short one-line summary for the HUD, e.g. "Copper ore 3 · Sunleaf 2"
func satchel_text() -> String:
	var parts = []
	var keys = satchel.keys()
	keys.sort()
	for key in keys:
		if satchel[key] <= 0:
			continue
		var bits = key.split(":")
		parts.append("%s %d" % [resource_name(bits[0], int(bits[1])), satchel[key]])
	return "Satchel %d/%d: " % [satchel_count(), satchel_capacity()] + (" · ".join(parts) if parts.size() > 0 else "empty")
