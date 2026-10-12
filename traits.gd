extends Node
## Autoload "Traits": who you're becoming. Six tensions, each a slider from -100 to +100.
## You don't spend points: HOW you play slowly moves them. Each end gives a small edge
## (up to about 12%), so neither side is "wrong". The character screen (C) shows the sliders.
##
##   Swift <-> Steadfast    skip vs. clear 99% of a map and avenge rivals
##   Fury <-> Precision     sweeps and fast attack speed vs. single strikes and heavy attack speed
##   Bold <-> Wary          fight hurt and pull big groups vs. heal early and take one group at a time
##   Self <-> Kin           solo and keep everything vs. play with friends, heal them, give gear, guard your pet
##   Wanderer <-> Keeper    explore, find new places vs. refine, craft, rest on time
##   Patient <-> Driven     rest on time (stacks +1% damage and health, up to 10%) vs. play past the flow
##                          timer (+5% while "Driven", but -2% for every minute past 25:00)
##
## Negative values = the LEFT name, positive = the RIGHT name.

signal changed

var SAVE_PATH: String:	# this character's save (Account)
	get:
		return Account.path("traits.cfg")
const EDGE = 0.12	# the most any pole gives

const TENSIONS = {
	"pace": {left = "Swift", right = "Steadfast",
		left_tip = "You move faster (up to +12% move speed).\nGrows when you skip enemies, leave zones early, or walk past your Rivals.",
		right_tip = "You're tougher (up to +12% max health, 6% less damage taken).\nGrows when you clear 99% of a map or go back and beat a Rival that killed you."},
	"style": {left = "Fury", right = "Precision",
		left_tip = "Wider sweeps (right click), and from halfway on, +1 enemy hit.\nGrows when you use sweeps and a fast attack speed (character window, C).",
		right_tip = "Harder single strikes (left click, up to +12%) and a chance to crit for double.\nGrows when you use single strikes and a heavy attack setting."},
	"nerve": {left = "Bold", right = "Wary",
		left_tip = "More damage while you're under half health (up to +12%).\nGrows when you fight at low health or take on 5+ enemies at once.",
		right_tip = "Enemies notice you from closer (up to 12% less), and potions heal more.\nGrows when you heal or drink before half health, and fight one small group at a time."},
	"bond": {left = "Self", right = "Kin",
		left_tip = "More gold from every pickup (up to +12%).\nGrows when you play solo.",
		right_tip = "Your heals on others are stronger, and your pet takes less damage and bonds faster.\nGrows when you play with friends, heal them, give them gear, or protect your pet."},
	"roam": {left = "Wanderer", right = "Keeper",
		left_tip = "You see farther: the fog clears wider and you spot resources from farther away.\nGrows when you explore new ground, new zones and shrines.",
		right_tip = "Better crafting: gear you make comes out up to 12% stronger.\nGrows when you refine, craft and rest at Home on time."},
	"rest": {left = "Patient", right = "Driven",
		left_tip = "Each rest taken on time adds +1% damage and max health (up to +10%).\nGo Home between 20 and 26 minutes of flow.",
		right_tip = "Past 25:00 of flow you're Driven: +5% more, but -2% for every minute over.\nUsed sparingly it pays; stay out too long and it costs you."},
}
const ORDER = ["pace", "style", "nerve", "bond", "roam", "rest"]

var values := {}		# tension -> -100..100
var history := {}		# tension -> last few reasons ["+ Steadfast: cleared Zone 2"]
var patient_stacks := 0	# 0..10: +1% damage and max health each
var _cleared := {}		# zone paths already counted as "cleared 99%" this session
var seen_zones := {}	# zones you've been to (for Wanderer)
var _tick := 0.0


func _ready():
	load_character()
	Rivals.avenged.connect(func(r): nudge("pace", 8.0, "beat your Rival " + r.name))
	Rivals.skipped.connect(func(r): nudge("pace", -4.0, "walked past your Rival " + r.name))
	SessionManager.break_started.connect(_on_break)
	Zones.entered.connect(_on_entered)


