extends Node

var player_class = 0

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

const ZONE_ORDER = ["res://Zone1.tscn", "res://Zone2.tscn", "res://Zone3.tscn", "res://Zone4.tscn"]
const ZONE_NAMES = {
	"res://Home.tscn": "Home",
	"res://Zone1.tscn": "Zone 1",
	"res://Zone2.tscn": "Zone 2",
	"res://Zone3.tscn": "Zone 3",
	"res://Zone4.tscn": "Zone 4",
}
const BOSSES_TO_UNLOCK = 2
const PROGRESS_PATH = "user://progress.cfg"

# Zone size and obstacle density
const BASE_ZONE_AREA = 6000.0	# Zone 1 floor: 60 x 100
const OBSTACLE_DENSITY = 0.7	# Zone 1 has 70% of the original obstacle count
var _obstacle_floor = null
var _obstacle_mult = 1.0


## How big the current zone is compared to Zone 1 (Zone 1 = 1.0)
func zone_area_scale() -> float:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node == null:
		ErrorLog.fail("zone_area_scale: no map floor found (floor must be in group map_floor)")
		return 1.0
	var half = floor_node.get_half_size()
	return (half.x * 2.0) * (half.y * 2.0) / BASE_ZONE_AREA


## How many obstacles to make, compared to the original counts.
## Zone 1: exactly 70%. Other zones: same density for their size, +/- 20% random.
func obstacle_multiplier() -> float:
	var floor_node = get_tree().get_first_node_in_group("map_floor")
	if floor_node != null and floor_node == _obstacle_floor:
		return _obstacle_mult	# same zone visit: obstacles and terrain share one roll
	_obstacle_floor = floor_node
	_obstacle_mult = OBSTACLE_DENSITY * zone_area_scale()
	if floor_node == null or floor_node.get_script().resource_path != "res://zone1floor.gd":
		_obstacle_mult *= randf_range(0.8, 1.2)
	return _obstacle_mult

var unlocked_zones = ["res://Home.tscn", "res://Zone1.tscn"]


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		unlocked_zones = cfg.get_value("progress", "unlocked_zones", unlocked_zones)
		gold_carried = cfg.get_value("gold", "carried", 0)
		gold_banked = cfg.get_value("gold", "banked", 0)
	bag_full.connect(_on_bag_full)


func save_progress():
	var cfg = ConfigFile.new()
	cfg.set_value("progress", "unlocked_zones", unlocked_zones)
	cfg.set_value("gold", "carried", gold_carried)
	cfg.set_value("gold", "banked", gold_banked)
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
func on_boss_killed(bosses_killed_here: int):
	if bosses_killed_here < BOSSES_TO_UNLOCK:
		return
	var here = get_tree().current_scene.scene_file_path
	var i = ZONE_ORDER.find(here)
	if i == -1 or i + 1 >= ZONE_ORDER.size():
		return
	unlock(ZONE_ORDER[i + 1])


func reset_zone_progress():
	unlocked_zones = ["res://Home.tscn", "res://Zone1.tscn"]
	save_progress()
	print("Zone progress reset: only Home and Zone 1 are open.")
	zone_unlocked.emit("")	# doors refresh their color and label


func unlock(scene_path: String):
	if is_unlocked(scene_path):
		return
	unlocked_zones.append(scene_path)
	save_progress()
	print("UNLOCKED: ", ZONE_NAMES.get(scene_path, scene_path))
	zone_unlocked.emit(scene_path)


# Test keys (only in debug builds):
#   F10         = unlock the next zone
#   Shift + F10 = lock everything again (back to a fresh start)
func _unhandled_input(event):
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		if event.shift_pressed:
			reset_zone_progress()
			return
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
	_gold_budget = min(_gold_budget + delta * GOLD_CAPACITY / (_bag_minutes * 60.0), MAX_GOLD_BUDGET)


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
	if get_tree().get_first_node_in_group("home_portal") != null:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
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
		return_scene = get_tree().current_scene.scene_file_path
		return_position = player.global_position
	get_tree().current_scene.add_child(portal)

const HOME_ARRIVAL = Vector3(0, 1, 8)	# next to the Deposit Shrine
