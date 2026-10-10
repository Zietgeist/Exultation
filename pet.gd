extends Node3D
## Your pet (Fantasy "Sprite", Zombie "Scavenger", Sci-Fi "Harvest Drone"). It floats after you and
## gathers resource nodes near you into your satchel. It never fights.
## Enemies will go after it if it's the closest target. Protect it: if it's knocked out, it's gone
## for KNOCKOUT_TIME seconds, then comes back to you.
##
## It GROWS from how you treat it (ideas from how babies and young animals handle stress):
##   Stress     goes up when it's hit or enemies are close; comes down with calm time, much faster
##              when you're near (it calms down with you, like a child with a parent).
##   Overwhelm  hits that stack up before it calms down push it over its limit ("trigger stacking"):
##              it hides behind you and stops gathering until it settles.
##   Sturdy     hard knocks it gets through WITH you near make it tougher, but slower.
##   Skittish   being overwhelmed again and again (worst when you're far away) lowers its limit.
##              Calm time with you heals it. Never permanent.
##   Bond       feeding it (T near it: one herb from your satchel), resting at Home together and
##              protecting it. A secure pet explores farther: high Bond = faster, gathers from
##              farther and quicker, and at 80+ gathers TWO nodes at once.
##   Tonics     refined herbs (from the Chemist) are a real treat: fully fed and calm, a big Bond boost,
##              less skittish, healed, and WELL FED for a while (faster, gathers quicker, +20% health).
##   Name       give it one in the Chronicle (J) or the pet window (K). Its milestones go in the Chronicle.
##
## Safety: it won't go for a node if an enemy you can see is close enough to notice it there,
## and it drops the job and comes back if one wanders close. (Enemies that pop up out of nowhere
## can still surprise it.)
##
## Made by the local player (character_body_3d.gd). Follows you from zone to zone. Saved in user://pet.cfg.
## Online: every player's pet is shown to the others (pet_ghost.gd). The host runs the enemies, so on the
## host a friend's pet can be targeted; the hit is sent to the friend's game, where the real pet takes it.

var SAVE_PATH: String:	# this character's save (Account)
	get:
		return Account.path("pet.cfg")
const BASE_HEALTH = 80.0
const KNOCKOUT_TIME = 20.0		# seconds out after being knocked out
const BASE_SPEED = 9.0			# a bit faster than you, so it keeps up
const FOLLOW_DIST = 2.2			# hangs back this far when idle
const GATHER_RADIUS = 9.0		# gathers nodes this close to YOU
const LEASH = 14.0				# you walked this far away: drop the job and come back
const GATHER_TIME = 3.0			# slower than gathering yourself (1.5 s)
const REGEN_DELAY = 5.0			# heals after this long without being hit
const REGEN_RATE = 6.0			# health per second
const NEAR_YOU = 5.0			# "you're close": it calms down much faster
const FEED_RANGE = 4.0
const FEED_COOLDOWN = 120.0		# a proper meal every 2 minutes; more is just a snack
const DANGER_MARGIN = 1.15		# keeps a little more than an enemy's aggro range away from it

# Grows over time (saved)
var pet_name_given := ""
var bond := 20.0			# 0..100
var sturdy := 0.0			# 0..100 (0 = nimble, 100 = tough and slow)
var skittish := 0.0			# 0..100 (lowers its overwhelm limit)
var hunger := 0.0			# 0..100 (goes up while you play; feeding brings it down)
var record := {gathered = 0, knockouts = 0, overwhelmed = 0, guarded = 0, fed = 0, since = ""}
var milestones := {}

# Right now
var owner_player = null
var MAX_HEALTH := BASE_HEALTH
var health := BASE_HEALTH
var stress := 0.0				# 0..100
var overwhelmed := false
var knocked_out := 0.0			# > 0: knocked out, seconds until it's back
var target = null				# the resource node it's working on
var target2 = null				# high Bond: a second node gathered at the same time
var gather_left := 0.0
var _since_hit := 99.0
var _since_fed := 999.0
var well_fed := 0.0			# seconds left of a tonic's boost
var _peak_stress := 0.0		# for "got through it with you"
var _look_timer := 0.0
var _save_t := 0.0
var _hint_t := 10.0
var _body: MeshInstance3D
var _label: Label3D
var _bar_bg: MeshInstance3D
var _bar: MeshInstance3D


