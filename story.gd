extends Node
## Autoload "Story": the game remembers what you did and shows it back to you.
##
##   - The Chronicle: a journal at Home that writes itself (J opens it), plus one line of your own
##     at each rest.
##   - Where recipes came from: earning a Sigil records the day, the zone, how many tries the trial
##     took and how close the Trial Ground came to killing you.
##   - Gear memory: each crafted item keeps who made it (and for whom), the recipe's story, and a
##     life record while it's worn (kills, bosses, rivals, times it saved you). Records earn titles.
##
## Store ids (enemy tiers, ability ids), not display names, so stories read right in any skin.

signal chronicle_changed

const SAVE_PATH = "user://story.cfg"
const MAX_ENTRIES = 400
const SAVED_BELOW = 0.10	# under 10% health and lived: the gear "saved you"

var player_name := ""
var first_date := ""			# "2026-10-07": Day 1
var chronicle := []				# [{day, date, text, own}]
var trial_tries := {}			# ability -> failed tries since its last level
var origins := {}				# advanced recipe id -> where it came from
var firsts := {}				# "first time" flags already written
var _losses := {}				# enemy tier -> date you last fell to one (for comebacks)


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		player_name = cfg.get_value("story", "name", "")
		first_date = cfg.get_value("story", "first_date", "")
		chronicle = cfg.get_value("story", "chronicle", [])
		trial_tries = cfg.get_value("story", "trial_tries", {})
		origins = cfg.get_value("story", "origins", {})
		firsts = cfg.get_value("story", "firsts", {})
		_losses = cfg.get_value("story", "losses", {})
	if first_date == "":
		first_date = Time.get_date_string_from_system()
		_save()
	if player_name == "":
		player_name = _default_name()
	Zones.entered.connect(_on_zone_entered)


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("story", "name", player_name)
	cfg.set_value("story", "first_date", first_date)
	cfg.set_value("story", "chronicle", chronicle)
	cfg.set_value("story", "trial_tries", trial_tries)
	cfg.set_value("story", "origins", origins)
	cfg.set_value("story", "firsts", firsts)
	cfg.set_value("story", "losses", _losses)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Story: couldn't save " + SAVE_PATH)


## Steam name if Steam is running, else the computer's user name.
func _default_name() -> String:
	if SteamLink.steam and SteamLink.ready_ok:
		return SteamLink.steam.getPersonaName()
	for v in ["USERNAME", "USER"]:
		var n = OS.get_environment(v)
		if n != "":
			return n.capitalize()
	return "Wanderer"


func set_player_name(n: String):
	n = n.strip_edges()
	if n == "":
		return
	player_name = n.substr(0, 24)
	_save()


## Day 1 is the day you first played.
func day() -> int:
	var a = Time.get_unix_time_from_datetime_string(first_date + "T00:00:00")
	var b = Time.get_unix_time_from_datetime_string(Time.get_date_string_from_system() + "T00:00:00")
	return int((b - a) / 86400) + 1


# ---------------- The Chronicle ----------------

func add(text: String, own := false):
	chronicle.append({day = day(), date = Time.get_date_string_from_system(), text = text, own = own})
	if chronicle.size() > MAX_ENTRIES:	# keep the newest, but never drop your own lines
		for i in chronicle.size():
			if not chronicle[i].own:
				chronicle.remove_at(i)
				break
	_save()
	chronicle_changed.emit()


## Write it only the first time (first boss, first step into a zone...).
func once(flag: String, text: String):
	if firsts.has(flag):
		return
	firsts[flag] = true
	add(text)


## The line you write at a rest.
func add_own_line(text: String):
	text = text.strip_edges()
	if text != "":
		add(text.substr(0, 140), true)


func _on_zone_entered(z):
	if z == null or z.path == "res://Home.tscn" or "#" in z.key:
		return
	once("zone:" + z.path, "First steps into %s." % z.zone_name if z.zone_name != "" else GameState.ZONE_NAMES.get(z.path, "a new land"))


# ---------------- Trials and recipes ----------------

## A trial ended (called by Trials.record).
func trial_result(ability: String, passed: bool):
	if not passed:
		trial_tries[ability] = trial_tries.get(ability, 0) + 1
		_save()


## You earned a level: remember how. extra = {zone, low} from the Trial Ground.
func sigil_earned(ability: String, level: int, extra: Dictionary):
	var tries = trial_tries.get(ability, 0) + 1
	trial_tries[ability] = 0
	var pet = Zones.player.pet if Zones.player else null
	var o = {
		ability = ability, level = level, day = day(), date = Time.get_date_string_from_system(),
		zone = extra.get("zone", ""), tries = tries, low = int(extra.get("low", 100)),
		pet = pet != null and is_instance_valid(pet) and pet.alive(),
		rival = extra.get("rival", ""),
	}
	origins[Crafting.advanced_id(ability, level)] = o
	var line = "Earned the Sigil of %s %s%s, %s." % [Trials.ability_name(ability), Trials.ROMAN[level],
		(" in " + o.zone) if o.zone != "" else "", _tries_text(tries)]
	if o.low <= 15:
		line += " The Trial Ground nearly won: %d%% health left." % o.low
	add(line)


func _tries_text(t: int) -> String:
	if t <= 1:
		return "passing the trial on the first try"
	return "passing the trial on the %s try" % _ordinal(t)


