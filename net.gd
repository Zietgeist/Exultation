extends Node
## Autoload "Net": online co-op for up to 7 players, each free to be in a different zone.
##
## One player HOSTS. The host's game runs every zone that has a player in it (Zones keeps them
## loaded side by side, each in its own little world): enemies, kills, boss fights, layouts.
## Others JOIN. A joined player's game shows only the zone they're in, with copies ("mirrors")
## of the host's enemies there. Hits, roots and heals go to whoever owns the target.
## Everyone keeps their own loot, gold, gear, unlocks and skill ranks.
##
## Moving around: ALL travel goes through Net.go(). Solo, it just travels. Online, it tells the
## host (who loads the zone and sends its layout) and tells the others in your zone, who get a
## "Follow / Stay" choice. Press P to rejoin the party.
##
## Connection: direct (ENet, PORT) or Steam (steam_link.gd). Both end in start_with_peer().
## Testing on one PC: Godot > Debug > Customize Run Instances: 2+ instances,
## arguments "--host" for one and "--join" for the others (add "--class=healer" to skip the class pick).

const PORT = 24565
const MAX_PLAYERS = 7			# host + 6 friends: one home PC can run that many zones at once
const STATE_RATE = 0.05			# my position to the others, 20 times a second
const SNAPSHOT_RATE = 0.1		# host: enemies to each player, 10 times a second
const ROSTER_RATE = 1.0			# host: who's where, once a second
const MIRROR_MISSES = 4			# client: an enemy missing from this many snapshots fell asleep (or left)
const SNAPSHOT_RADIUS = 45.0	# each player only gets the enemies near them
const FIELDS = 9
const PER_PACKET = 30			# enemies per message (30 x 36 bytes fits in one network packet)
const COLORS = [Color(1, 0.49, 1), Color(0.3, 0.8, 1), Color(1, 0.6, 0.2), Color(0.5, 1, 0.4)]
const NOWHERE = Vector3.INF		# "no spot given" in network messages

signal status(text)		# connection messages for the start screen
signal follow_offer(text, go)	# someone in my zone left: show Follow / Stay (go = Callable)

var mode := "solo"		# solo, host, client
var players := {}		# host: peer id -> {class_id}
var roster := {}		# everyone: peer id -> {c = class id, k = zone key, p = zone path, pos}
var puppets := {}		# peer id -> that player's stand-in (host: in whatever zone they're in)
var enemies := {}		# host: net id -> enemy (every zone)
var mirrors := {}		# client: net id -> mirror enemy (my zone)
var _misses := {}
var _seen := {}
var _next_enemy_id := 1
var _state_t := 0.0
var _snap_t := 0.0
var _roster_t := 0.0
var travelling := false	# client: asked the host for a zone, waiting for its layout


func _ready():
	multiplayer.peer_connected.connect(func(id): print("Peer connected: ", id))
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
	start_with_peer(peer, true)
	print("Hosting on port ", PORT)
	return true


func join(ip: String) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip if ip != "" else "127.0.0.1", PORT)
	if err != OK:
		ErrorLog.fail("Couldn't start joining %s (error %d)" % [ip, err])
		return false
	start_with_peer(peer, false)
	status.emit("Connecting to %s ..." % ip)
	return true


## Start online play with a ready-made connection (ENet above, or Steam).
func start_with_peer(peer: MultiplayerPeer, as_host: bool):
	multiplayer.multiplayer_peer = peer
	mode = "host" if as_host else "client"
	if as_host:
		players = {1: _my_info()}
	get_window().title = "Exultation - " + ("Host" if as_host else "Joined")


func leave():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "solo"
	players.clear()
	roster.clear()
	puppets.clear()
	mirrors.clear()
	enemies.clear()
	SteamLink.leave_lobby()
	Party.end()


func _fail(text: String):
	ErrorLog.warn(text)
	GameState.notify(text)
	status.emit(text)
	leave()
	Zones.reset()
	get_tree().change_scene_to_file.call_deferred("res://ClassSelect.tscn")


func _my_info() -> Dictionary:
	return {class_id = GameState.player_class, name = Story.player_name}


## Each player gets their own color (the host is always pink).
func color_of(id: int) -> Color:
	return COLORS[0] if id == 1 else COLORS[1 + id % (COLORS.size() - 1)]


