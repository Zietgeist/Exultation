extends Node
## Autoload "Trials": shrine trials that test a skill, and the Sigils they lead to.
##
## The loop:  find a shrine (Zone 2 on) -> press G -> a short trial (20-45 s, no sound needed)
##   pass -> a gate opens to a small Trial Ground -> clear it -> the LAST enemy drops a Sigil
##   fail -> the shrine fades and shows up somewhere else in the zone.
## Sigils are crafting materials. Advanced recipes need one. The first Sigil of a kind also
## teaches that advanced recipe for good.
##
## Each trial type is its own script in res://trials/ (extends trial_base.gd).
## Add one to TYPES (or a mod's "trials" folder later) and shrines start offering it.
## Every ability has its own hidden rating, tuned so you pass about 85% of the time.

const SAVE_PATH = "user://trials.cfg"
const ARENA = "res://TrialArena.tscn"

# ability id -> {name, trial script, color, sigil material, advanced recipe it teaches}
const TYPES = {
	"precision": {name = "Precision", script = "res://trials/trace_path.gd", color = Color(1.0, 0.75, 0.3), recipe = "masterwork_blade"},
	"numbers": {name = "Numbers", script = "res://trials/quick_math.gd", color = Color(0.4, 0.8, 1.0), recipe = "tally_plate"},
	"sorting": {name = "Color", script = "res://trials/rainbow_order.gd", color = Color(1.0, 0.45, 0.8), recipe = "prism_ring"},
	"typing": {name = "Swiftness", script = "res://trials/typing.gd", color = Color(0.5, 1.0, 0.5), recipe = "windrunner_boots"},
	"logic": {name = "Logic", script = "res://trials/lights_out.gd", color = Color(0.75, 0.6, 1.0), recipe = "grand_elixir"},
}

# Ratings: pass +20, fail -110  ->  settles where you pass about 85% of the time
const START_RATING = 1000.0
const PASS_STEP = 20.0
const FAIL_STEP = 110.0
const EASIEST = 700.0		# rating that maps to difficulty 0
const HARDEST = 1700.0		# rating that maps to difficulty 1

var ratings := {}		# ability -> rating
var passes := {}		# ability -> times passed
var arena := {}			# the Trial Ground we're heading into / in: {ability, q, back_scene, back_pos}


func _ready():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		ratings = cfg.get_value("trials", "ratings", {})
		passes = cfg.get_value("trials", "passes", {})
	for id in TYPES:
		if not ResourceLoader.exists(TYPES[id].script):
			ErrorLog.fail("Trial '%s' points at a missing script: %s" % [id, TYPES[id].script])


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("trials", "ratings", ratings)
	cfg.set_value("trials", "passes", passes)
	cfg.save(SAVE_PATH)


func ability_name(id: String) -> String:
	var names = SkinManager.section("trials")
	if names is Dictionary and names.has(id):
		return names[id]
	return TYPES.get(id, {}).get("name", id.capitalize())


## A random ability for a new shrine.
func random_ability() -> String:
	return TYPES.keys().pick_random()


## 0 (easiest) .. 1 (hardest), from your rating in that ability.
func difficulty(id: String) -> float:
	return clamp((ratings.get(id, START_RATING) - EASIEST) / (HARDEST - EASIEST), 0.0, 1.0)


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


# ---------------- Sigils ----------------

func sigil_material(id: String) -> String:
	return "sigil_" + id


## The last enemy of a Trial Ground fell: the Sigil goes in your stash.
## The first Sigil of an ability also teaches its advanced recipe.
func grant_sigil(id: String, q: int):
	Crafting.add_material(sigil_material(id), q, 1)
	var recipe = TYPES[id].recipe
	var text = "You earned a %s!" % Crafting.material_name(sigil_material(id), q)
	if not Crafting.knows(recipe):
		Crafting.learn(recipe)
		text += "  New recipe: %s" % Crafting.BASES[recipe].label
	GameState.notify(text)
