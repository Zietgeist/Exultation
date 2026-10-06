extends Node
## Autoload "Zones": the world is ONE scene (World.tscn) that holds your player, camera and HUD.
## Zones (Home, Zone 1, Zone 2...) load into it as content, each in its own little world
## (a SubViewport with its own physics), so several zones can run at the same time without
## touching each other. That's what lets players be in different places (online: the host runs
## every zone that has a player in it).
##
## Rules for code:
##   - Never use get_tree().current_scene to mean "the zone". Use Zones.
##   - Never use get_tree().get_nodes_in_group(...) for zone things (enemies, doors, spawner...).
##     Use Zones.all(self, "enemy") / Zones.first(self, "zone_spawner"): only things in YOUR zone.
##   - UI asks about the local player's zone: Zones.local_first("zone_spawner"), Zones.local_path().
##   - Things you add to the world (effects, drops) go in a zone: Zones.root_of(self).add_child(x)
##
## Opening a zone scene straight from the editor (Run Current Scene) still works: it starts the
## World and puts you in that zone.

const WORLD = "res://World.tscn"
const CLASS_SELECT = "res://ClassSelect.tscn"
const STRIP = ["Player", "HUD", "Camera3D"]	# old per-zone copies; the World has the real ones
const ZONE_SCRIPT = preload("res://zone.gd")

signal entered(zone)		# the local player arrived in a zone

var world = null		# the World node (World.tscn)
var zones := {}			# scene path -> zone (zone.gd, a SubViewport)
var player = null		# the local player (persistent)
var _start_path := "res://Home.tscn"
var _keep := {}			# scene path -> true: keep loaded even with no local player (online host)


func _ready():
	_check_direct_run.call_deferred()


## Ran a zone scene directly from the editor: hop into the World with that zone.
func _check_direct_run():
	var scene = get_tree().current_scene
	if scene == null or world != null:
		return
	var path = scene.scene_file_path
	if path == WORLD or path == CLASS_SELECT or not scene is Node3D:
		return
	print("Zones: started in %s directly; opening the World there" % path)
	start(path)


## Leave the menus and start playing in a zone.
func start(path: String):
	_start_path = path
	zones.clear()
	world = null
	player = null
	get_tree().change_scene_to_file.call_deferred(WORLD)


## world.gd calls this once the World scene is up.
func world_ready(w):
	world = w
	player = load("res://Player.tscn").instantiate()
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.top_level = true	# follows by code, doesn't spin with the player
	cam.rotation_degrees = Vector3(-60, 0, 0)
	player.add_child(cam)
	player.camera = cam
	travel(_start_path)


# ---------------- Moving the local player ----------------

## Take the local player to a zone. Set GameState.pending_spawn first to arrive at a spot,
## otherwise you arrive by the door you came from.
func travel(path: String):
	if world == null:
		start(path)
		return
	if not ResourceLoader.exists(path):
		ErrorLog.fail("Zones.travel: no such zone scene: " + path)
		return
	var old = zone_of(player) if player.is_inside_tree() else null
	if old and old.path == path:
		player.arrive()
		return
	if old:
		GameState.previous_scene = old.path
	var z = zones.get(path)
	if z == null:
		z = load_zone(path, true)
	else:
		world.show_zone(z)
	if player.get_parent():
		player.get_parent().remove_child(player)
	z.add_child(player)
	player.camera.make_current()
	if old and not is_busy(old):
		unload(old)
	GameState.current_zone = z.zone_name
	player.arrive.call_deferred()
	entered.emit(z)


## Load a zone's scene into its own little world.
func load_zone(path: String, on_screen := false):
	var z = ZONE_SCRIPT.new()
	z.path = path
	z.name = path.get_file().get_basename()
	var scene = load(path).instantiate()
	for n in STRIP:	# the World supplies the player, camera and HUD
		var old = scene.get_node_or_null(n)
		if old:
			if n == "Player":
				z.default_spawn = old.position
			scene.remove_child(old)
			old.free()
	z.root = scene
	z.add_child(scene)
	zones[path] = z
	if on_screen:
		world.show_zone(z)
	else:
		world.park(z)
	return z


## Save a zone's state (kills, layout, fog) and remove it.
func unload(z):
	GameState.remember_zone(z)
	zones.erase(z.path)
	z.queue_free()


## Something still needs this zone running (a player in it, or online the host keeps it).
func is_busy(z) -> bool:
	if _keep.has(z.path):
		return true
	for p in get_tree().get_nodes_in_group("party"):
		if p.get_viewport() == z and p != player:
			return true
	return false


func keep_loaded(path: String, on: bool):
	if on:
		_keep[path] = true
	else:
		_keep.erase(path)


# ---------------- Finding things in a zone ----------------

## The zone a node is in (or null).
func zone_of(node):
	if node == null or not node.is_inside_tree():
		return null
	var v = node.get_viewport()
	return v if v is ZONE_SCRIPT else null


func path_of(node) -> String:
	var z = zone_of(node)
	return z.path if z else ""


## The zone's scene root (where world objects like enemies, effects and drops go).
func root_of(node):
	var z = zone_of(node)
	return z.root if z else null


## First node of a group in the same zone as `node`.
func first(node, group: String):
	var v = node.get_viewport() if node and node.is_inside_tree() else null
	for n in get_tree().get_nodes_in_group(group):
		if n.get_viewport() == v:
			return n
	return null


## All nodes of a group in the same zone as `node`.
func all(node, group: String) -> Array:
	var v = node.get_viewport() if node and node.is_inside_tree() else null
	return get_tree().get_nodes_in_group(group).filter(func(n): return n.get_viewport() == v)


## The local player's zone, its path and its scene root.
func local_zone():
	return zone_of(player) if player else null

func local_path() -> String:
	var z = local_zone()
	return z.path if z else ""

func local_root():
	var z = local_zone()
	return z.root if z else null

func local_first(group: String):
	return first(player, group) if player and player.is_inside_tree() else null

func local_all(group: String) -> Array:
	return all(player, group) if player and player.is_inside_tree() else []


## Back to the menus: forget the World.
func reset():
	world = null
	player = null
	zones.clear()
	_keep.clear()


func get_zone(path: String):
	return zones.get(path)