func _on_connected():
	status.emit("Connected! Waiting for the host...")
	_register.rpc_id(1, _my_info())


func _on_peer_disconnected(id: int):
	players.erase(id)
	roster.erase(id)
	var p = puppets.get(id)
	puppets.erase(id)
	if p and is_instance_valid(p):
		var z = Zones.zone_of(p)
		p.queue_free()
		if is_host() and z and z != Zones.local_zone():
			_unload_if_empty.call_deferred(z)
	GameState.notify("A player left the party")


func _unload_if_empty(z):
	if is_instance_valid(z) and not Zones.is_busy(z) and z != Zones.local_zone():
		Zones.unload(z)


## Host: a new player. Bring them to wherever the host is.
@rpc("any_peer", "call_remote", "reliable")
func _register(info: Dictionary):
	var id = multiplayer.get_remote_sender_id()
	players[id] = info
	Party.host_member_joined(info.get("name", "a friend"))
	GameState.notify("%s joined the party!" % Classes.label(info.class_id))
	var here = Zones.local_zone()
	if here:
		var spot = Zones.player.global_position + Vector3(randf_range(-2, 2), 0, randf_range(2, 3))
		_send_into(id, here.path, here.key, "", spot)


# ---------------- Every frame ----------------

func _process(delta):
	if not is_online():
		return
	var key = Zones.local_key()
	_state_t -= delta
	if _state_t <= 0.0 and key != "" and not travelling:
		_state_t = STATE_RATE
		var me = Zones.player
		_player_state.rpc(key, Zones.local_path(), me.global_position, me.rotation.y, me.health, me.MAX_HEALTH, me.player_class, me.disguised)
		if me.pet and is_instance_valid(me.pet) and me.pet.is_inside_tree():
			_pet_state.rpc(key, me.pet.global_position, me.pet.alive(), me.pet.draws_aggro())
	if not is_host():
		return
	_snap_t -= delta
	if _snap_t <= 0.0 and puppets.size() > 0:
		_snap_t = SNAPSHOT_RATE
		_send_snapshots()
	_roster_t -= delta
	if _roster_t <= 0.0:
		_roster_t = ROSTER_RATE
		_update_roster()


# ---------------- Travel ----------------

## Go to a zone. spot = where to appear (null: by the door you came from).
## key = which copy (only one-off zones like a Trial Ground have their own key). info = extra zone info.
func go(path: String, key := "", spot = null, info := {}):
	if key == "":
		key = path
	Rivals.leaving(Zones.local_zone())	# your rival here still lives: you skipped it
	var sp = Zones.local_first("zone_spawner")
	if sp and sp.total_killed < sp.min_clear * 0.5 and Zones.local_path() in GameState.ZONE_ORDER:
		Traits.on_left_early(GameState.ZONE_NAMES.get(Zones.local_path(), "the zone"))	# Swift
	if is_online() and Zones.local_key() != "" and not info.get("solo", false):	# solo trips (Trial Grounds) don't ask friends to follow
		_left_zone.rpc(Zones.local_key(), path, key, spot if spot != null else NOWHERE, info, GameState.player_class)
	if is_client():
		travelling = true
		_request_zone.rpc_id(1, path, key, Zones.local_path(), spot if spot != null else NOWHERE, info)
		return
	if not info.is_empty():
		Zones.pending_info[key] = info
	GameState.pending_spawn = spot
	Zones.travel(path, key)


## P: go to where the party is (the host's zone; for the host, the busiest zone with friends in it).
func rejoin():
	if not is_online():
		return
	var target = null
	if is_client():
		target = roster.get(1)
	else:
		var counts = {}
		for id in roster:
			if id != 1 and not roster[id].k.begins_with(Trials.ARENA):	# Trial Grounds are solo
				counts[roster[id].k] = counts.get(roster[id].k, 0) + 1
		var best = 0
		for id in roster:
			if id != 1 and counts.get(roster[id].k, 0) > best:
				best = counts[roster[id].k]
				target = roster[id]
	if target != null and target.k.begins_with(Trials.ARENA):
		GameState.notify("They're in a Trial Ground. Those are solo; wait for them to come out.")
		return
	if target == null or target.k == Zones.local_key():
		GameState.notify("You're already with the party")
		return
	go(target.p, target.k, target.pos + Vector3(randf_range(-2, 2), 0, randf_range(2, 3)))