func _ready():
	add_to_group("pet")
	_load()
	_build_look()
	SkinManager.skin_changed.connect(_apply_skin)
	_apply_skin()
	_refresh_stats()
	health = MAX_HEALTH


## The local player calls this right after making the pet.
func setup(p):
	owner_player = p
	Zones.entered.connect(_on_zone_entered)
	SessionManager.break_started.connect(_on_rest)


func pet_name() -> String:
	return pet_name_given if pet_name_given != "" else SkinManager.name_of("pet")


## "Pip the Sprite" once it has a name.
func full_name() -> String:
	return SkinManager.name_of("pet") if pet_name_given == "" else "%s the %s" % [pet_name_given, SkinManager.name_of("pet")]


func set_pet_name(n: String):
	n = n.strip_edges().substr(0, 20)
	if n == "" or n == pet_name_given:
		return
	var first = pet_name_given == ""
	pet_name_given = n
	_save()
	Story.add(("You named your %s %s." if first else "Your %s goes by %s now.") % [SkinManager.name_of("pet"), n])


## Enemies only notice it while it's out gathering (beside you it stays out of the fight).
func draws_aggro() -> bool:
	return target != null


func alive() -> bool:
	return knocked_out <= 0.0


# ---------------- Growth ----------------

## Health, speed and gathering follow Sturdy and Bond.
func _refresh_stats():
	var old = MAX_HEALTH
	MAX_HEALTH = BASE_HEALTH * (1.0 + sturdy / 100.0) * (1.2 if well_fed > 0.0 else 1.0)	# up to double; tonics +20%
	health = clamp(health + (MAX_HEALTH - old), 0.0, MAX_HEALTH)


func speed() -> float:
	return BASE_SPEED * (1.0 - 0.25 * sturdy / 100.0) * (1.0 + 0.35 * bond / 100.0) * (1.25 if well_fed > 0.0 else 1.0)

func gather_time() -> float:
	return GATHER_TIME * (1.0 + 0.2 * sturdy / 100.0) * (1.0 - 0.3 * bond / 100.0) * (0.75 if well_fed > 0.0 else 1.0)

func gather_radius() -> float:
	return GATHER_RADIUS * (1.0 + 0.3 * bond / 100.0) * Traits.sight_mult()	# Wanderer: spots nodes farther out

func double_gather() -> bool:
	return bond >= 80.0

## Its limit before it's overwhelmed (skittish pets get overwhelmed sooner).
func threshold() -> float:
	return 85.0 - 0.4 * skittish


func mood() -> String:
	if not alive():
		return "knocked out"
	if overwhelmed:
		return "overwhelmed"
	if stress > 50.0:
		return "nervous"
	if hunger > 70.0:
		return "hungry"
	if bond >= 80.0:
		return "devoted"
	if bond >= 50.0:
		return "happy"
	return "content"


func _grow_bond(amount: float, why := ""):
	var before = bond
	bond = clamp(bond + amount * (1.0 + Traits.right("bond") * 0.5), 0.0, 100.0)	# Kin: bonds faster
	if before < 50.0 and bond >= 50.0:
		_milestone("bond50", "%s trusts you now." % full_name())
	if before < 80.0 and bond >= 80.0:
		_milestone("bond80", "%s is devoted to you. It can gather two things at once." % full_name())
	if why != "":
		_say(why, Color(0.7, 1.0, 0.7))


func _milestone(id: String, text: String):
	if milestones.has(id):
		return
	milestones[id] = true
	Story.add(text)
	_save()


# ---------------- Moving between zones ----------------

## You went through a door: the pet comes along (unless it's knocked out; then it waits for you there).
func _on_zone_entered(z):
	if z == null or z.root == null:
		ErrorLog.fail("Pet: entered a zone with no scene root")
		return
	if get_parent():
		get_parent().remove_child(self)
	z.root.add_child(self)
	target = null
	target2 = null
	_place_next_to_owner()


## Resting at Home together: calm, and closer.
func _on_rest(_blocks):
	if not alive():
		return
	stress = 0.0
	overwhelmed = false
	skittish = max(0.0, skittish - 5.0)
	_grow_bond(3.0)
	_save()


