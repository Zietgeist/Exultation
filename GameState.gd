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


func _process(delta: float) -> void:
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

var unlocked_zones = ["res://Home.tscn", "res://Zone1.tscn"]


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		unlocked_zones = cfg.get_value("progress", "unlocked_zones", unlocked_zones)


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


func unlock(scene_path: String):
	if is_unlocked(scene_path):
		return
	unlocked_zones.append(scene_path)
	var cfg = ConfigFile.new()
	cfg.set_value("progress", "unlocked_zones", unlocked_zones)
	cfg.save(PROGRESS_PATH)
	print("UNLOCKED: ", ZONE_NAMES.get(scene_path, scene_path))
	zone_unlocked.emit(scene_path)


# Test key: F10 unlocks the next zone (only in debug builds)
func _unhandled_input(event):
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		for z in ZONE_ORDER:
			if not is_unlocked(z):
				unlock(z)
				return
