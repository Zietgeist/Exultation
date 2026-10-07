extends "res://lm_base.gd"
## Event town (Market / Survivor Camp / Trade Convoy): a few houses around a heart (Town Well /
## Camp Generator / Convoy Core). Come close and, after a short warning, raiders attack the heart.
## Hold out for 3 minutes: the town is SAVED (a gift of gold, a free meal, a Chronicle entry).
## If the heart falls, the town FALLS and stays a ruin (saved with the party). One raid per town.
## Leave the zone mid-raid and it's called off (try again later). The host runs the raid.

const TRIGGER = 45.0
const WARNING = 10.0
const DURATION = 180.0
const WAVE_EVERY = 15.0

var heart_max := 1000.0
var heart := 1000.0
var phase := "calm"		# calm / warning / raid / done
var time_left := 0.0
var _wave_t := 0.0
var _houses := []
var _status: Label3D
var _heart_mesh: MeshInstance3D


func title_height() -> float:
	return 10.0


func build():
	heart_max = 800.0 + 200.0 * info.zone
	heart = heart_max
	var style = SkinManager.props_style()
	var wm = mat("lm_event_wall", {"zombie": Color(0.45, 0.4, 0.35), "scifi": Color(0.55, 0.6, 0.65)}.get(style, Color(0.6, 0.5, 0.38)))
	var rm = mat("lm_event_roof", {"zombie": Color(0.3, 0.3, 0.28), "scifi": Color(0.85, 0.55, 0.2)}.get(style, Color(0.45, 0.6, 0.3)))
	for i in 5:
		var a = TAU * i / 5.0 + 0.3
		_houses.append(house(Vector3(cos(a), 0, sin(a)) * 15.0, Vector3(6, 3.5, 5), wm, rm, -a))
	_heart_mesh = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 1.3
	cyl.bottom_radius = 1.6
	cyl.height = 2.0
	_heart_mesh.mesh = cyl
	_heart_mesh.position.y = 1.0
	_heart_mesh.material_override = mat("lm_heart", Color(0.4, 0.8, 1.0), true)
	add_child(_heart_mesh)
	_status = label("", Vector3(0, 5.5, 0), 34, Color(1.0, 0.8, 0.4))
	var s = state()
	if s.get("outcome", "") == "fallen":
		_ruin()
	elif s.get("outcome", "") == "saved":
		phase = "done"
		_status.text = "Saved by %s" % ", ".join(s.get("by", []))


## On the host while the raid runs, the heart is something enemies go after (like a pet).
func alive() -> bool:
	return phase == "raid" and heart > 0.0

func take_damage(amount, _source = null):
	if phase != "raid":
		return
	heart -= amount
	if heart <= 0.0:
		_finish(false)

func guarded():
	pass


func tick(dt: float):
	if Net.is_client():
		return
	match phase:
		"calm":
			if state().has("outcome"):
				phase = "done"
				return
			for m in GameState.party(self):
				if is_instance_valid(m) and Vector2(m.global_position.x - global_position.x, m.global_position.z - global_position.z).length() < TRIGGER:
					phase = "warning"
					time_left = WARNING
					announce("warning", {})
					break
		"warning":
			time_left -= dt
			if time_left <= 0.0:
				phase = "raid"
				time_left = DURATION
				_wave_t = 0.0
				add_to_group("pet")
				announce("raid", {})
		"raid":
			time_left -= dt
			_wave_t -= dt
			if _wave_t <= 0.0:
				_wave_t = WAVE_EVERY
				_wave()
			announce("hp", {hp = heart, max = heart_max, t = time_left})
			if time_left <= 0.0:
				_finish(true)


func _wave():
	var n = 4 + info.zone / 2
	var a0 = randf() * TAU
	for i in n:
		var a = a0 + randf_range(-0.6, 0.6)
		var e = spawn_enemy(1 if randf() < 0.2 else 0, Vector3(cos(a), 0, sin(a)) * 60.0)
		if e:
			e.aggroed = true
			e.hunter = true	# raiders keep coming
			count_for_zone(e)


func _finish(saved: bool):
	phase = "done"
	remove_from_group("pet")
	set_state({outcome = "saved" if saved else "fallen", by = Landmarks.who(), on = Time.get_date_string_from_system()})
	announce("saved" if saved else "fallen", {by = Landmarks.who()})


func net_event(event: String, data: Dictionary):
	match event:
		"warning":
			GameState.notify("Raiders are coming for %s! Guard the %s!" % [info.name, Landmarks.word("heart")])
			_status.text = "Raiders spotted!"
		"raid":
			phase = "raid" if not Net.is_client() else phase
			GameState.notify("The raid begins! Hold out for 3 minutes.")
		"hp":
			var t = int(data.t)
			_status.text = "%s %d / %d\nHold out: %d:%02d" % [Landmarks.word("heart"), data.hp, data.max, t / 60, t % 60]
		"saved":
			_status.text = "Saved!"
			GameState.notify("%s is saved! The townsfolk thank you." % info.name)
			GameState.gold_banked += 40 * info.zone
			GameState.save_progress()
			GameState.buffs["meal"] = true	# they feed you
			GameState.buffs_changed.emit()
			Story.add("Held off the raid on %s. The townsfolk fed us like heroes." % info.name)
			Traits.nudge("bond", 6.0, "defended " + info.name)
		"fallen":
			GameState.notify("%s has fallen..." % info.name)
			Story.add("%s fell to raiders. We couldn't hold it." % info.name)
			_ruin()


## Burnt and empty.
func _ruin():
	phase = "done"
	var burnt = mat("lm_burnt", Color(0.12, 0.1, 0.09))
	for h in _houses:
		for c in h.get_children():
			if c is MeshInstance3D:
				c.material_override = burnt
				if c.mesh is PrismMesh:
					c.visible = false	# roofs gone
	_heart_mesh.material_override = burnt
	_status.text = "(ruins)"