func load_character():
	values = {}
	history = {}
	patient_stacks = 0
	seen_zones = {}
	_cleared = {}
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		values = cfg.get_value("traits", "values", {})
		history = cfg.get_value("traits", "history", {})
		patient_stacks = cfg.get_value("traits", "patient_stacks", 0)
		seen_zones = cfg.get_value("traits", "seen_zones", {})
	for t in ORDER:
		values[t] = float(values.get(t, 0.0))
	changed.emit()


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("traits", "values", values)
	cfg.set_value("traits", "history", history)
	cfg.set_value("traits", "patient_stacks", patient_stacks)
	cfg.set_value("traits", "seen_zones", seen_zones)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Traits: couldn't save " + SAVE_PATH)


## Move a tension. amount > 0 = toward the RIGHT name. reason "" = small, frequent nudge (not listed).
func nudge(t: String, amount: float, reason := ""):
	if not values.has(t):
		ErrorLog.fail("Traits: unknown tension '%s'" % t)
		return
	var old = values[t]
	values[t] = clamp(old + amount, -100.0, 100.0)
	if reason != "":
		var side = TENSIONS[t].right if amount > 0 else TENSIONS[t].left
		var h = history.get(t, [])
		h.append("%s %s: %s" % ["+" if amount > 0 else "-", side, reason])
		history[t] = h.slice(max(0, h.size() - 5))
	_dirty = true
	if int(old / 25.0) != int(values[t] / 25.0):	# crossed a step: refresh stats
		changed.emit()


var _dirty := false
var _save_t := 0.0


## How far toward each pole, 0..1.
func left(t: String) -> float:
	return clamp(-values.get(t, 0.0) / 100.0, 0.0, 1.0)

func right(t: String) -> float:
	return clamp(values.get(t, 0.0) / 100.0, 0.0, 1.0)


func label(t: String) -> String:
	var v = values.get(t, 0.0)
	if abs(v) < 10.0:
		return "Balanced"
	var side = TENSIONS[t].right if v > 0 else TENSIONS[t].left
	var how = "Leaning" if abs(v) < 40.0 else ("Mostly" if abs(v) < 75.0 else "Deeply")
	return "%s %s" % [how, side]


# ---------------- Effects (the player and others ask these) ----------------

func move_mult() -> float:
	return 1.0 + EDGE * left("pace")

func health_mult() -> float:
	return (1.0 + EDGE * right("pace")) * (1.0 + rest_bonus())

func damage_taken_mult() -> float:
	return 1.0 - EDGE * 0.5 * right("pace")

## Every hit: Bold (when under half health) and the rest bonus.
func damage_mult(health_frac: float) -> float:
	var m = 1.0 + rest_bonus()
	if health_frac < 0.5:
		m *= 1.0 + EDGE * left("nerve")
	return m

func strike_mult() -> float:
	return 1.0 + EDGE * right("style")

func crit_chance() -> float:
	return 0.08 * right("style")

func sweep_cone_shift() -> float:	# lower dot = wider cone
	return 0.25 * left("style")

func sweep_extra_targets() -> int:
	return 1 if left("style") >= 0.5 else 0

func aggro_mult() -> float:
	return 1.0 - EDGE * right("nerve")

func potion_mult() -> float:
	return 1.0 + EDGE * right("nerve")

func gold_mult() -> float:
	return 1.0 + EDGE * left("bond")

func heal_others_mult() -> float:
	return 1.0 + EDGE * right("bond")

func pet_guard_mult() -> float:	# damage your pet takes
	return 1.0 - EDGE * right("bond")

func sight_mult() -> float:
	return 1.0 + EDGE * 2.0 * left("roam")

func craft_mult() -> float:
	return 1.0 + EDGE * right("roam")


## Patient stacks and Driven: +1% per stack; past 25:00, +5% and then -2% per minute over.
func rest_bonus() -> float:
	var b = patient_stacks * 0.01
	var over = SessionManager.flow_seconds - SessionManager.FLOW_TARGET
	if over > 0.0 and GameState.current_zone != "Home":
		b += 0.05 - 0.02 * floor(over / 60.0)
	return clamp(b, -0.20, 0.15)


func is_driven() -> bool:
	return SessionManager.flow_seconds > SessionManager.FLOW_TARGET and GameState.current_zone != "Home"


func rest_text() -> String:
	var t = "Patient stacks: %d / 10 (+%d%%)" % [patient_stacks, patient_stacks]
	if is_driven():
		t += "   DRIVEN: total %+d%%" % roundi(rest_bonus() * 100.0)
	return t


# ---------------- What moves them ----------------