## Someone in my zone left: offer to follow.
@rpc("any_peer", "call_remote", "reliable")
func _left_zone(from_key: String, path: String, key: String, spot: Vector3, info: Dictionary, class_id: String):
	if Zones.local_key() != from_key or Zones.player == null:
		return
	var where = GameState.ZONE_NAMES.get(path, "")
	if where == "":
		where = SkinManager.name_of("trial_arena") if path == Trials.ARENA else path.get_file().get_basename()
	var go_call = func(): go(path, key, null if spot == NOWHERE else spot, info)
	follow_offer.emit("%s went to %s" % [Classes.label(class_id), where], go_call)


## Host: a joined player wants a zone.
@rpc("any_peer", "call_remote", "reliable")
func _request_zone(path: String, key: String, from_path: String, spot: Vector3, info: Dictionary):
	_send_into(multiplayer.get_remote_sender_id(), path, key, from_path, null if spot == NOWHERE else spot, info)


## Host: load (or keep) the zone, put the player's stand-in there, then send the layout.
func _send_into(id: int, path: String, key: String, from_path: String, spot, info := {}):
	if not ResourceLoader.exists(path):
		ErrorLog.fail("A player asked for a zone that doesn't exist: " + path)
		return
	if not info.is_empty() and Zones.get_zone(key) == null:
		Zones.pending_info[key] = info
	var z = Zones.ensure(path, key)
	var entry = Zones.entry_point(z, from_path, spot)
	var p = _puppet_for(id, players.get(id, {}).get("class_id", "dps"))
	Zones.place_puppet(p, path, key, entry)
	await get_tree().create_timer(0.5).timeout	# a just-loaded zone finishes building (obstacles come a moment later)
	if not is_instance_valid(z):
		return
	_enter_zone.rpc_id(id, path, key, _layout_of(z), entry, z.info, GameState.unlocked_zones)


func _layout_of(z) -> Dictionary:
	var layout = {}
	var parts = {"terrain": "zone_terrain", "obstacles": "zone_obstacles", "features": "zone_features"}	# features: region bosses down, encounters done
	for part in parts:
		var node = Zones.first(z.root, parts[part])
		if node:
			layout[part] = node.save_state()
	return layout


## Joined player: the host has the zone ready. Build the same layout here and go.
@rpc("authority", "call_remote", "reliable")
func _enter_zone(path: String, key: String, layout: Dictionary, entry: Vector3, info: Dictionary, host_unlocks: Array):
	travelling = false
	for z in host_unlocks:	# you can enter anything the host has opened; your own unlocks are kept
		if not GameState.is_unlocked(z):
			GameState.unlocked_zones.append(z)
	if not layout.is_empty():
		var memory = GameState.zone_memory_of(path)	# keeps my own explored map (fog)
		memory.erase("spawner")
		for part in layout:
			memory[part] = layout[part]
		GameState.zone_memory[path] = memory
	if not info.is_empty():
		Zones.pending_info[key] = info
	for id in puppets:	# stand-ins and enemy copies belong to the zone I'm leaving
		if is_instance_valid(puppets[id]):
			puppets[id].queue_free()
	puppets.clear()
	for id in mirrors:
		if is_instance_valid(mirrors[id]):
			mirrors[id].queue_free()
	mirrors.clear()
	_misses.clear()
	GameState.pending_spawn = entry
	Zones.travel.call_deferred(path, key)	# (starts the World first if we're still on the start screen)


# ---------------- Players ----------------

func _puppet_for(id: int, class_id: String):
	var p = puppets.get(id)
	if p and is_instance_valid(p):
		return p
	p = load("res://Player.tscn").instantiate()
	p.is_puppet = true
	p.peer_id = id
	p.player_class = class_id
	p.puppet_color = color_of(id)
	p.name = "Remote_%d" % id
	puppets[id] = p
	return p


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _player_state(key: String, path: String, pos: Vector3, rot: float, hp: float, max_hp: float, class_id: String, disguised := false):
	var id = multiplayer.get_remote_sender_id()
	if is_host():
		var p = _puppet_for(id, class_id)
		var z = Zones.zone_of(p)
		if z == null or z.key != key:	# (normally placed already when they asked for the zone)
			Zones.place_puppet(p, path, key, pos)
		p.net_state(pos, rot, hp, max_hp)
		p.set_disguise(disguised)	# the host's enemies leave a disguised player alone
		return
	# Joined player: only show people who are in my zone
	var p = puppets.get(id)
	if Zones.local_key() != key or Zones.local_root() == null:
		if p and is_instance_valid(p):
			p.queue_free()
		puppets.erase(id)
		return
	if p == null or not is_instance_valid(p):
		p = _puppet_for(id, class_id)
		Zones.local_root().add_child(p)
		p.global_position = pos
	p.net_state(pos, rot, hp, max_hp)
	p.set_disguise(disguised)


