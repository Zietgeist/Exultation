extends Node
## Autoload "Rivals": the small enemy that kills you doesn't forget it.
##
##   - If a TRASH enemy kills you, it grows into a named Rival boss right there: "Grask the Goblin,
##     who slew you". Its health and hits are set from YOUR stats, and it copies a version of
##     your best-ranked skill (enrage / mend / slam / harden / lunge).
##   - It stays in that zone. Each time you come back, it's there (rebuilt from your current stats).
##   - If it kills you again, it grows stronger and its title changes ("who slew you twice").
##   - Beat it: that's a Chronicle entry, a trophy, gear that "remembers" it, and a pull toward
##     Steadfast. Leave its zone while it lives: a pull toward Swift.
##   - Trial Grounds follow the same rules. A rival born in a Trial Ground waits in your next
##     Trial Ground of that ability.
##
## Rivals are personal: they're saved on the PC of the player they killed.
## Online: the host runs them (see Net: rival_born / spawn_rival / rival_avenged).

signal avenged(data)	# you (or your party) beat one of your rivals
signal skipped(data)	# you left a zone while your rival there still lives
signal born(data)

var SAVE_PATH: String:	# this character's save (Account)
	get:
		return Account.path("rivals.cfg")
const POWER_FOR = {	# your skill's effect -> the rival's version of it
	"damage_boost": "enrage", "whirlwind": "enrage",
	"heal_self": "mend", "mending": "mend", "drain_aura": "mend",
	"blast": "slam", "root_field": "slam", "thorns_aura": "slam", "totem": "slam",
	"shield": "harden", "dash": "lunge",
}
const POWER_WORDS = {"enrage": "flies into a rage", "mend": "mends its wounds", "slam": "slams the ground",
	"harden": "hardens its hide", "lunge": "lunges at you"}
const START = ["Gr", "Sk", "Vor", "Mal", "Th", "Kr", "Zh", "Bel", "Dr", "Mor", "Ux", "Fen", "Rot", "Sn"]
const MID = ["a", "o", "u", "e", "i", "aa", "ou"]
const END = ["sk", "g", "th", "x", "rn", "z", "ll", "k", "mble", "sh", "d"]

var rivals := {}		# id -> {id, name, kind, place, kills, power, born, owner}
var trophies := []		# names of rivals you've beaten (shown in the Chronicle)
var _visit_skips := {}	# rival ids already counted as "skipped" this visit


func _ready():
	load_character()
	Zones.entered.connect(_on_entered)


func load_character():
	rivals = {}
	trophies = []
	_visit_skips = {}
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		rivals = cfg.get_value("rivals", "rivals", {})
		trophies = cfg.get_value("rivals", "trophies", [])


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("rivals", "rivals", rivals)
	cfg.set_value("rivals", "trophies", trophies)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Rivals: couldn't save " + SAVE_PATH)


# ---------------- Where a rival lives ----------------

## Zones: their scene path. Trial Grounds: "arena:<ability>" (the next Trial Ground of that ability).
func place_of(z) -> String:
	if z == null:
		return ""
	if z.path == Trials.ARENA:
		return "arena:" + str(z.info.get("ability", ""))
	if z.path == "res://Cavern.tscn":
		return "cavern:%s|%s" % [z.info.get("parent", ""), z.info.get("id", "")]
	return z.path


func full_name(r: Dictionary) -> String:
	var title = "who slew you"
	if r.kills == 2:
		title += " twice"
	elif r.kills > 2:
		title += " %d times" % r.kills
	return "%s the %s, %s" % [r.name, SkinManager.name_of(r.kind + "_one"), title]


func _make_name() -> String:
	return START.pick_random() + MID.pick_random() + END.pick_random()


## The rival's version of your best-ranked skill.
func _pick_power() -> String:
	var p = Zones.player
	var best = "enrage"
	var best_rank = -1
	if p == null:
		return best
	for key in ["E", "Q", "F"]:
		var s = Classes.skill(p.player_class, key)
		var r = Classes.rank(p.player_class, key)
		if s.has("effect") and POWER_FOR.has(s.effect) and r > best_rank:
			best = POWER_FOR[s.effect]
			best_rank = r
	return best


## Health and hit size, from YOUR current stats (so it's always a fair fight for you right now).
func stats_for(r: Dictionary) -> Dictionary:
	var p = Zones.player
	var my_hp = p.MAX_HEALTH if p else 100.0
	var my_hit = p.st_damage if p else 100.0
	var grow = 1.0 + 0.35 * (r.kills - 1)
	return {
		hp = max(my_hit * 22.0, my_hp * 6.0) * grow,	# about 20+ of your hits
		dmg = my_hp * 0.07 * (1.0 + 0.15 * (r.kills - 1)),	# about 14 of its hits to take you down
		label = full_name(r), power = r.power, id = r.id, owner = r.owner,
	}


# ---------------- Born, grown, beaten ----------------

