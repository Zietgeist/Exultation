extends Node
## Autoload "Net": online co-op for 2-4 players.
##
## One player HOSTS. The host's game runs the world: enemies, kills, boss unlocks, the zone layout.
## Others JOIN. They see copies ("mirrors") of the host's enemies; their hits, roots and heals are
## sent to whoever owns the target. Each player moves their own character and keeps their own
## loot, gold, gear and skill ranks. The party travels together: the host leads through gates.
## Solo play never touches the network.
##
## Today the connection is direct (ENet): same PC (127.0.0.1), home network, or over the internet
## if the host forwards PORT on their router. Later the peer can be swapped for Steam (GodotSteam);
## everything else in this file stays the same.
##
## Testing on one PC: Godot > Debug > Customize Run Instances: 2 instances,
## arguments "--host" for one and "--join" for the other (add "--class=healer" to skip the class pick).

const PORT = 24565
const MAX_PLAYERS = 4
const STATE_RATE = 0.05		# my position to the others, 20 times a second
const SNAPSHOT_RATE = 0.1	# host: enemies to the others, 10 times a second
const MIRROR_MISSES = 4		# client: an enemy missing from this many snapshots fell asleep (or left)
const COLORS = [Color(1, 0.49, 1), Color(0.3, 0.8, 1), Color(1, 0.6, 0.2), Color(0.5, 1, 0.4)]
const NOT_ZONES = ["res://ClassSelect.tscn", ""]

signal status(text)		# connection messages for the start screen

var mode := "solo"		# solo, host, client
var players := {}		# host: peer id -> {class_id}  (everyone, me included)
var puppets := {}		# peer id -> that player's stand-in in my current zone
var enemies := {}		# host: net id -> enemy
var mirrors := {}		# client: net id -> mirror enemy
var _misses := {}		# client: net id -> snapshots in a row without it
var _next_enemy_id := 1
var _zone := ""			# host: zone the party is in (already sent)
var _zone_wait := 0.0
var _state_t := 0.0
var _snap_t := 0.0
var allow_travel := false	# client: true while the host is moving the party


func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Couldn't connect to the host."))
	multiplayer.server_disconnected.connect(func(): _fail("The host left the game."))


func is_online() -> bool:
	return mode != "solo"

func is_host() -> bool:
	return mode == "host"

func is_client() -> bool:
	return mode == "client"

func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


# ---------------- Start / stop ----------------

func host() -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		ErrorLog.fail("Couldn't host on port %d (error %d). Is another copy already hosting?" % [PORT, err])
		return false
	multiplayer.multiplayer_peer = peer
	mode = "host"
	players = {1: _my_info()}
	get_window().title = "Exultation - Host"
	print("Hosting on port ", PORT)
	return true


func join(ip: String) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip if ip != "" else "127.0.0.1", PORT)
	if err != OK:
		ErrorLog.fail("Couldn't start joining %s (error %d)" % [ip, err])
		return false
	multiplayer.multiplayer_peer = peer
	mode = "client"
	get_window().title = "Exultation - Joined"
	status.emit("Connecting to %s ..." % ip)
	return true


func leave():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "solo"
	players.clear()
	puppets.clear()
	mirrors.clear()
	enemies.clear()


func _fail(text: String):
	ErrorLog.warn(text)
	GameState.notify(text)
	status.emit(text)
	leave()
	get_tree().change_scene_to_file.call_deferred("res://ClassSelect.tscn")


func _my_info() -> Dictionary:
	return {class_id = GameState.player_class}


## Each player gets their own color (the host is always pink).
func color_of(id: int) -> Color:
	return COLORS[0] if id == 1 else COLORS[1 + id % (COLORS.size() - 1)]


func _on_connected():
	status.emit("Connected! Waiting for the host...")
	_register.rpc_id(1, _my_info())


func _on_peer_connected(id: int):
	print("Peer connected: ", id)


func _on_peer_disconnected(id: int):
	players.erase(id)
	if puppets.has(id) and is_instance_valid(puppets[id]):
		puppets[id].queue_free()
	puppets.erase(id)
	GameState.notify("A player left the party")


@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary):
	var id = multiplayer.get_remote_sender_id()
	players[id] = info
	GameState.notify("%s joined the party!" % Classes.label(info.class_id))
	if _zone != "":
		_send_zone(id)


# ---------------- Every frame ----------------