func _place_next_to_owner():
	if not _owner_ok():
		return
	var a = randf() * TAU
	global_position = owner_player.global_position + Vector3(cos(a), 0, sin(a)) * FOLLOW_DIST + Vector3(0, 0.6, 0)


func _owner_ok() -> bool:
	return owner_player != null and is_instance_valid(owner_player) and owner_player.is_inside_tree() and is_inside_tree()


# ---------------- Every frame ----------------

func _process(delta):
	if not _owner_ok():
		return
	_save_t += delta
	if _save_t > 20.0:
		_save_t = 0.0
		_save()
	_since_fed += delta
	if well_fed > 0.0:
		well_fed -= delta
		if well_fed <= 0.0:
			well_fed = 0.0
			_refresh_stats()
	_hint_t -= delta
	if _hint_t <= 0.0:
		_hint_t = 20.0
		if hunger > 70.0 and alive() and target == null:
			_say("hungry... (T to share a herb)", Color(1.0, 0.85, 0.5))
	if GameState.current_zone != "Home":
		hunger = min(100.0, hunger + delta * 100.0 / (25.0 * 60.0))	# hungry after about one flow block
	if hunger >= 100.0:
		bond = max(0.0, bond - delta * 0.01)	# a hungry pet slowly drifts away
	if knocked_out > 0.0:
		knocked_out -= delta
		if knocked_out <= 0.0:
			_come_back()
		return
	var me = owner_player.global_position
	var near_you = _flat(global_position - me).length() <= NEAR_YOU
	_tick_stress(delta, near_you)
	_since_hit += delta
	if _since_hit > REGEN_DELAY and health < MAX_HEALTH and stress < 40.0:
		health = min(MAX_HEALTH, health + REGEN_RATE * delta)
		_update_bar()
	# Bob up and down a little (shakes when overwhelmed)
	_body.position.y = 0.15 * sin(Time.get_ticks_msec() / 300.0)
	_body.position.x = randf_range(-0.05, 0.05) if overwhelmed else 0.0

	if _flat(global_position - me).length() > 30.0:	# lost (respawn, portal): pop back next to you
		_place_next_to_owner()
		_stop_gathering()

	if overwhelmed:	# hide behind you, away from the nearest enemy
		_stop_gathering()
		_move_toward(_hiding_spot(), delta, 0.3)
		return

	# Drop the job if the node is gone, or you walked off
	if target != null and (not is_instance_valid(target) or _flat(target.global_position - me).length() > LEASH):
		_stop_gathering()
	# ...or an enemy came close enough to notice it
	_danger_t -= delta
	if target != null and _danger_t <= 0.0:
		_danger_t = 0.25
		if _danger_near(target.global_position) or _danger_near(global_position):
			_stop_gathering()
			_say("enemies near... coming back", Color(1.0, 0.8, 0.5))

	# Look for a job a few times a second
	_look_timer -= delta
	if target == null and _look_timer <= 0.0:
		_look_timer = 0.4
		target = _pick_node()
		target2 = _pick_second(target) if target and double_gather() else null
		gather_left = gather_time()

	if target != null:
		var spot = target.global_position
		if target2 and is_instance_valid(target2):
			spot = (spot + target2.global_position) / 2.0	# between the two
		if _move_toward(spot, delta, 0.9 if target2 == null else 1.6):
			_gather(delta)
	else:
		_move_toward(me, delta, FOLLOW_DIST)


## Stress: enemies close by add to it; calm time takes it away (much faster near you).
func _tick_stress(delta: float, near_you: bool):
	var threat = false
	for e in Zones.all(self, "enemy"):
		if e.aggroed and e.global_position.distance_to(global_position) < 6.0:
			threat = true
			break
	if threat:
		stress = min(100.0, stress + 3.0 * delta)
	else:
		stress = max(0.0, stress - (8.0 if near_you else 2.0) * delta)	# co-regulation
	_peak_stress = max(_peak_stress, stress)
	# Got through a scare with you close: tougher
	if _peak_stress >= 50.0 and stress < 20.0:
		if near_you:
			sturdy = min(100.0, sturdy + 3.0)
			_refresh_stats()
			if sturdy >= 50.0:
				_milestone("sturdy50", "%s has grown tough from the fights it got through beside you." % full_name())
		_peak_stress = stress
	if overwhelmed and stress < 30.0:
		overwhelmed = false
		_say("calmer now", Color(0.7, 0.9, 1.0))
	# Calm time with you slowly heals skittishness
	if not threat and near_you and stress < 10.0:
		skittish = max(0.0, skittish - delta / 30.0)