static func _ordinal(n: int) -> String:
	var s = "th"
	if n % 100 < 11 or n % 100 > 13:
		s = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, s]


# ---------------- Gear memory ----------------

## Crafting calls this on every new item.
func stamp_crafted(item: Dictionary, recipe_id: String):
	item.story = {maker = player_name, day = day(), date = Time.get_date_string_from_system()}
	if origins.has(recipe_id):
		item.story.origin = origins[recipe_id].duplicate()
	item.life = {kills = 0, bosses = 0, rivals = 0, saves = 0, first_worn = ""}


## An enemy died in my zone while I'm there: every piece I wear remembers it.
func on_kill(enemy):
	var boss = "tier" in enemy and enemy.tier == 3
	for it in Crafting.equipped_items():
		var life = _life(it)
		life.kills += 1
		if boss:
			life.bosses += 1
	if boss:
		once("boss", "Felled your first %s." % SkinManager.name_of("enemy_boss_one"))
		var lost = _losses.get(3, "")
		if lost != "" and lost != Time.get_date_string_from_system():
			_losses.erase(3)
			add("Dawn's answer: beat a %s the day after one beat you." % SkinManager.name_of("enemy_boss_one"))
	_dirty = true


## You dropped under 10% health and came back to 50%: your gear saved you.
func on_saved():
	for it in Crafting.equipped_items():
		_life(it).saves += 1
	_dirty = true


## A rival was beaten while you wore this gear (Rivals call this).
func on_rival_beaten():
	for it in Crafting.equipped_items():
		_life(it).rivals += 1
	_dirty = true


func on_death(tier):
	if tier == null:
		return
	if tier == 3:
		_losses[3] = Time.get_date_string_from_system()
	once("death", "Fell for the first time. Got back up.")
	_save()


## Started wearing it: the day it was first worn (and it's yours now; see Crafting.equip).
func on_equip(item: Dictionary):
	var life = _life(item)
	if life.first_worn == "":
		life.first_worn = Time.get_date_string_from_system()


func _life(item: Dictionary) -> Dictionary:
	if not item.has("life"):
		item.life = {kills = 0, bosses = 0, rivals = 0, saves = 0, first_worn = ""}
	return item.life


# Gear records are saved with Crafting, a few seconds after they change (not every kill)
var _dirty := false
var _save_t := 0.0

func _process(delta):
	if not _dirty:
		return
	_save_t += delta
	if _save_t > 5.0:
		_save_t = 0.0
		_dirty = false
		Crafting.save()


## Titles an item has earned from its story, best first.
func titles(item: Dictionary) -> Array:
	var t = []
	var life = item.get("life", {})
	var s = item.get("story", {})
	var o = s.get("origin", {})
	if life.get("rivals", 0) >= 1:
		t.append("Rivalbane")
	if life.get("saves", 0) >= 10:
		t.append("Old Faithful")
	if o.get("low", 100) <= 5:
		t.append("of the Last Breath")
	if o.get("tries", 1) >= 5:
		t.append("The Stubborn")
	if life.get("bosses", 0) >= 5:
		t.append(SkinManager.name_of("enemy_boss_one") + "bane")
	if s.has("given_to"):
		t.append("Gift of " + s.get("maker", "a friend"))
	if life.get("kills", 0) >= 1000:
		t.append("Veteran")
	return t


## Name with its best title: Copper Blade "Old Faithful"
func display_name(item: Dictionary) -> String:
	var t = titles(item)
	return item.name if t.is_empty() else "%s \"%s\"" % [item.name, t[0]]


## Story lines for an item's description.
func item_lines(item: Dictionary) -> Array:
	var lines = []
	var s = item.get("story", {})
	if s.has("maker"):
		var made = "Made by %s on Day %d" % [s.maker, s.get("day", 1)]
		if s.has("given_to"):
			made += ", for %s" % s.given_to
		lines.append(made)
	var o = s.get("origin", {})
	if not o.is_empty():
		var l = "Recipe: Sigil of %s %s, Day %d" % [Trials.ability_name(o.ability), Trials.ROMAN[clampi(o.level, 1, Trials.MAX_LEVEL)], o.day]
		if o.zone != "":
			l += " in " + o.zone
		l += ", " + ("first try" if o.tries <= 1 else _ordinal(o.tries) + " try")
		if o.low < 100:
			l += ", %d%% health left" % o.low
		if o.get("pet", false):
			l += ", " + SkinManager.name_of("pet") + " at your side"
		lines.append(l)
	var life = item.get("life", {})
	if life.get("first_worn", "") != "":
		var bits = ["%d foes" % life.kills]
		if life.bosses > 0:
			bits.append("%d %s" % [life.bosses, SkinManager.name_of("enemy_boss_one" if life.bosses == 1 else "enemy_boss").to_lower()])
		if life.rivals > 0:
			bits.append("%d rival%s" % [life.rivals, "" if life.rivals == 1 else "s"])
		if life.saves > 0:
			bits.append("saved you %d time%s" % [life.saves, "" if life.saves == 1 else "s"])
		var worn_by = item.get("bound_to", "")
		lines.append("Worn since %s%s: %s" % [life.first_worn, (" by " + worn_by) if worn_by != "" else "", ", ".join(bits)])
	var t = titles(item)
	if t.size() > 0:
		lines.append("Titles: " + ", ".join(t))
	return lines
