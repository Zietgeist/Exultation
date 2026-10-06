extends Node
## Autoload "SteamLink": play with friends through Steam (invites, no router setup).
##
## Needs the GodotSteam add-on (GDExtension, "GodotSteam" in Godot's AssetLib) in addons/godotsteam.
## Without it everything else still works: the start screen just says Steam isn't installed.
##
## How it works:
##   Host:  makes a friends-only Steam lobby, opens the Steam invite window, then hosts over Steam.
##   Join:  accept a friend's invite (or right-click them in Steam > Join Game). The game joins
##          their lobby and connects to the lobby owner (the host).
## Press F7 in game (host) to open the Steam invite window again.
##
## APP_ID 480 = Valve's free test app ("Spacewar"). Change it when you get your own App ID.

const APP_ID = 480
const LOBBY_FRIENDS_ONLY = 1	# Steam.LOBBY_TYPE_FRIENDS_ONLY
const RESULT_OK = 1				# Steam's "OK" result for a new lobby
const JOIN_OK = 1				# Steam's "success" when entering a lobby
const GAME_TAG = "exultation"	# marks our lobbies (app 480 is shared by many test games)

signal lobby_ready		# host: lobby made, hosting over Steam
signal invite_waiting	# someone invited me while I was on the start screen

var steam = null		# the GodotSteam singleton, or null if the add-on isn't installed
var ready_ok := false	# Steam is running and logged in
var lobby_id := 0
var pending_lobby := 0	# invite accepted on the start screen: join after picking a class
var _hosting := false

# Tests can swap these to fake Steam's connection with a local one.
var make_host_peer: Callable
var make_client_peer: Callable


func _init():
	make_host_peer = _steam_host_peer
	make_client_peer = _steam_client_peer


func _ready():
	if Engine.has_singleton("Steam"):
		start(Engine.get_singleton("Steam"))
	else:
		print("Steam: GodotSteam add-on not installed (online play by address still works)")


## Hook up to Steam (or a stand-in when testing).
func start(steam_object):
	steam = steam_object
	var r = steam.steamInitEx(APP_ID, true)	# true = Steam callbacks run automatically
	if typeof(r) != TYPE_DICTIONARY or r.get("status", 1) != 0:
		ErrorLog.warn("Steam didn't start: %s. Is the Steam app running and logged in?" % [r])
		return
	ready_ok = true
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("join_requested", _on_join_requested)
	print("Steam ready: logged in as ", steam.getPersonaName())
	# Started by accepting an invite while the game was closed: Steam adds "+connect_lobby <id>"
	var args = OS.get_cmdline_args()
	var i = args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size():
		pending_lobby = int(args[i + 1])
		invite_waiting.emit()


## Steam is usable right now (add-on installed, Steam running, peer type available).
func available() -> bool:
	return ready_ok


func why_not() -> String:
	if steam == null:
		return "Steam add-on isn't installed yet (see the Steam setup steps)."
	return "Steam isn't running or isn't logged in."


# ---------------- Host ----------------

func host_lobby():
	if not available():
		ErrorLog.warn("Can't host on Steam: " + why_not())
		return
	_hosting = true
	Net.status.emit("Making a Steam lobby...")
	steam.createLobby(LOBBY_FRIENDS_ONLY, Net.MAX_PLAYERS)


func _on_lobby_created(result: int, new_lobby_id: int):
	if result != RESULT_OK:
		ErrorLog.fail("Steam couldn't make a lobby (result %d)" % result)
		Net.status.emit("Steam couldn't make a lobby.")
		_hosting = false
		return
	lobby_id = new_lobby_id
	steam.setLobbyData(lobby_id, "game", GAME_TAG)
	steam.setLobbyJoinable(lobby_id, true)
	var peer = make_host_peer.call()
	if peer == null:
		return
	Net.start_with_peer(peer, true)
	print("Steam lobby %d ready, hosting over Steam" % lobby_id)
	lobby_ready.emit()
	invite_friends()


## Opens Steam's invite window (Shift+Tab overlay must be on in Steam).
func invite_friends():
	if available() and lobby_id != 0:
		steam.activateGameOverlayInviteDialog(lobby_id)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		if Net.is_host() and lobby_id != 0:
			invite_friends()


# ---------------- Join ----------------

## A friend's invite was accepted (or "Join Game" in the Steam friends list).
func _on_join_requested(requested_lobby: int, _friend_id: int):
	var scene = get_tree().current_scene
	if scene and scene.scene_file_path == "res://ClassSelect.tscn":
		pending_lobby = requested_lobby	# pick a class first
		invite_waiting.emit()
		return
	if Net.is_online():
		Net.leave()
	join_lobby(requested_lobby)


func join_lobby(id: int):
	if not available():
		ErrorLog.warn("Can't join on Steam: " + why_not())
		return
	pending_lobby = 0
	_hosting = false
	Net.status.emit("Joining your friend's Steam lobby...")
	steam.joinLobby(id)


func _on_lobby_joined(joined_lobby: int, _permissions: int, _locked: bool, response: int):
	if _hosting:
		return	# that's my own lobby (the owner also "joins" it)
	if response != JOIN_OK:
		ErrorLog.warn("Couldn't join the Steam lobby (response %d). It may be full or closed." % response)
		Net.status.emit("Couldn't join that lobby.")
		return
	lobby_id = joined_lobby
	var owner_id = steam.getLobbyOwner(lobby_id)
	var peer = make_client_peer.call(owner_id)
	if peer == null:
		return
	Net.start_with_peer(peer, false)
	Net.status.emit("Connecting to the host over Steam...")


func leave_lobby():
	if available() and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	_hosting = false


# ---------------- Steam connections ----------------

func _steam_host_peer():
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		ErrorLog.fail("GodotSteam is installed but has no SteamMultiplayerPeer. Use GodotSteam 4.16 or newer (GDExtension).")
		return null
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err = peer.create_host(0)
	if err != OK:
		ErrorLog.fail("Steam hosting failed (error %d)" % err)
		return null
	peer.server_relay = true
	return peer


func _steam_client_peer(owner_id: int):
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		ErrorLog.fail("GodotSteam is installed but has no SteamMultiplayerPeer. Use GodotSteam 4.16 or newer (GDExtension).")
		return null
	var peer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err = peer.create_client(owner_id, 0)
	if err != OK:
		ErrorLog.fail("Steam joining failed (error %d)" % err)
		return null
	peer.server_relay = true
	return peer