func _process(delta):
	if not is_online():
		return
	var scene = get_tree().current_scene
	var path = scene.scene_file_path if scene else ""

	# Host: when I change zone, bring the party along (once the zone has built itself)
	if is_host() and path != _zone and not path in NOT_ZONES:
		_zone_wait += delta
		if _zone_wait > 0.4:
			_zone_wait = 0.0
			_zone = path
			_send_zone(0)

	_state_t -= delta
	if _state_t <= 0.0 and not path in NOT_ZONES:
		_state_t = STATE_RATE
		var me = get_tree().get_first_node_in_group("player")
		if me:
			_player_state.rpc(path, me.global_position, me.rotation.y, me.health, me.MAX_HEALTH, me.player_class)

	if is_host():
		_snap_t -= delta
		if _snap_t <= 0.0 and puppets.size() > 0:
			_snap_t = SNAPSHOT_RATE
			_send_snapshot(path)


# ---------------- Zones: the party travels together ----------------

func _send_zone(to: int):
	var layout = {}
	var parts = {"terrain": "zone_terrain", "obstacles": "zone_obstacles"}
	for part in parts:
		var node = get_tree().get_first_node_in_group(parts[part])
		if node:
			layout[part] = node.save_state()
	var me = get_tree().get_first_node_in_group("player")
	var spot = me.global_position if me else Vector3.ZERO
	if to == 0:
		_go_to_zone.rpc(_zone, layout, GameState.unlocked_zones, spot)
	else:
		_go_to_zone.rpc_id(to, _zone, layout, GameState.unlocked_zones, spot)


@rpc("authority", "call_remote", "reliable")
func _go_to_zone(path: String, layout: Dictionary, unlocked: Array, host_spot: Vector3):
	print("Host is taking the party to ", path)
	GameState.unlocked_zones = unlocked.duplicate()
	var memory = GameState.zone_memory.get(path, {})
	memory.erase("spawner")
	for part in layout:
		memory[part] = layout[part]
	GameState.zone_memory[path] = memory
	GameState.previous_scene = get_tree().current_scene.scene_file_path if get_tree().current_scene else ""
	GameState.pending_spawn = host_spot + Vector3(randf_range(-2, 2), 0, randf_range(2, 3))
	for id in puppets:
		if is_instance_valid(puppets[id]):
			puppets[id].queue_free()
	puppets.clear()
	mirrors.clear()
	_misses.clear()
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	get_tree().change_scene_to_file.call_deferred(path)


# ---------------- Players ----------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _player_state(zone: String, pos: Vector3, rot: float, hp: float, max_hp: float, class_id: String):
	var id = multiplayer.get_remote_sender_id()
	var scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != zone:
		if puppets.has(id) and is_instance_valid(puppets[id]):	# they left my zone
			puppets[id].queue_free()
			puppets.erase(id)
		return
	var p = puppets.get(id)
	if p == null or not is_instance_valid(p):
		p = load("res://Player.tscn").instantiate()
		p.is_puppet = true
		p.peer_id = id
		p.player_class = class_id
		p.puppet_color = color_of(id)
		p.name = "Remote_%d" % id
		scene.add_child(p)
		p.global_position = pos
		puppets[id] = p
	p.net_state(pos, rot, hp, max_hp)


## Something hurt / healed / blessed another player's stand-in: tell that player.
func hurt_player(id: int, amount: float, enemy):
	_hurt.rpc_id(id, amount, enemy.net_id if enemy and "net_id" in enemy else 0)

func heal_player(id: int, amount: float):
	_heal.rpc_id(id, amount)

func vow_player(id: int, vow: Dictionary):
	_vow.rpc_id(id, vow)


@rpc("any_peer", "call_remote", "reliable")
func _hurt(amount: float, enemy_id: int):
	var me = get_tree().get_first_node_in_group("player")
	if me:
		me.take_damage(amount, mirrors.get(enemy_id))

@rpc("any_peer", "call_remote", "reliable")
func _heal(amount: float):
	var me = get_tree().get_first_node_in_group("player")
	if me:
		me.heal(amount)

@rpc("any_peer", "call_remote", "reliable")
func _vow(vow: Dictionary):
	var me = get_tree().get_first_node_in_group("player")
	if me:
		me.receive_vow(vow)


# ---------------- Enemies (host runs them, clients mirror them) ----------------

func register_enemy(e) -> int:
	var id = _next_enemy_id
	_next_enemy_id += 1
	enemies[id] = e
	return id


const SNAPSHOT_RADIUS = 45.0	# each player only gets the enemies near them