## Host: who's where (for the party list and P to rejoin).
func _update_roster():
	roster = {1: {c = GameState.player_class, n = Story.player_name, k = Zones.local_key(), p = Zones.local_path(), pos = Zones.player.global_position if Zones.player else Vector3.ZERO}}
	for id in puppets:
		var p = puppets[id]
		if is_instance_valid(p) and Zones.zone_of(p):
			var z = Zones.zone_of(p)
			roster[id] = {c = p.player_class, n = players.get(id, {}).get("name", Classes.label(p.player_class)), k = z.key, p = z.path, pos = p.global_position}
	_roster.rpc(roster)


@rpc("authority", "call_remote", "reliable")
func _roster(r: Dictionary):
	roster = r


## Something hurt / healed / blessed another player's stand-in: tell that player.
func hurt_player(id: int, amount: float, enemy):
	_hurt.rpc_id(id, amount, enemy.net_id if enemy and "net_id" in enemy else 0)

## Stun another player (Daddy's tickles): their own game does it.
func stun_player(id: int, seconds: float, text: String):
	_stun_player.rpc_id(id, clampf(seconds, 0.0, 10.0), text.left(40))


@rpc("any_peer", "call_remote", "reliable")
func _stun_player(seconds: float, text: String):
	if Zones.player and not travelling:
		Zones.player.stun(clampf(seconds, 0.0, 10.0), text.left(40))	# never trust big numbers from the network


func heal_player(id: int, amount: float):
	_heal.rpc_id(id, amount)

func vow_player(id: int, vow: Dictionary):
	_vow.rpc_id(id, vow)


@rpc("any_peer", "call_remote", "reliable")
func _hurt(amount: float, enemy_id: int):
	if Zones.player and not travelling:
		Zones.player.take_damage(amount, mirrors.get(enemy_id))

@rpc("any_peer", "call_remote", "reliable")
func _heal(amount: float):
	if Zones.player:
		Zones.player.heal(amount)

@rpc("any_peer", "call_remote", "reliable")
func _vow(vow: Dictionary):
	if Zones.player:
		Zones.player.receive_vow(vow)


# ---------------- Enemies (host runs them, joined players mirror them) ----------------

func register_enemy(e) -> int:
	var id = _next_enemy_id
	_next_enemy_id += 1
	enemies[id] = e
	return id


## Host: the players in a zone (by key), not counting me.
func _peers_in(key: String) -> Array:
	var out = []
	for id in puppets:
		var p = puppets[id]
		if is_instance_valid(p) and Zones.key_of(p) == key:
			out.append(id)
	return out


func _send_snapshots():
	for id in enemies.keys():
		var e = enemies[id]
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			enemies.erase(id)
	for peer in puppets:
		var who = puppets[peer]
		if not is_instance_valid(who) or Zones.zone_of(who) == null:
			continue
		var z = Zones.zone_of(who)
		var sp = Zones.first(z.root, "zone_spawner")
		var counts = PackedInt32Array()
		if sp:
			counts = PackedInt32Array([sp.total_killed, sp.trash_killed, sp.thugs_killed, sp.masters_killed, sp.bosses_killed, sp.min_clear, sp.target_total])
		var c = who.global_position
		var data = PackedFloat32Array()
		for id in enemies:
			var e = enemies[id]
			if e.get_viewport() != z:
				continue
			var p = e.global_position
			if Vector2(p.x - c.x, p.z - c.z).length() > SNAPSHOT_RADIUS:
				continue
			data.append_array([id, e.tier + (10 if not e.rival.is_empty() else 0), Crafting.ELEMENTS.find(e.damage_type), p.x, p.y, p.z, e.health, e.MAX_HEALTH, 1.0 if e.aggroed else 0.0])
			if data.size() >= FIELDS * PER_PACKET:
				_snapshot.rpc_id(peer, z.key, counts, data, false)
				data = PackedFloat32Array()
		_snapshot.rpc_id(peer, z.key, counts, data, true)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(key: String, counts: PackedInt32Array, data: PackedFloat32Array, last: bool):
	var scene = Zones.local_root()
	if scene == null or Zones.local_key() != key or travelling:
		return
	var sp = Zones.local_first("zone_spawner")
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
			m.setup(1.0, int(data[i + 1]) % 10, Crafting.ELEMENTS[el] if el >= 0 else "physical")
			if int(data[i + 1]) >= 10:	# a rival: ask the host for its name and looks
				_rival_info.rpc_id(1, key, id)
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


