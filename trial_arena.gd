extends Node3D
## A Trial Ground: the small zone behind a trial gate. Clear it; the LAST enemy drops the Sigil.
## The exit gate (by where you came in) takes you back to the shrine's spot. Nothing here is remembered.
## Online: the host runs the enemies; when it's cleared every player gets their own Sigil.

const ENEMY_SCENE = preload("res://enemy.tscn")
const START = Vector3(0, 1, 15)

var info := {}		# {ability, q, back_scene, back_pos}
var alive := 0
var cleared := false


func _ready():
	var z = Zones.zone_of(self)
	info = z.info if z and not z.info.is_empty() else {ability = "precision", q = 1, back_scene = "res://Home.tscn", back_pos = Vector3(0, 1, 8)}
	if z:
		z.zone_name = SkinManager.name_of("trial_arena")
	_exit_gate.call_deferred()
	if not Net.is_client():
		_spawn_foes.call_deferred()
	if Zones.local_zone() == z:
		GameState.notify.call_deferred("%s of %s %s: clear it! The last foe holds the Sigil." % [SkinManager.name_of("trial_arena"), Trials.ability_name(info.ability), Trials.ROMAN[clampi(int(info.get("level", 1)), 1, Trials.MAX_LEVEL)]])


## Foes get tougher with the zone the shrine was in (q 1 = Zone 2) and much tougher with the
## trial level (I-VIII): more of them, more health, and a boss from level V on.
func _spawn_foes():
	var q = int(info.q)
	var lv = int(info.get("level", 1))
	var diff = (1.0 + 0.5 * (q - 1)) * (1.0 + 0.6 * (lv - 1))
	var groups = [[0, 8 + 2 * q + 2 * (lv - 1)], [1, 2 + q + (lv - 1)], [2, 1 + int((lv - 1) / 2.0)]]	# [tier, how many]
	if lv >= 5:
		groups.append([3, 1])
	for g in groups:
		for i in range(g[1]):
			var e = ENEMY_SCENE.instantiate()
			e.enemy_died.connect(_on_enemy_died.bind(e))
			add_child(e)
			e.global_position = Vector3(randf_range(-16, 16), 1.2, randf_range(-16, 2))
			e.setup(diff, g[0], Crafting.roll_enemy_element(info.get("back_scene", ""), false))
			alive += 1


func _on_enemy_died(_tier, e):
	alive -= 1
	if alive <= 0 and not cleared:
		_cleared(e.global_position)


func _cleared(at: Vector3):
	cleared = true
	if Zones.first(self, "player"):	# I'm here: my own Sigil
		_drop_sigil(at)
	Net.scene_event(self, "cleared", {at = at, ability = info.ability, q = info.q})	# everyone else here gets theirs


## Online, joined player: the host says the ground is clear.
func net_event(event: String, data: Dictionary):
	if event == "cleared" and not cleared:
		cleared = true
		info.ability = data.ability
		info.q = data.q
		_drop_sigil(data.at)


func _drop_sigil(at: Vector3):
	GameState.notify("Cleared! Take the Sigil.")
	var s = Area3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 1.2
	var col = CollisionShape3D.new()
	col.shape = shape
	s.add_child(col)
	var mesh = MeshInstance3D.new()
	var pm = PrismMesh.new()
	pm.size = Vector3(0.8, 1.0, 0.8)
	mesh.mesh = pm
	var mat = StandardMaterial3D.new()
	var c = Trials.TYPES[info.ability].color
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.position.y = 1.2
	s.add_child(mesh)
	var tw = mesh.create_tween().set_loops()
	tw.tween_property(mesh, "rotation:y", TAU, 2.0).from(0.0)
	add_child(s)
	s.global_position = Vector3(at.x, 0, at.z)
	s.body_entered.connect(func(body):
		if body.name == "Player" and is_instance_valid(s):
			Trials.complete(info.ability)
			s.queue_free())


func _exit_gate():
	var g = load("res://portal.gd").new()
	g.target_scene = info.back_scene
	g.target_position = info.back_pos
	g.label_text = "Return"
	add_child(g)
	g.position = Vector3(0, 0, 19)
	g.rotation.y = 0.0