func _send_snapshot(zone: String):
	for id in enemies.keys():
		var e = enemies[id]
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			enemies.erase(id)
	var sp = get_tree().get_first_node_in_group("zone_spawner")
	var counts = PackedInt32Array()
	if sp:
		counts = PackedInt32Array([sp.total_killed, sp.trash_killed, sp.thugs_killed, sp.masters_killed, sp.bosses_killed, sp.min_clear, sp.target_total])
	for peer in puppets:	# only players who are in this zone with me
		var who = puppets[peer]
		if not is_instance_valid(who):
			continue
		var c = who.global_position
		var data = PackedFloat32Array()
		for id in enemies:
			var e = enemies[id]
			var p = e.global_position
			if Vector2(p.x - c.x, p.z - c.z).length() > SNAPSHOT_RADIUS:
				continue
			data.append_array([id, e.tier, Crafting.ELEMENTS.find(e.damage_type), p.x, p.y, p.z, e.health, e.MAX_HEALTH, 1.0 if e.aggroed else 0.0])
			if data.size() >= FIELDS * PER_PACKET:	# keep each message small enough for one network packet
				_snapshot.rpc_id(peer, zone, counts, data, false)
				data = PackedFloat32Array()
		_snapshot.rpc_id(peer, zone, counts, data, true)


const FIELDS = 9
const PER_PACKET = 30	# enemies per message (30 x 36 bytes fits in one packet)
var _seen := {}		# client: enemies seen in this round of messages

@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(zone: String, counts: PackedInt32Array, data: PackedFloat32Array, last: bool):
	var scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != zone:
		return
	var sp = get_tree().get_first_node_in_group("zone_spawner")
	if sp and counts.size() == 7:
		sp.total_killed = counts[0]
		sp.trash_killed = counts[1]
		sp.thugs_killed = counts[2]
		sp.masters_killed = counts[3]
		sp.bosses_killed = counts[4]
		sp.min_clear = counts[5]
		sp.target_total = counts[6]
	for i in range(0, data.size(), FIELDS):
		var id = int(data[i])
		_seen[id] = true
		var m = mirrors.get(id)
		var pos = Vector3(data[i + 3], data[i + 4], data[i + 5])
		if m == null or not is_instance_valid(m):
			m = load("res://enemy.tscn").instantiate()
			m.mirror = true
			m.net_id = id
			scene.add_child(m)
			var el = int(data[i + 2])
			m.setup(1.0, int(data[i + 1]), Crafting.ELEMENTS[el] if el >= 0 else "physical")
			m.global_position = pos
			mirrors[id] = m
		m.net_target = pos
		m.MAX_HEALTH = data[i + 7]
		m.health = data[i + 6]
		m.aggroed = data[i + 8] > 0.5
		_misses[id] = 0
	if not last:
		return
	var seen = _seen
	_seen = {}
	for id in mirrors.keys():
		if seen.has(id):
			continue
		_misses[id] = _misses.get(id, 0) + 1
		if _misses[id] >= MIRROR_MISSES:	# asleep, far away
			if is_instance_valid(mirrors[id]):
				mirrors[id].queue_free()
			mirrors.erase(id)
			_misses.erase(id)


## Host: an enemy died. Everyone gets their own loot drop and the kill counts.
func enemy_died(e):
	enemies.erase(e.net_id)
	if players.size() > 1:
		_enemy_died.rpc(get_tree().current_scene.scene_file_path, e.net_id, e.tier)


@rpc("authority", "call_remote", "reliable")
func _enemy_died(zone: String, id: int, tier: int):
	var scene = get_tree().current_scene
	if scene == null or scene.scene_file_path != zone:
		return
	var m = mirrors.get(id)
	mirrors.erase(id)
	if m and is_instance_valid(m):
		m.mirror_died()	# my own orb and gold
	var sp = get_tree().get_first_node_in_group("zone_spawner")
	if sp:
		sp._on_enemy_died(tier)	# boss unlocks, "zone cleared"


## Client: I hit / rooted a mirror. The host applies it to the real enemy.
func hit_enemy(id: int, amount: float):
	_hit.rpc_id(1, get_tree().current_scene.scene_file_path, id, amount)

func root_enemy(id: int, seconds: float):
	_root.rpc_id(1, get_tree().current_scene.scene_file_path, id, seconds)


@rpc("any_peer", "call_remote", "reliable")
func _hit(zone: String, id: int, amount: float):
	var e = enemies.get(id)
	if e and is_instance_valid(e) and get_tree().current_scene.scene_file_path == zone:
		e.aggroed = true
		e.take_damage(amount)

@rpc("any_peer", "call_remote", "reliable")
func _root(zone: String, id: int, seconds: float):
	var e = enemies.get(id)
	if e and is_instance_valid(e) and get_tree().current_scene.scene_file_path == zone:
		e.root(seconds)