func _hiding_spot() -> Vector3:
	var me = owner_player.global_position
	var nearest = null
	var best = INF
	for e in Zones.all(self, "enemy"):
		var d = e.global_position.distance_to(me)
		if d < best:
			best = d
			nearest = e
	if nearest == null:
		return me
	var away = _flat(me - nearest.global_position).normalized()
	return me + away * 1.3


## Fly toward a spot (ignores walls: it floats). True once within `stop` of it.
func _move_toward(spot: Vector3, delta: float, stop: float) -> bool:
	var to = _flat(spot - global_position)
	var d = to.length()
	if d <= stop:
		return true
	var step = min(d - stop, speed() * delta * (1.6 if d > 8.0 else 1.0))
	global_position += to / d * step
	global_position.y = lerp(global_position.y, spot.y + 1.0, min(1.0, delta * 4.0))
	if d > 0.05:
		look_at(global_position + to, Vector3.UP)
	return d - step <= stop


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# ---------------- Feeding (T) ----------------

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T and not GameState.ui_open:
		if _owner_ok() and alive() and _flat(global_position - owner_player.global_position).length() <= FEED_RANGE:
			feed()
			get_viewport().set_input_as_handled()


## One herb from your satchel.
func feed():
	var key = ""
	for k in GameState.satchel:
		if k.begins_with("herb:") and GameState.satchel[k] > 0:
			key = k
			break
	if key == "":
		if best_tonic() >= 0:	# no raw herbs: a tonic will do
			feed_tonic()
		else:
			_say("no herbs or tonics to share", Color(0.9, 0.8, 0.6))
		return
	GameState.satchel[key] -= 1
	if GameState.satchel[key] <= 0:
		GameState.satchel.erase(key)
	GameState.save_progress()
	record.fed += 1
	hunger = max(0.0, hunger - 60.0)
	stress = max(0.0, stress - 30.0)
	if _since_fed >= FEED_COOLDOWN:
		_since_fed = 0.0
		_grow_bond(5.0, "yum!")
	else:
		_grow_bond(0.5, "a little snack")
	if record.fed == 1:
		_milestone("fed", "Shared a %s with %s for the first time." % [GameState.resource_name("herb", int(key.get_slice(":", 1))), full_name()])
	_save()


## Your best tonic's quality (-1 = none).
func best_tonic() -> int:
	var best = -1
	for k in Crafting.stash:
		if k.begins_with("tonic:") and Crafting.stash[k] > 0:
			best = max(best, int(k.get_slice(":", 1)))
	return best


## A refined herb: much better than a raw one. Better tonics keep it well fed longer.
func feed_tonic() -> bool:
	var q = best_tonic()
	if q < 0:
		_say("no tonics (refine herbs at the Chemist)", Color(0.9, 0.8, 0.6))
		return false
	Crafting._take("tonic", q, 1)
	Crafting.save()
	record.fed += 1
	hunger = 0.0
	stress = 0.0
	if overwhelmed:
		overwhelmed = false
	skittish = max(0.0, skittish - 5.0)
	well_fed = 180.0 + 60.0 * q	# 3 minutes, +1 per quality
	_refresh_stats()
	health = MAX_HEALTH
	_update_bar()
	if _since_fed >= FEED_COOLDOWN:
		_since_fed = 0.0
		_grow_bond(8.0, "delicious! (well fed)")
	else:
		_grow_bond(2.0, "a tasty treat! (well fed)")
	_milestone("tonic", "Gave %s a %s. It's never been happier." % [full_name(), Crafting.material_name("tonic", q)])
	_save()
	return true


# ---------------- Gathering ----------------