## Host: an enemy died. Players in that zone get their own loot drop and the kill count.
func enemy_died(e):
	enemies.erase(e.net_id)
	var key = Zones.key_of(e)
	for peer in _peers_in(key):
		_enemy_died.rpc_id(peer, key, e.net_id, e.tier if e.rival.is_empty() and not e.no_count else -1)	# rivals / landmark bosses don't count toward unlocks


@rpc("authority", "call_remote", "reliable")
func _enemy_died(key: String, id: int, tier: int):
	if Zones.local_key() != key:
		return
	var m = mirrors.get(id)
	mirrors.erase(id)
	if m and is_instance_valid(m):
		m.mirror_died()	# my own orb and gold
	var sp = Zones.local_first("zone_spawner")
	if sp and tier >= 0:
		sp._on_enemy_died(tier)	# boss unlocks, "zone cleared"


## Joined player: I hit / rooted a mirror. The host applies it to the real enemy.
func hit_enemy(id: int, amount: float):
	_hit.rpc_id(1, Zones.local_key(), id, amount)

func root_enemy(id: int, seconds: float):
	_root.rpc_id(1, Zones.local_key(), id, seconds)

func stun_enemy(id: int, seconds: float):	# Phase Runner's Blink landing, on a joined player's screen
	_stun.rpc_id(1, Zones.local_key(), id, seconds)

func turn_enemy(id: int, seconds: float, buff := 1.0):	# Healer's F, cast on a joined player's screen
	_turn.rpc_id(1, Zones.local_key(), id, seconds, buff)


@rpc("any_peer", "call_remote", "reliable")
func _hit(key: String, id: int, amount: float):
	var e = enemies.get(id)
	if e and is_instance_valid(e) and Zones.key_of(e) == key:
		e.aggroed = true
		e.take_damage(amount)

@rpc("any_peer", "call_remote", "reliable")
func _root(key: String, id: int, seconds: float):
	var e = enemies.get(id)
	if e and is_instance_valid(e) and Zones.key_of(e) == key:
		e.root(seconds)

@rpc("any_peer", "call_remote", "reliable")
func _stun(key: String, id: int, seconds: float):
	var e = enemies.get(id)
	if e and is_instance_valid(e) and Zones.key_of(e) == key:
		e.stun(clampf(seconds, 0.0, 5.0))	# never trust big numbers from the network

@rpc("any_peer", "call_remote", "reliable")
func _turn(key: String, id: int, seconds: float, buff: float):
	var e = enemies.get(id)
	if e and is_instance_valid(e) and Zones.key_of(e) == key:
		e.turn_ally(clampf(seconds, 0.0, 60.0), clampf(buff, 1.0, 4.0))	# never trust big numbers from the network


# ---------------- Boss moves (boss_kit.gd) ----------------

## Host: a boss (or a rival's slam) just did something big: show it to the players in its zone.
func boss_fx(e, kind: String, data: Dictionary):
	if not is_host() or e.net_id == 0:
		return
	var key = Zones.key_of(e)
	for peer in _peers_in(key):
		_boss_fx.rpc_id(peer, key, e.net_id, kind, data)


@rpc("authority", "call_remote", "reliable")
func _boss_fx(key: String, id: int, kind: String, data: Dictionary):
	if Zones.local_key() != key:
		return
	var m = mirrors.get(id)
	if m == null or not is_instance_valid(m):	# not near me (no copy here): nothing to see
		return
	if kind == "slam":
		if typeof(data.get("at")) == TYPE_VECTOR3:
			m.slam_fx(data.at)
	elif m.has_node("BossKit"):
		m.get_node("BossKit").net_fx(kind, data)