func _on_break(_blocks):
	var flow = _last_flow
	_last_flow = 0.0
	if flow >= SessionManager.MIN_BLOCK and flow <= SessionManager.FLOW_TARGET + 60.0:
		if patient_stacks < 10:
			patient_stacks += 1
		nudge("rest", -8.0, "rested on time (%d min)" % roundi(flow / 60.0))
		nudge("roam", 3.0, "rested at Home on time")
		GameState.notify("Patient: rested on time. +1%% damage and health (now +%d%%)" % patient_stacks)
	elif flow > SessionManager.FLOW_TARGET + 60.0:
		var over = int((flow - SessionManager.FLOW_TARGET) / 60.0)
		nudge("rest", min(3.0 * over, 20.0), "pushed %d min past the flow timer" % over)
	changed.emit()
	_save()


var _last_flow := 0.0
var _driven_said := false
var _enemies_on_me := 0


func _process(delta):
	if SessionManager.flow_seconds > 0.0:
		_last_flow = SessionManager.flow_seconds
	if _dirty:
		_save_t += delta
		if _save_t > 5.0:
			_save_t = 0.0
			_dirty = false
			_save()
	_tick += delta
	if _tick < 2.0:
		return
	_tick = 0.0
	var p = Zones.player
	if p == null or not p.is_inside_tree():
		return
	# Driven: say it once when it starts, and keep stats fresh as the bonus slides
	if is_driven():
		if not _driven_said:
			_driven_said = true
			GameState.notify("Driven! +5% for now... but -2% for every minute past 25:00.")
		changed.emit()
	else:
		_driven_said = false
	if GameState.current_zone == "Home":
		return
	# Bold or Wary: how many enemies are on you right now
	var on_me = 0
	for e in Zones.local_all("enemy"):
		if e.aggroed and e.player == p and e.global_position.distance_to(p.global_position) < 10.0:
			on_me += 1
	if on_me >= 5:
		nudge("nerve", -0.5)
	elif on_me >= 1 and on_me <= 3 and p.health > p.MAX_HEALTH * 0.5:
		nudge("nerve", 0.15)
	# Self or Kin: playing alone or with friends (every 2 s)
	if Net.is_online() and GameState.party(p).size() > 1:
		nudge("bond", 0.06)
	elif not Net.is_online():
		nudge("bond", -0.03)
	# Fury or Precision: the attack speed setting
	if p.speed_level > 0:
		nudge("style", -0.05)
	elif p.speed_level < 0:
		nudge("style", 0.05)


## Called by the player on each attack.
func on_strike():
	nudge("style", 0.12)

func on_sweep():
	nudge("style", -0.12)


## A hit landed while you were under 30% health.
func on_hurt_fight():
	nudge("nerve", -0.3)

## You healed (potion or skill) while still above half health.
func on_early_heal():
	nudge("nerve", 1.0)


func on_heal_other():
	nudge("bond", 0.4)

func on_guarded_pet():
	nudge("bond", 0.5)

func on_gave_gear(to: String):
	nudge("bond", 6.0, "gave gear to " + to)


func on_refine():
	nudge("roam", 0.5)

func on_craft(item_name: String):
	nudge("roam", 1.5, "crafted " + item_name)

func on_new_ground():
	nudge("roam", -0.04)

func on_found_shrine():
	nudge("roam", -2.0, "found a shrine")


## 99% of a map's enemies are down (once per zone per session).
func on_zone_cleared(path: String, zone_name: String):
	if _cleared.has(path):
		return
	_cleared[path] = true
	nudge("pace", 10.0, "cleared 99% of " + zone_name)
	Story.add("Cleared nearly every foe in %s." % zone_name)
	var banner = load("res://steadfast_flag.gd").new()	# the pop-up flag
	banner.zone_name = zone_name
	get_tree().root.add_child(banner)
	if Zones.player:
		banner.plant(Zones.player)


func _on_entered(z):
	if z == null or z.path == "res://Home.tscn" or "#" in z.key:
		return
	if not seen_zones.has(z.path):	# a brand new place
		seen_zones[z.path] = true
		nudge("roam", -5.0, "first steps into " + GameState.ZONE_NAMES.get(z.path, "a new zone"))


## You left a zone (Net.go) with less than half of it cleared.
func on_left_early(zone_name: String):
	nudge("pace", -2.0, "left %s early" % zone_name)
