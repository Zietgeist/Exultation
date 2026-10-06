extends RefCounted
## Map templates: the "shape" of a zone. From wide open to tightly channeled:
##   open_field -> rolling_hills -> forest -> river -> ruins -> rails   (+ island, a special one)
## Zone 1 is always the open field (if the world has it). Later zones pick at random
## from the templates the world skin allows:  "terrain": {"templates": [...], "names": {...}}
##
## Counts are for Zone 1 density; bigger zones scale them up (GameState.obstacle_multiplier).
##   hills, groves: terrain features (ore and herbs gather around them)
##   ditches: loose slow patches     low / solid: loose wall clusters
##   boxes: share of the 50 loose block obstacles (rocks, crates)
##   layout: the special builder that gives the template its shape (see terrain_generator.gd)

const ORDER = ["open_field", "rolling_hills", "forest", "river", "ruins", "rails", "island"]

const TEMPLATES = {
	"open_field": {name = "Open Field", hills = 2, groves = 3, ditches = 3, low = 1, solid = 0, boxes = 0.15, layout = ""},
	"rolling_hills": {name = "Rolling Hills", hills = 11, groves = 4, ditches = 3, low = 0, solid = 0, boxes = 0.2, layout = "fences"},
	"forest": {name = "Forest", hills = 2, groves = 15, ditches = 5, low = 0, solid = 0, boxes = 0.15, layout = "clearings"},
	"river": {name = "River", hills = 3, groves = 7, ditches = 0, low = 0, solid = 0, boxes = 0.25, layout = "river"},
	"ruins": {name = "Ruins", hills = 1, groves = 3, ditches = 5, low = 0, solid = 0, boxes = 0.5, layout = "rooms"},
	"rails": {name = "Rails", hills = 0, groves = 2, ditches = 0, low = 0, solid = 0, boxes = 0.3, layout = "lanes"},
	"island": {name = "Island", hills = 4, groves = 6, ditches = 2, low = 1, solid = 0, boxes = 0.2, layout = "island"},
}

const ISLAND_SIZE = 0.66		# the island's radius as a share of the map's half size
const CAUSEWAY_HALF_WIDTH = 4.5	# land bridges from each gate to the island


static func get_def(id: String) -> Dictionary:
	return TEMPLATES.get(id, TEMPLATES.open_field)


## Templates this world allows (all of them if the skin doesn't say).
static func allowed() -> Array:
	var t = SkinManager.section("terrain")
	var list = []
	if t is Dictionary and t.has("templates"):
		for id in t.templates:
			if TEMPLATES.has(id):
				list.append(id)
			else:
				ErrorLog.fail("Skin '%s' lists an unknown map template '%s'. Known: %s" % [SkinManager.current_id, id, ", ".join(ORDER)])
	if list.is_empty():
		list = ORDER.duplicate()
	return list


## Zone 1: open field. Later zones: random pick from what the world allows.
static func pick(scene_path: String) -> String:
	var list = allowed()
	if scene_path == "res://Zone1.tscn":
		return "open_field" if "open_field" in list else list[0]
	return list.pick_random()


## Name for players, e.g. "Ruined Town" in the Zombie world.
static func label(id: String) -> String:
	var t = SkinManager.section("terrain")
	if t is Dictionary and t.get("names", {}).has(id):
		return t.names[id]
	return get_def(id).name


## Island maps: is this spot open water? (half = the map's half size, gates = gate positions)
static func is_island_water(pos: Vector3, half: Vector2, gates: Array) -> bool:
	var nx = pos.x / (half.x * ISLAND_SIZE)
	var nz = pos.z / (half.y * ISLAND_SIZE)
	if nx * nx + nz * nz <= 1.0:
		return false
	var p = Vector2(pos.x, pos.z)
	for g in gates:	# causeway: a straight strip from the gate to the middle
		var a = Vector2(g.x, g.z)
		var closest = Geometry2D.get_closest_point_to_segment(p, a, Vector2.ZERO)
		if p.distance_to(closest) < CAUSEWAY_HALF_WIDTH:
			return false
	return true