## Joined player: a boss just showed up on my screen; ask the host its name and how angry it is.
func ask_boss_info(id: int):
	if is_client():
		_boss_info.rpc_id(1, Zones.local_key(), id)


@rpc("any_peer", "call_remote", "reliable")
func _boss_info(key: String, id: int):
	var e = enemies.get(id)
	if e == null or not is_instance_valid(e) or Zones.key_of(e) != key or not e.has_node("BossKit"):
		return
	var kit = e.get_node("BossKit")
	_boss_fx.rpc_id(multiplayer.get_remote_sender_id(), key, id, "info", {name = kit.display_name, phase = kit.phase})


# ---------------- Shared moments ----------------

## Host: tell the players in `node`'s zone about something (their zone scene handles it in net_event).
func scene_event(node, event: String, data: Dictionary):
	if not is_host():
		return
	var key = Zones.key_of(node)
	for peer in _peers_in(key):
		_scene_event.rpc_id(peer, key, event, data)


@rpc("authority", "call_remote", "reliable")
func _scene_event(key: String, event: String, data: Dictionary):
	var scene = Zones.local_root()
	if scene and Zones.local_key() == key and scene.has_method("net_event"):
		scene.net_event(event, data)


# ---------------- Rivals (rivals.gd) ----------------

## Joined player: the enemy that killed me (a mirror) should become my rival. The host does it.
func rival_born(enemy_id: int, s: Dictionary):
	_rival_born.rpc_id(1, Zones.local_key(), enemy_id, s)

## Joined player: my rival lives in this zone; host, please put it here.
func spawn_rival(s: Dictionary, spot: Vector3):
	_spawn_rival.rpc_id(1, Zones.local_key(), s, spot)

## Host: show everyone in the zone the rival's name and looks.
func rival_look_all(e):
	var key = Zones.key_of(e)
	for peer in _peers_in(key):
		_rival_look.rpc_id(peer, key, e.net_id, e.rival)

## Host: a rival owned by a joined player fell.
func rival_avenged(owner: int, id: String):
	_rival_avenged.rpc_id(owner, id)


@rpc("any_peer", "call_remote", "reliable")
func _rival_born(key: String, enemy_id: int, s: Dictionary):
	var e = enemies.get(enemy_id)
	if e and is_instance_valid(e) and Zones.key_of(e) == key:
		s.owner = multiplayer.get_remote_sender_id()
		e.become_rival(s)

@rpc("any_peer", "call_remote", "reliable")
func _spawn_rival(key: String, s: Dictionary, spot: Vector3):
	var z = Zones.get_zone(key)
	if z:
		s.owner = multiplayer.get_remote_sender_id()
		Rivals.spawn_rival(z, s, spot)

@rpc("any_peer", "call_remote", "reliable")
func _rival_info(key: String, enemy_id: int):
	var e = enemies.get(enemy_id)
	if e and is_instance_valid(e) and not e.rival.is_empty():
		_rival_look.rpc_id(multiplayer.get_remote_sender_id(), key, enemy_id, e.rival)

@rpc("authority", "call_remote", "reliable")
func _rival_look(key: String, enemy_id: int, s: Dictionary):
	var m = mirrors.get(enemy_id)
	if Zones.local_key() == key and m and is_instance_valid(m):
		m.rival_look(s)

@rpc("authority", "call_remote", "reliable")
func _rival_avenged(id: String):
	Rivals.avenge(id)


# ---------------- Giving gear (unworn gear only; worn gear is bound) ----------------

## A friend's name (from the roster), or their class if we don't know it.
func name_of(id: int) -> String:
	var r = roster.get(id, {})
	return r.get("n", Classes.label(r.get("c", "")) if r.has("c") else "a friend")


## Everyone else in the party: [peer id, name]
func others() -> Array:
	var out = []
	for id in roster:
		if id != my_id():
			out.append([id, name_of(id)])
	return out


func give_item(to_id: int, item: Dictionary):
	_give_item.rpc_id(to_id, item, Story.player_name)


@rpc("any_peer", "call_remote", "reliable")
func _give_item(item: Dictionary, from_name: String):
	Crafting.receive_item(item, from_name)


# ---------------- Pets (each player's pet is shown to the others) ----------------

