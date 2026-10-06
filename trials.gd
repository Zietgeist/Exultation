extends Node
## Autoload "Trials": shrine trials on a spaced-repetition ladder, and the recipes they teach.
##
## The loop:  find a shrine (Zone 2 on) -> press G -> a short trial (no sound needed)
##   pass -> a gate opens to a small Trial Ground -> clear it -> the LAST enemy drops a Sigil
##   fail -> the shrine fades and shows up somewhere else in the zone (try again any time).
##
## THE LADDER: each ability has levels 1-8. Level 0 recipes come from the shop keepers.
## Earning level N teaches that ability's level-N recipe (much stronger each level).
## The next level only opens after a wait, growing like spaced-repetition review:
##   level 1 any time, level 2 a day after level 1, then 3 days, 1 week, 2 weeks, 1 month,
##   2 months, 6 months. Trials and Trial Grounds get harder with each level.
## Debug builds: Shift+F11 moves the trial clock 1 day forward (for testing).
##
## Each trial type is its own script in res://trials/ (extends trial_base.gd).
## Add one to TYPES and shrines start offering it.

const SAVE_PATH = "user://trials.cfg"
const ARENA = "res://TrialArena.tscn"
const MAX_LEVEL = 8
const DAY = 86400
# Wait after earning level N before level N+1 opens (index 0 = after level 1)
const WAITS = [1 * DAY, 3 * DAY, 7 * DAY, 14 * DAY, 30 * DAY, 60 * DAY, 180 * DAY]
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

# ability id -> {name, trial script, color, recipe family it improves}
const TYPES = {
	"precision": {name = "Precision", script = "res://trials/trace_path.gd", color = Color(1.0, 0.75, 0.3)},
	"numbers": {name = "Numbers", script = "res://trials/quick_math.gd", color = Color(0.4, 0.8, 1.0)},
	"sorting": {name = "Color", script = "res://trials/rainbow_order.gd", color = Color(1.0, 0.45, 0.8)},
	"typing": {name = "Swiftness", script = "res://trials/typing.gd", color = Color(0.5, 1.0, 0.5)},
	"logic": {name = "Logic", script = "res://trials/lights_out.gd", color = Color(0.75, 0.6, 1.0)},
}

# Ratings: pass +20, fail -110  ->  settles where you pass about 85% of the time
const START_RATING = 1000.0
const PASS_STEP = 20.0
const FAIL_STEP = 110.0
const EASIEST = 700.0		# rating that maps to difficulty 0
const HARDEST = 1700.0		# rating that maps to difficulty 1

var ratings := {}		# ability -> rating
var passes := {}		# ability -> times passed
var levels := {}		# ability -> {level, cleared (unix time it was earned)}
var time_offset := 0	# debug: trial clock moved forward (seconds)
var arena := {}			# (old) last Trial Ground info; zones carry their own info now


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		ratings = cfg.get_value("trials", "ratings", {})
		passes = cfg.get_value("trials", "passes", {})
		levels = cfg.get_value("trials", "levels", {})
		time_offset = cfg.get_value("trials", "time_offset", 0)
	for id in TYPES:
		if not ResourceLoader.exists(TYPES[id].script):
			ErrorLog.fail("Trial '%s' points at a missing script: %s" % [id, TYPES[id].script])


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("trials", "ratings", ratings)
	cfg.set_value("trials", "passes", passes)
	cfg.set_value("trials", "levels", levels)
	cfg.set_value("trials", "time_offset", time_offset)
	cfg.save(SAVE_PATH)


# ---------------- The ladder ----------------

func now() -> int:
	return int(Time.get_unix_time_from_system()) + time_offset


func level(id: String) -> int:
	return levels.get(id, {}).get("level", 0)


## The level the next trial of this ability is for (MAX_LEVEL + 1 = all done).
func next_level(id: String) -> int:
	return level(id) + 1


## When the next level opens (unix time). 0 = open now.
func opens_at(id: String) -> int:
	var l = level(id)
	if l == 0:
		return 0
	if l >= MAX_LEVEL:
		return -1
	return levels[id].get("cleared", 0) + WAITS[l - 1]


func is_due(id: String) -> bool:
	return level(id) < MAX_LEVEL and now() >= opens_at(id)


## "21h", "3 days" ... until the next level opens ("" when open now).
func wait_text(id: String) -> String:
	if level(id) >= MAX_LEVEL:
		return "mastered"
	var left = opens_at(id) - now()
	if left <= 0:
		return ""
	if left < 3600:
		return "%d min" % max(1, left / 60)
	if left < 2 * DAY:
		return "%dh" % (left / 3600)
	return "%d days" % (left / DAY)


func due_abilities() -> Array:
	return TYPES.keys().filter(func(id): return is_due(id))


func _unhandled_input(event):
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11 and event.shift_pressed:
		skip_days(1)


## Debug / testing: move the trial clock forward.
func skip_days(days: int):
	time_offset += days * DAY
	_save()
	GameState.notify("Trial clock moved %d day(s) forward" % days)


func ability_name(id: String) -> String:
	var names = SkinManager.section("trials")
	if names is Dictionary and names.has(id):
		return names[id]
	return TYPES.get(id, {}).get("name", id.capitalize())


## An ability for a new shrine: one whose next level is open, if there is one.
func random_ability() -> String:
	var due = due_abilities()
	return due.pick_random() if due.size() > 0 else TYPES.keys().pick_random()


## 0 (easiest) .. 1 (hardest): your rating in that ability, plus a step for each ladder level.
func difficulty(id: String) -> float:
	var base = (ratings.get(id, START_RATING) - EASIEST) / (HARDEST - EASIEST)
	return clamp(base + 0.07 * (next_level(id) - 1), 0.0, 1.0)


func record(id: String, passed: bool):
	var r = ratings.get(id, START_RATING)
	ratings[id] = r + PASS_STEP if passed else max(EASIEST - 200.0, r - FAIL_STEP)
	if passed:
		passes[id] = passes.get(id, 0) + 1
	_save()


## Start the trial UI for an ability. on_done(passed) is called when it ends.
func run(id: String, on_done: Callable):
	var ui = load("res://trial_ui.gd").new()
	get_tree().current_scene.add_child(ui)
	ui.start(id, difficulty(id), on_done)


# ---------------- Sigils (earning a level) ----------------

## The last enemy of a Trial Ground fell and you took its Sigil.
## If your next level of that ability is open, you earn it and learn its recipe.
func complete(id: String):
	if not is_due(id):
		var w = wait_text(id)
		GameState.notify("This %s Sigil fades... your next %s trial opens in %s." % [ability_name(id), ability_name(id), w] if w != "mastered" else "You've mastered %s." % ability_name(id))
		return
	var l = next_level(id)
	levels[id] = {level = l, cleared = now()}
	_save()
	var recipe = Crafting.advanced_id(id, l)
	var text = "Sigil of %s %s! New recipe: %s." % [ability_name(id), ROMAN[l], Crafting.recipe(recipe).label]
	if l < MAX_LEVEL:
		text += " Next %s trial opens in %s." % [ability_name(id), wait_text(id)]
	GameState.notify(text)
	Crafting.changed.emit()


## (Old saves) Sigils used to be crafting materials. Kept so old calls still work.
func grant_sigil(id: String, _q := 1):
	complete(id)
