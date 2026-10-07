extends Node3D
## Your pet (Fantasy "Sprite", Zombie "Scavenger", Sci-Fi "Harvest Drone"). It floats after you and
## gathers resource nodes near you into your satchel. It never fights.
## Enemies will go after it if it's the closest target. Protect it: if it's knocked out, it's gone
## for KNOCKOUT_TIME seconds, then comes back to you.
##
## Made by the local player (character_body_3d.gd). Follows you from zone to zone.
## Online: pets are your own. Joined players' pets aren't seen by the host's enemies yet.

const MAX_HEALTH = 80.0
const KNOCKOUT_TIME = 20.0		# seconds out after being knocked out
const SPEED = 9.0				# a bit faster than you, so it keeps up
const FOLLOW_DIST = 2.2			# hangs back this far when idle
const GATHER_RADIUS = 9.0		# gathers nodes this close to YOU
const LEASH = 14.0				# you walked this far away: drop the job and come back
const GATHER_TIME = 3.0			# slower than gathering yourself (1.5 s)
const REGEN_DELAY = 5.0			# heals after this long without being hit
const REGEN_RATE = 6.0			# health per second

var owner_player = null
var health := MAX_HEALTH
var knocked_out := 0.0			# > 0: knocked out, seconds until it's back
var target = null				# the resource node it's working on
var gather_left := 0.0
var _since_hit := 99.0
var _look_timer := 0.0
var _body: MeshInstance3D
var _label: Label3D
var _bar_bg: MeshInstance3D
var _bar: MeshInstance3D


func _ready():
	add_to_group("pet")
	_build_look()
	SkinManager.skin_changed.connect(_apply_skin)
	_apply_skin()


## The local player calls this right after making the pet.
func setup(p):
	owner_player = p
	Zones.entered.connect(_on_zone_entered)


func pet_name() -> String:
	return SkinManager.name_of("pet")


func alive() -> bool:
	return knocked_out <= 0.0


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
	_place_next_to_owner()


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
	if knocked_out > 0.0:
		knocked_out -= delta
		if knocked_out <= 0.0:
			_come_back()
		return
	_since_hit += delta
	if _since_hit > REGEN_DELAY and health < MAX_HEALTH:
		health = min(MAX_HEALTH, health + REGEN_RATE * delta)
		_update_bar()
	# Bob up and down a little
	_body.position.y = 0.15 * sin(Time.get_ticks_msec() / 300.0)

	var me = owner_player.global_position
	if _flat(global_position - me).length() > 30.0:	# lost (respawn, portal): pop back next to you
		_place_next_to_owner()
		target = null

	# Drop the job if the node is gone, or you walked off
	if target != null and (not is_instance_valid(target) or _flat(target.global_position - me).length() > LEASH):
		_stop_gathering()

	# Look for a job a few times a second
	_look_timer -= delta
	if target == null and _look_timer <= 0.0:
		_look_timer = 0.4
		target = _pick_node()
		gather_left = GATHER_TIME

	if target != null:
		var spot = target.global_position
		if _move_toward(spot, delta, 0.9):
			_gather(delta)
	else:
		_move_toward(me, delta, FOLLOW_DIST)


## Fly toward a spot (ignores walls: it floats). True once within `stop` of it.
func _move_toward(spot: Vector3, delta: float, stop: float) -> bool:
	var to = _flat(spot - global_position)
	var d = to.length()
	if d <= stop:
		return true
	var step = min(d - stop, SPEED * delta * (1.6 if d > 8.0 else 1.0))
	global_position += to / d * step
	global_position.y = lerp(global_position.y, spot.y + 1.0, min(1.0, delta * 4.0))
	if d > 0.05:
		look_at(global_position + to, Vector3.UP)
	return d - step <= stop


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# ---------------- Gathering ----------------

## The closest resource node near YOU that you're not gathering yourself.
func _pick_node():
	if GameState.satchel_count() >= GameState.satchel_capacity():
		return null
	var me = owner_player.global_position
	var best = null
	var best_d = INF
	for n in Zones.all(owner_player, "resource_node"):
		if n == owner_player.gather_node:
			continue
		var d = _flat(n.global_position - me).length()
		if d <= GATHER_RADIUS * Traits.sight_mult() and d < best_d:	# Wanderer: spots nodes farther out
			best = n
			best_d = d
	return best


func _gather(delta):
	gather_left -= delta
	_label.text = "%s: gathering%s" % [pet_name(), ".".repeat(int((GATHER_TIME - gather_left) * 2) % 4)]
	_label.modulate = Color(1, 1, 1)
	_label.visible = true
	if gather_left > 0.0:
		return
	var n = target
	target = null
	_label.visible = health < MAX_HEALTH
	_update_bar()
	if not is_instance_valid(n):
		return
	if not GameState.add_resource(n.type, n.quality):
		_say("Satchel full!", Color(1, 0.6, 0.4))
		return
	_say("+1 " + GameState.resource_name(n.type, n.quality), GameState.RESOURCE_INFO[n.type].color.lightened(0.3))
	n.queue_free()


func _stop_gathering():
	target = null
	_update_bar()


# ---------------- Getting hurt ----------------

## Enemies call this (same as hitting a player).
func take_damage(amount, _source = null):
	if not alive():
		return
	health -= amount * Traits.pet_guard_mult()	# Kin: you look after it
	_since_hit = 0.0
	if target != null:
		_stop_gathering()	# getting hit interrupts gathering (like it does for you)
	_flash()
	_update_bar()
	if health <= 0.0:
		_knock_out()


func _knock_out():
	health = 0.0
	knocked_out = KNOCKOUT_TIME
	target = null
	visible = false
	GameState.notify("Your %s was knocked out! It'll be back in %d seconds." % [pet_name(), int(KNOCKOUT_TIME)])


func _come_back():
	health = MAX_HEALTH
	visible = true
	_place_next_to_owner()
	_update_bar()
	_say(pet_name() + " is back!", Color(0.6, 1, 0.6))


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


func _apply_skin():
	_body.material_override = SkinManager.material("pet", Color(0.55, 0.9, 1.0))
	for ear in _body.get_children():
		ear.material_override = _body.material_override


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