## The local player just died. killer = the enemy that landed the last hit (may be a mirror online).
func on_player_killed(killer):
	if killer == null or not is_instance_valid(killer) or not "tier" in killer:
		return
	var z = Zones.zone_of(killer)
	if z == null:
		return
	if not killer.rival.is_empty():	# it beat me again
		var r = rivals.get(killer.rival.id)
		if r == null:	# someone else's rival
			return
		r.kills += 1
		_save()
		var s = stats_for(r)
		Story.add("%s beat you again. It grows stronger." % full_name(r))
		GameState.notify("%s grows stronger!" % r.name)
		_apply(killer, s)
		return
	if killer.tier != 0:	# only the small ones grudge
		return
	var r = {id = "%d%d" % [Time.get_unix_time_from_system(), randi() % 100000], name = _make_name(),
		kind = killer.TIER_IDS[killer.tier], place = place_of(z), kills = 1, power = _pick_power(),
		born = Time.get_date_string_from_system(), owner = Net.my_id()}
	rivals[r.id] = r
	_save()
	GameState.notify("The %s that felled you grows into a Rival: %s!" % [SkinManager.name_of(r.kind + "_one"), r.name])
	Story.add("A %s struck you down in %s... and grew into %s." % [SkinManager.name_of(r.kind + "_one"), z.zone_name if z.zone_name != "" else "the wilds", full_name(r)])
	born.emit(r)
	_apply(killer, stats_for(r))


## Turn an enemy into the rival (host), or ask the host to.
func _apply(e, s: Dictionary):
	if e.mirror:
		Net.rival_born(e.net_id, s)
	else:
		e.become_rival(s)


## Host: a rival died. Tell its owner.
func rival_died(e):
	var owner = int(e.rival.get("owner", 1))
	if owner == Net.my_id():
		avenge(e.rival.id)
	else:
		Net.rival_avenged(owner, e.rival.id)


## One of MY rivals fell (I may not have landed the blow; the party counts).
func avenge(id: String):
	var r = rivals.get(id)
	if r == null:
		return
	rivals.erase(id)
	trophies.append(full_name(r))
	_save()
	Story.on_rival_beaten()
	Story.add("Avenged! %s has fallen." % full_name(r))
	GameState.notify("Rival defeated: %s!" % r.name)
	avenged.emit(r)


# ---------------- Coming back to a rival's zone ----------------

func _on_entered(z):
	_visit_skips.clear()
	_spawn_mine_in.call_deferred(z)


## Rivals of mine that live here come back (from my current stats), away from the entrance.
func _spawn_mine_in(z):
	if z == null or not is_instance_valid(z) or Zones.player == null:
		return
	var place = place_of(z)
	var nest = ""	# caverns: sometimes your rivals from the zone above are hiding down here
	if z.path == "res://Cavern.tscn" and randf() < 0.35:
		nest = str(z.info.get("parent", ""))
		if rivals.values().any(func(r): return r.place == nest):
			GameState.notify("A Rival nest! Your rivals from above are hiding down here.")
	for r in rivals.values():
		if r.place != place and (nest == "" or r.place != nest):
			continue
		var s = stats_for(r)
		var spot = _far_spot(z)
		if Net.is_client():
			Net.spawn_rival(s, spot)
		else:
			spawn_rival(z, s, spot)


## Host (or solo): put a rival into zone z, unless it's already there.
func spawn_rival(z, s: Dictionary, spot: Vector3):
	for e in Zones.all(z.root, "enemy"):
		if not e.rival.is_empty() and e.rival.id == s.id:
			return
	var e = load("res://enemy.tscn").instantiate()
	z.root.add_child(e)
	e.global_position = spot
	e.setup(1.0, 3)
	e.become_rival(s)
	if z.root.has_method("adopt_enemy"):	# Trial Ground: it has to fall before the ground is clear
		z.root.adopt_enemy(e)


func _far_spot(z) -> Vector3:
	if z.root.has_method("rival_spot"):
		return z.root.rival_spot()
	var me = Zones.player.global_position
	var sp = Zones.first(z.root, "zone_spawner")
	var spot = Vector3(randf_range(-14, 14), 1.2, randf_range(-16, 0))	# Trial Ground
	if sp:
		spot = sp._random_spot(me, 25.0)
		spot = sp.clamp_to_map(spot)
		spot.y = 1.2
	var terrain = Zones.first(z.root, "zone_terrain")
	if terrain and terrain.is_water(spot):
		spot = terrain.nearest_land(spot)
	return spot


## Called before you leave a zone (Net.go): your rival here still lives = you skipped it.
func leaving(z):
	if z == null:
		return
	var place = place_of(z)
	for r in rivals.values():
		if r.place == place and not _visit_skips.has(r.id):
			_visit_skips[r.id] = true
			skipped.emit(r)


func mine_here() -> Array:
	var place = place_of(Zones.local_zone())
	return rivals.values().filter(func(r): return r.place == place)
