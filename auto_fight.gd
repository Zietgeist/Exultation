extends Node
## Auto-attack, so fights are about where you stand and when you use E / Q / F, not clicking.
##   Tab: auto-attack on / off.   R: change which enemy is your main target.
##   Mouse wheel: the style (you choose, auto never switches on its own).
##     Up   = Single target: strikes on your main target. For the leader / the tough one.
##     Down = Multi target: sweeps, aimed where they catch the most. For a crowd of small ones.
##            (If nobody is close enough to sweep, it strikes instead.)
##   - Only fights enemies that are already after you. Auto never starts a fight.
##   - Your own clicks always win; auto waits while you hold a mouse button.
## The main target choice also applies to your own left clicks when the mouse isn't on an enemy.
## Also saves the attack speed setting (character window), so all controls live in one file.

const MODES = ["mouse", "closest", "strongest", "weakest", "most_health", "least_health"]
const MODE_NAMES = {
	mouse = "Nearest the mouse", closest = "Closest to you", strongest = "Strongest",
	weakest = "Weakest", most_health = "Most health", least_health = "Least health",
}
const MODE_TIPS = {
	mouse = "Strikes the enemy nearest your mouse pointer (or the closest one).",
	closest = "Strikes whichever enemy is closest to you.",
	strongest = "Bosses first, then Masters, Thugs, Trash. Rivals count as strongest.",
	weakest = "Trash first: thin the crowd before the big ones.",
	most_health = "The enemy with the most health left: wear down the tanky one.",
	least_health = "The enemy with the least health left: finish them off.",
}
const STANCES = ["single", "multi"]
const STANCE_NAMES = {single = "Single target", multi = "Multi target"}
const SAVE_PATH = "user://controls.cfg"

var on := false
var mode := "mouse"
var stance := "single"
var target = null		# the main target right now (shown with a ring)
var p					# the player
var _ring: MeshInstance3D


func _ready():
	p = get_parent()
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		on = cfg.get_value("auto", "on", false)
		mode = cfg.get_value("auto", "mode", "mouse")
		stance = cfg.get_value("auto", "stance", "single")
		p.speed_level = clampi(cfg.get_value("attack", "speed_level", 0), -p.MAX_SPEED_LEVELS, p.MAX_SPEED_LEVELS)
	if not mode in MODES:
		ErrorLog.warn("AutoFight: unknown target mode '%s' in %s, using 'mouse'" % [mode, SAVE_PATH])
		mode = "mouse"
	if not stance in STANCES:
		ErrorLog.warn("AutoFight: unknown style '%s' in %s, using 'single'" % [stance, SAVE_PATH])
		stance = "single"
	_ring = MeshInstance3D.new()
	var t = TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.15
	_ring.mesh = t
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.35, 0.2)
	m.no_depth_test = true
	_ring.material_override = m
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)


func save():
	var cfg = ConfigFile.new()
	cfg.set_value("auto", "on", on)
	cfg.set_value("auto", "mode", mode)
	cfg.set_value("auto", "stance", stance)
	cfg.set_value("attack", "speed_level", p.speed_level)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("AutoFight: couldn't save " + SAVE_PATH)


func toggle():
	on = not on
	save()
	p._float_text("Auto-attack ON" if on else "Auto-attack off", Color(1.0, 0.8, 0.4))
	if not on:
		_ring.visible = false


func next_mode():
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	save()
	p._float_text("Target: " + MODE_NAMES[mode], Color(1.0, 0.8, 0.4))


## Mouse wheel: pick the auto-attack style.
func set_stance(s: String):
	if not s in STANCES:
		ErrorLog.fail("AutoFight.set_stance: unknown style '%s'" % s)
		return
	if s == stance:
		return
	stance = s
	save()
	p._float_text(STANCE_NAMES[stance], Color(1.0, 0.8, 0.4))


func stance_name() -> String:
	return STANCE_NAMES[stance]


func mode_name() -> String:
	return MODE_NAMES[mode]


## Pick the main target from a list of enemies, by the chosen rule.
func pick(foes: Array):
	var best = null
	var best_score = -INF
	for e in foes:
		var score = 0.0
		var d = p.global_position.distance_to(e.global_position)
		match mode:
			"mouse":
				score = -Vector2(e.global_position.x - p.mouse_world_point.x, e.global_position.z - p.mouse_world_point.z).length()
			"closest":
				score = -d
			"strongest":
				score = _rank(e) * 1e6 + e.MAX_HEALTH - d * 0.01
			"weakest":
				score = -_rank(e) * 1e6 - e.MAX_HEALTH - d * 0.01
			"most_health":
				score = e.health - d * 0.01
			"least_health":
				score = -e.health - d * 0.01
		if score > best_score:
			best_score = score
			best = e
	return best


func _rank(e) -> int:
	return 4 if not e.rival.is_empty() else e.tier


## Enemies that are after you, alive, within reach.
func _foes(reach: float) -> Array:
	var out = []
	for e in Zones.all(p, "enemy"):
		if is_instance_valid(e) and e.aggroed and e.health > 0 and p.global_position.distance_to(e.global_position) <= reach:
			out.append(e)
	return out


## The sweep direction that catches the most enemies: [direction, how many].
func best_sweep(foes: Array) -> Array:
	var best_dir = Vector3.ZERO
	var best_n = 0
	var cone = p.aoe_cone - Traits.sweep_cone_shift()
	for aim in foes:
		var dir = aim.global_position - p.global_position
		dir.y = 0
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var n = 0
		for e in foes:
			var to_e = e.global_position - p.global_position
			to_e.y = 0
			if to_e.length() < 0.01 or dir.dot(to_e.normalized()) > cone:
				n += 1
		if n > best_n:
			best_n = n
			best_dir = dir
	return [best_dir, best_n]


## Called by the player every physics frame (not while a window is open or a mouse button is held).
func tick():
	if not on:
		_ring.visible = false
		target = null
		return
	var foes = _foes(max(p.ST_RANGE, p.AOE_RANGE))
	target = pick(foes)
	_ring.visible = target != null
	if target:
		_ring.global_position = Vector3(target.global_position.x, target.global_position.y - 1.0, target.global_position.z)
	if foes.is_empty():
		return
	if stance == "multi":
		var close = foes.filter(func(e): return p.global_position.distance_to(e.global_position) <= p.AOE_RANGE)
		if not close.is_empty():	# someone in sweep range: sweep (no single strikes meanwhile)
			if p.aoe_cooldown <= 0:
				p.aoe_attack(best_sweep(close)[0])
				p.aoe_cooldown = p.aoe_cooldown_time
			return
	if target and p.st_cooldown <= 0:
		p.single_target_attack(target)
		p.st_cooldown = p.st_cooldown_time