## The closest resource node near YOU that you're not gathering yourself,
## and that no enemy you can see is close enough to notice it at (there or on the way).
func _pick_node():
	if GameState.satchel_count() >= GameState.satchel_capacity():
		return null
	var me = owner_player.global_position
	var best = null
	var best_d = INF
	var skipped = false
	for n in Zones.all(owner_player, "resource_node"):
		if n == owner_player.gather_node:
			continue
		var d = _flat(n.global_position - me).length()
		if d <= gather_radius() and d < best_d:
			if _danger_near(n.global_position) or _danger_near((n.global_position + me) / 2.0):
				skipped = true
				continue
			best = n
			best_d = d
	if best == null and skipped:
		_wary_t -= 0.4
		if _wary_t <= 0.0:
			_wary_t = 8.0
			_say("an enemy is close to that one", Color(1.0, 0.8, 0.5))
	return best


var _danger_t := 0.0
var _wary_t := 0.0

## Would an enemy (one you can see) notice the pet at this spot?
func _danger_near(spot: Vector3) -> bool:
	for e in Zones.all(owner_player, "enemy"):
		if not is_instance_valid(e) or e.health <= 0:
			continue
		if _flat(e.global_position - spot).length() <= e.AGGRO_RANGE * DANGER_MARGIN + 1.0:
			return true
	return false


## 0..100: how full it is (the food bar).
func food() -> float:
	return 100.0 - hunger


## Devoted pets: another node close to the first.
func _pick_second(first):
	if GameState.satchel_count() + 2 > GameState.satchel_capacity():
		return null
	for n in Zones.all(owner_player, "resource_node"):
		if n != first and n != owner_player.gather_node and n.global_position.distance_to(first.global_position) <= 5.0:
			return n
	return null


func _gather(delta):
	gather_left -= delta
	var gt = gather_time()
	_label.text = "%s: gathering%s%s" % [pet_name(), " two" if target2 else "", ".".repeat(int((gt - gather_left) * 2) % 4)]
	_label.modulate = Color(1, 1, 1)
	_label.visible = true
	if gather_left > 0.0:
		return
	var got = []
	for n in [target, target2]:
		if n == null or not is_instance_valid(n):
			continue
		if not GameState.add_resource(n.type, n.quality):
			_say("Satchel full!", Color(1, 0.6, 0.4))
			break
		got.append(GameState.resource_name(n.type, n.quality))
		n.queue_free()
		record.gathered += 1
	if got.size() == 2:
		_milestone("double", "%s gathered two things at once for the first time." % full_name())
	if record.gathered >= 100:
		_milestone("gathered100", "%s has gathered 100 things for you." % full_name())
	target = null
	target2 = null
	_label.visible = health < MAX_HEALTH
	_update_bar()
	if got.size() > 0:
		_say("+" + " +".join(got), Color(0.8, 1.0, 0.6))


func _stop_gathering():
	target = null
	target2 = null
	_update_bar()


# ---------------- Getting hurt ----------------

## Enemies call this (same as hitting a player).
func take_damage(amount, _source = null):
	if not alive():
		return
	health -= amount * Traits.pet_guard_mult()	# Kin: you look after it
	_since_hit = 0.0
	# Hits stack: the less time it's had to calm down, the more each one adds
	stress = min(100.0, stress + 15.0 + 0.2 * stress)
	sturdy = min(100.0, sturdy + 0.3)	# gets hit a lot: grows tougher (and slower)
	_peak_stress = max(_peak_stress, stress)
	if not overwhelmed and stress >= threshold():
		overwhelmed = true
		record.overwhelmed += 1
		var far = owner_player and _flat(global_position - owner_player.global_position).length() > NEAR_YOU
		skittish = min(100.0, skittish + (8.0 if far else 4.0))
		_say("overwhelmed!", Color(1.0, 0.6, 0.4))
	if target != null:
		_stop_gathering()	# getting hit interrupts gathering (like it does for you)
	_flash()
	_update_bar()
	if health <= 0.0:
		_knock_out()


## You took down something that was going after it (enemy.gd calls Traits.on_guarded_pet too).
func guarded():
	record.guarded += 1
	stress = max(0.0, stress - 10.0)
	_grow_bond(1.0)