## Someone's pet moved. Show it next to their stand-in (on the host, enemies can go after it).
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _pet_state(key: String, pos: Vector3, alive: bool, gathering := true):
	var id = multiplayer.get_remote_sender_id()
	var p = puppets.get(id)
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or Zones.key_of(p) != key:
		return
	var g = p.get_node_or_null("PetGhost")
	if g == null:
		g = load("res://pet_ghost.gd").new()
		g.name = "PetGhost"
		g.peer_id = id
		g.color = color_of(id)
		p.add_child(g)
		g.global_position = pos
	g.net_state(pos, alive, gathering)


## Host: an enemy hit a joined player's pet.
func hurt_pet(id: int, amount: float):
	_pet_hurt.rpc_id(id, amount)

func pet_guarded(id: int):
	_pet_guarded_rpc.rpc_id(id)


@rpc("any_peer", "call_remote", "reliable")
func _pet_hurt(amount: float):
	if Zones.player and Zones.player.pet and not travelling:
		Zones.player.pet.take_damage(amount)

@rpc("any_peer", "call_remote", "reliable")
func _pet_guarded_rpc():
	if Zones.player and Zones.player.pet:
		Zones.player.pet.guarded()


# ---------------- Party saves (party.gd) ----------------

## Host: send the party to everyone.
func send_party(p: Dictionary):
	if is_host():
		_party.rpc(p)

## Joined player: something happened that the party should remember (the host records it).
func party_event(kind: String, path: String):
	_party_event.rpc_id(1, kind, path)

## Host: the party just cleared the last zone. Everyone celebrates.
func party_legend():
	if is_host():
		_party_legend.rpc()


@rpc("authority", "call_remote", "reliable")
func _party(p: Dictionary):
	Party.receive(p)

@rpc("any_peer", "call_remote", "reliable")
func _party_event(kind: String, path: String):
	if kind == "unlock":
		GameState.unlock(path)
	elif kind == "cleared":
		Party.zone_cleared(path)

@rpc("authority", "call_remote", "reliable")
func _party_legend():
	Party.become_legend.call_deferred()


# ---------------- Small zone set pieces (by group) ----------------

## Host: tell the joined players in `node`'s zone; their copy of the group's first node gets net_event().
func group_event(node, group: String, event: String, data: Dictionary):
	if not is_host():
		return
	var key = Zones.key_of(node)
	for peer in _peers_in(key):
		_group_event.rpc_id(peer, key, group, event, data)


@rpc("authority", "call_remote", "reliable")
func _group_event(key: String, group: String, event: String, data: Dictionary):
	if Zones.local_key() != key or not group in ["daddy_camp"]:	# only groups that expect it
		return
	var n = Zones.local_first(group)
	if n and n.has_method("net_event"):
		n.net_event(event, data)


# ---------------- Regions and encounters (zone_features.gd) ----------------

## Host: something happened in a big zone (region boss down, ambush, horde...); joined players there see it too.
func feature_event(node, event: String, data: Dictionary):
	if not is_host():
		return
	var key = Zones.key_of(node)
	for peer in _peers_in(key):
		_feature_event.rpc_id(peer, key, event, data)


@rpc("authority", "call_remote", "reliable")
func _feature_event(key: String, event: String, data: Dictionary):
	if Zones.local_key() != key:
		return
	var f = Zones.local_first("zone_features")
	if f:
		f.net_event(event, data)


# ---------------- Landmarks (landmarks.gd, lm_*.gd) ----------------

## Host: something happened at a landmark; the joined players in that zone see it too.
func landmark_event(node, event: String, data: Dictionary):
	if not is_host():
		return
	var key = Zones.key_of(node)
	for peer in _peers_in(key):
		_landmark_event.rpc_id(peer, key, str(node.name), event, data)

## Joined player: please record this about a landmark (the host keeps the party's record).
func landmark_state(path: String, id: String, changes: Dictionary):
	_landmark_state.rpc_id(1, path, id, changes)


@rpc("authority", "call_remote", "reliable")
func _landmark_event(key: String, id: String, event: String, data: Dictionary):
	if Zones.local_key() != key:
		return
	for l in Zones.local_all("landmark"):
		if str(l.name) == id:
			l.net_event(event, data)

@rpc("any_peer", "call_remote", "reliable")
func _landmark_state(path: String, id: String, changes: Dictionary):
	Landmarks.set_state(path, id, changes)
