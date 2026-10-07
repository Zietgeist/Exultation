extends Node
## Autoload "Party": a saved adventure for a group of friends.
##
##   - When you HOST, you pick a party on the start screen: a new one (give it a name) or one you've
##     played before. The party's progress (which zones are open, which are cleared, its legends)
##     is what everyone plays with in that game.
##   - Every member keeps a copy (user://parties/<id>.cfg), so ANY of you can host it next time and
##     carry on. The host's copy is the one that counts; it's sent to everyone when they join and
##     whenever it changes.
##   - Your own things stay yours: gear, gold, pet, traits, story. Zones you open with a party are
##     also opened in your own (solo) progress.
##   - Clearing the last zone (Zone 10) is the big one: the party becomes a Legend. Its name, its
##     members and the day go on the Hall of Legends at Home, and into everyone's Chronicle.
##
## Solo play doesn't use a party (your own progress, as before).

signal changed

const DIR = "user://parties"

var current := {}	# the party in play, or {} when solo


func active() -> bool:
	return not current.is_empty()


func label() -> String:
	return current.get("name", "") if active() else ""


# ---------------- Saved parties ----------------

## Every party this PC has played in, most recent first.
func list_saved() -> Array:
	var out = []
	var d = DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".cfg"):
			continue
		var cfg = ConfigFile.new()
		if cfg.load(DIR + "/" + f) == OK:
			var p = cfg.get_value("party", "data", {})
			if p is Dictionary and p.has("id"):
				out.append(p)
	out.sort_custom(func(a, b): return a.get("last_played", "") > b.get("last_played", ""))
	return out


func new_party(party_name: String) -> Dictionary:
	party_name = party_name.strip_edges()
	if party_name == "":
		party_name = "%s's party" % Story.player_name
	return {
		id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000],
		name = party_name.substr(0, 32),
		created = Time.get_date_string_from_system(),
		last_played = Time.get_date_string_from_system(),
		members = {},		# name -> date last played
		unlocked = ["res://Home.tscn", "res://Zone1.tscn"],
		cleared = [],		# zones where both bosses fell
		legend = "",		# date the last zone was cleared ("" = not yet)
	}


func save():
	if not active():
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var cfg = ConfigFile.new()
	cfg.set_value("party", "data", current)
	if cfg.save("%s/%s.cfg" % [DIR, current.id]) != OK:
		ErrorLog.fail("Party: couldn't save " + current.id)


# ---------------- Playing ----------------

## Host: start playing as this party.
func begin(p: Dictionary):
	current = p
	current.last_played = Time.get_date_string_from_system()
	_add_member(Story.player_name)
	GameState.use_party(current.unlocked)
	save()
	changed.emit()


## Back to solo (left the game).
func end():
	current = {}
	GameState.use_party(null)
	changed.emit()


func _add_member(n: String):
	if not current.members.has(n):
		current.members[n] = Time.get_date_string_from_system()
		if current.members.size() > 1:
			GameState.notify("%s joins %s." % [n, current.name])
	current.members[n] = Time.get_date_string_from_system()


## Host: someone joined: add them and send everyone the party.
func host_member_joined(member_name: String):
	if not active():
		return
	_add_member(member_name)
	save()
	Net.send_party(current)


## Joined player: the host sent the party (on join, and whenever it changes).
func receive(p: Dictionary):
	var first = not active() or current.get("id", "") != p.get("id", "")
	current = p
	GameState.use_party(current.unlocked)
	for z in current.unlocked:	# zones opened with the party open in your own progress too
		GameState.unlock_personal(z)
	save()
	changed.emit()
	if first:
		GameState.notify("Playing with %s (%d zones open)." % [current.name, current.unlocked.size() - 1])


## A zone opened. Host: record and share it. Joined: tell the host.
func zone_unlocked(path: String):
	if not active():
		return
	if Net.is_client():
		Net.party_event("unlock", path)
		return
	if not path in current.unlocked:
		current.unlocked.append(path)
	save()
	Net.send_party(current)


## Both bosses of a zone fell. The last zone makes the party a Legend.
func zone_cleared(path: String):
	if not active():
		return
	if Net.is_client():
		Net.party_event("cleared", path)
		return
	if path in current.cleared:
		return
	current.cleared.append(path)
	if path == GameState.ZONE_ORDER[-1] and current.legend == "":
		current.legend = Time.get_date_string_from_system()
		Net.party_legend()
		become_legend()
	save()
	Net.send_party(current)


## Everyone in the party, on their own PC.
func become_legend():
	var zone = GameState.ZONE_NAMES.get(GameState.ZONE_ORDER[-1], "the last zone")
	GameState.notify("LEGENDS! %s has cleared %s!" % [current.get("name", "Your party"), zone])
	Story.add("%s cleared %s. We are Legends. (%s)" % [current.get("name", "The party"), zone, ", ".join(current.get("members", {}).keys())])
	Story.once("legend", "Became a Legend of the Spiral.")


## Legends for the Hall at Home: [{name, date, members}] from every party this PC knows.
func legends() -> Array:
	var out = []
	for p in list_saved():
		if p.get("legend", "") != "":
			out.append({name = p.name, date = p.legend, members = p.members.keys()})
	return out


## Where a saved party has got to, for the start screen.
func summary(p: Dictionary) -> String:
	var furthest = "Zone 1"
	for z in GameState.ZONE_ORDER:
		if z in p.get("unlocked", []):
			furthest = GameState.ZONE_NAMES.get(z, z)
	var s = "%s - up to %s, %d cleared" % [p.name, furthest, p.get("cleared", []).size()]
	if p.get("legend", "") != "":
		s += " - LEGENDS"
	return s