func _knock_out():
	health = 0.0
	knocked_out = KNOCKOUT_TIME
	target = null
	target2 = null
	visible = false
	overwhelmed = false
	stress = 0.0
	skittish = min(100.0, skittish + 6.0)
	record.knockouts += 1
	GameState.notify("%s was knocked out! It'll be back in %d seconds." % [full_name(), int(KNOCKOUT_TIME)])
	if record.knockouts == 1:
		_milestone("ko1", "%s was knocked out for the first time." % full_name())
	_save()


func _come_back():
	health = MAX_HEALTH
	visible = true
	_place_next_to_owner()
	_update_bar()
	_say(pet_name() + " is back!", Color(0.6, 1, 0.6))


# ---------------- Saving ----------------

func _load():
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		record.since = Time.get_date_string_from_system()
		return
	pet_name_given = cfg.get_value("pet", "name", "")
	bond = cfg.get_value("pet", "bond", 20.0)
	sturdy = cfg.get_value("pet", "sturdy", 0.0)
	skittish = cfg.get_value("pet", "skittish", 0.0)
	hunger = cfg.get_value("pet", "hunger", 0.0)
	record.merge(cfg.get_value("pet", "record", {}), true)
	milestones = cfg.get_value("pet", "milestones", {})


func _save():
	var cfg = ConfigFile.new()
	cfg.set_value("pet", "name", pet_name_given)
	cfg.set_value("pet", "bond", bond)
	cfg.set_value("pet", "sturdy", sturdy)
	cfg.set_value("pet", "skittish", skittish)
	cfg.set_value("pet", "hunger", hunger)
	cfg.set_value("pet", "record", record)
	cfg.set_value("pet", "milestones", milestones)
	if cfg.save(SAVE_PATH) != OK:
		ErrorLog.fail("Pet: couldn't save " + SAVE_PATH)


func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()


# ---------------- Looks ----------------

func _build_look():
	_body = MeshInstance3D.new()
	var s = SphereMesh.new()
	s.radius = 0.42
	s.height = 0.84
	_body.mesh = s
	add_child(_body)
	for side in [-1, 1]:	# two little ears / antennae, so it reads as a creature
		var ear = MeshInstance3D.new()
		var p = PrismMesh.new()
		p.size = Vector3(0.14, 0.26, 0.1)
		ear.mesh = p
		ear.position = Vector3(0.2 * side, 0.44, 0)
		_body.add_child(ear)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 1.1
	_label.font_size = 32
	_label.pixel_size = 0.011
	_label.outline_size = 8
	_label.no_depth_test = true
	_label.visible = false
	add_child(_label)
	# Health bar (only shows when hurt)
	_bar_bg = _bar_mesh(Color(0.15, 0.15, 0.15))
	_bar = _bar_mesh(Color(0.3, 1.0, 0.4))
	_bar.position.z = -0.01


func _bar_mesh(c: Color) -> MeshInstance3D:
	var m = MeshInstance3D.new()
	var q = QuadMesh.new()
	q.size = Vector2(0.8, 0.09)
	m.mesh = q
	var mat = StandardMaterial3D.new()
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	m.material_override = mat
	m.position.y = 0.8
	m.visible = false
	add_child(m)
	return m


## Sturdy pets look a bit bigger.
func _apply_skin():
	_body.material_override = SkinManager.material("pet", Color(0.55, 0.9, 1.0))
	for ear in _body.get_children():
		ear.material_override = _body.material_override
	_body.scale = Vector3.ONE * (1.0 + 0.35 * sturdy / 100.0)


func _update_bar():
	var hurt = health < MAX_HEALTH and alive()
	_bar_bg.visible = hurt
	_bar.visible = hurt
	var f = clamp(health / MAX_HEALTH, 0.0, 1.0)
	_bar.mesh.size.x = 0.8 * max(f, 0.01)
	if target == null:
		_label.visible = false


func _flash():
	_body.material_override = SkinManager.material("hit_flash", Color(1, 1, 1))
	var t = create_tween()
	t.tween_interval(0.08)
	t.tween_callback(_apply_skin)


func _say(text: String, color: Color):
	_label.text = text
	_label.modulate = color
	_label.visible = true
	var t = create_tween()
	t.tween_interval(1.2)
	t.tween_callback(func(): _label.visible = target != null)
