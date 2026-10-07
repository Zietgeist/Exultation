extends Node3D
## A shrine (terminal / altar, named by the world skin). Press G next to it to take its trial.
## Pass: a gate to a Trial Ground opens right here. Fail: the shrine fades and appears elsewhere in the zone.
## Placed and saved by terrain_generator.gd (kind "shrine"), from Zone 2 on.

var ability := "precision"
var reach := 0.8
var busy := false
var _label: Label3D
var _crystal: MeshInstance3D


func _ready():
	add_to_group("npc")	# so G (talk) picks it, like a shopkeeper
	add_to_group("shrine")
	var color = Trials.TYPES[ability].color
	var base = MeshInstance3D.new()
	var bm = CylinderMesh.new()
	bm.top_radius = 0.7
	bm.bottom_radius = 1.0
	bm.height = 1.2
	base.mesh = bm
	base.position.y = 0.6
	base.material_override = SkinManager.material("shrine_stone", Color(0.45, 0.43, 0.48))
	add_child(base)
	_crystal = MeshInstance3D.new()
	var cm = PrismMesh.new()
	cm.size = Vector3(0.7, 1.2, 0.7)
	_crystal.mesh = cm
	_crystal.position.y = 2.1
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	_crystal.material_override = mat
	add_child(_crystal)
	var body = StaticBody3D.new()	# you bump into it, enemies walk around it
	var shape = CylinderShape3D.new()
	shape.radius = 0.9
	shape.height = 1.4
	var col = CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.7
	body.add_child(col)
	add_child(body)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 3.4
	_label.font_size = 40
	_label.pixel_size = 0.012
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.modulate = color
	add_child(_label)
	set_highlight(false)


func _process(delta):
	_label_t -= delta
	if _label_t <= 0.0:	# the wait counts down while you watch
		_label_t = 5.0
		_refresh_label()
	_crystal.rotation.y += delta * 1.5
	_crystal.position.y = 2.1 + sin(Time.get_ticks_msec() / 500.0) * 0.15


func horizontal_distance(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


var _lit := false

func set_highlight(on: bool):
	_lit = on
	_refresh_label()


## "Shrine of Logic III" when your next level is open; "rests: 21h" when it isn't yet.
func _refresh_label():
	var title = "%s of %s" % [SkinManager.name_of("shrine"), Trials.ability_name(ability)]
	var wait = Trials.wait_text(ability)
	if wait == "":
		title += " " + Trials.ROMAN[min(Trials.next_level(ability), Trials.MAX_LEVEL)]
		_label.text = title + ("\nG: take the trial" if _lit else "")
		_crystal.visible = true
	else:
		_label.text = title + "\n" + ("mastered" if wait == "mastered" else "rests for you: " + wait)
		_crystal.visible = false	# dim: nothing for you here yet


var _label_t := 0.0

## Player pressed G here.
func talk():
	if busy:
		return
	if not Trials.is_due(ability):
		var w = Trials.wait_text(ability)
		GameState.notify("This shrine rests for you. " + ("You've mastered %s." % Trials.ability_name(ability) if w == "mastered" else "Your next %s trial opens in %s." % [Trials.ability_name(ability), w]))
		return
	busy = true
	if not has_meta("found"):
		set_meta("found", true)
		Traits.on_found_shrine()	# Wanderer
	Trials.run(ability, _on_result)


func _on_result(passed: bool):
	busy = false
	var terrain = get_parent()
	if passed:
		terrain.open_trial_gate(self)
	else:
		GameState.notify("The %s fades... and appears somewhere else." % SkinManager.name_of("shrine").to_lower())
		terrain.move_shrine(self)
