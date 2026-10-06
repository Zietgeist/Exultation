extends Control
## Start screen: pick a WORLD (skin), a RACE (from that world) and a CLASS.
## The world changes names, colors, terrain looks and which races you can play.
## The race decides which gear slots you have (an Ent has no boots, but twenty rings).

const GOLD = Color(1.0, 0.85, 0.3)

var world_pick: OptionButton
var world_about: Label
var race_pick: OptionButton
var race_about: Label
var class_buttons = {}	# class id -> Button
var class_about: Label
var play_mode: OptionButton	# Solo / Host / Join
var ip_box: LineEdit
var net_status: Label
var _waiting = false
const MODES = ["Solo", "Host on Steam (friends)", "Join a Steam friend", "Host by address", "Join by address"]
const SOLO = 0
const STEAM_HOST = 1
const STEAM_JOIN = 2
const ADDR_HOST = 3
const ADDR_JOIN = 4
var _world_ids = []


func _ready():
	$VBoxContainer.visible = false	# the old simple buttons; replaced by the screen below
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.07)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(640, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	_title(box, "EXULTATION", 44)

	_title(box, "World", 22)
	world_pick = OptionButton.new()
	_world_ids = SkinManager.skins.keys()
	_world_ids.sort()
	_world_ids.erase("default")
	_world_ids.push_front("default")	# Fantasy first
	for id in _world_ids:
		world_pick.add_item(SkinManager.skins[id].get("name", id))
	world_pick.select(max(0, _world_ids.find(SkinManager.current_id)))
	world_pick.item_selected.connect(_on_world)
	box.add_child(world_pick)
	world_about = _text(box)

	_title(box, "Race", 22)
	race_pick = OptionButton.new()
	race_pick.item_selected.connect(_on_race)
	box.add_child(race_pick)
	race_about = _text(box)

	# Online co-op: host a game, or join a friend's
	_title(box, "Play", 22)
	var net_row = HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	net_row.add_theme_constant_override("separation", 12)
	box.add_child(net_row)
	play_mode = OptionButton.new()
	for t in MODES:
		play_mode.add_item(t)
	if not SteamLink.available():	# grey out Steam until the add-on is in and Steam is running
		play_mode.set_item_disabled(STEAM_HOST, true)
		play_mode.set_item_disabled(STEAM_JOIN, true)
		play_mode.set_item_tooltip(STEAM_HOST, SteamLink.why_not())
		play_mode.set_item_tooltip(STEAM_JOIN, SteamLink.why_not())
	play_mode.item_selected.connect(_on_mode)
	net_row.add_child(play_mode)
	ip_box = LineEdit.new()
	ip_box.placeholder_text = "Host's address (blank = this PC)"
	ip_box.custom_minimum_size = Vector2(300, 0)
	ip_box.visible = false
	net_row.add_child(ip_box)
	net_status = _text(box)
	if not SteamLink.available():
		net_status.text = "Steam: " + SteamLink.why_not()
	Net.status.connect(func(t): net_status.text = t)
	SteamLink.invite_waiting.connect(_on_invite)
	SteamLink.lobby_ready.connect(func(): get_tree().change_scene_to_file("res://Home.tscn"))
	if SteamLink.pending_lobby != 0:
		_on_invite.call_deferred()

	_title(box, "Class", 22)
	# One button per class file (classes/*.json and mods). Hover to read about it, click to play.
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var grid_center = CenterContainer.new()
	grid_center.add_child(grid)
	box.add_child(grid_center)
	for id in Classes.ids():
		var b = Button.new()
		b.custom_minimum_size = Vector2(200, 56)
		b.pressed.connect(_start.bind(id))
		b.mouse_entered.connect(_show_class.bind(id))
		b.focus_entered.connect(_show_class.bind(id))
		grid.add_child(b)
		class_buttons[id] = b
	class_about = _text(box)
	class_about.custom_minimum_size = Vector2(0, 110)
	_show_class(Classes.ids()[0])

	_refresh()
	_read_command_line.call_deferred()


## Test shortcuts: --host, --join or --join=ADDRESS, --class=healer (starts right away)
func _read_command_line():
	var class_id = ""
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--host":
			play_mode.select(ADDR_HOST)
		elif arg == "--steam-host":
			play_mode.select(STEAM_HOST)
		elif arg == "--steam-join":
			play_mode.select(STEAM_JOIN)
		elif arg.begins_with("--join"):
			play_mode.select(ADDR_JOIN)
			ip_box.visible = true
			ip_box.text = arg.get_slice("=", 1) if "=" in arg else ""
		elif arg.begins_with("--class="):
			class_id = arg.get_slice("=", 1)
	if class_id != "" and not _waiting:
		_start(Classes.normalize(class_id))


func _on_world(i: int):
	SkinManager.set_skin(_world_ids[i])
	_refresh()


func _on_race(i: int):
	SkinManager.set_race(SkinManager.races()[i].id)
	_refresh()


func _refresh():
	world_about.text = SkinManager.skin_about()
	race_pick.clear()
	var races = SkinManager.races()
	for r in races:
		race_pick.add_item(r.name)
	for i in range(races.size()):
		if races[i].id == SkinManager.current_race:
			race_pick.select(i)
	var r = SkinManager.race()
	var slots = []
	for rs in SkinManager.race_slots():
		slots.append(rs.label if rs.count == 1 else "%d %ss" % [rs.count, rs.label])
	race_about.text = "%s\nGear slots: %s" % [r.get("about", ""), ", ".join(slots)]
	for id in class_buttons:
		class_buttons[id].text = "%s\n(%s)" % [Classes.label(id), Classes.get_def(id).get("role", "")]
	_show_class(_shown_class)


var _shown_class := ""

## About text + the class's three skills (with this world's names).
func _show_class(id: String):
	_shown_class = id
	var c = Classes.get_def(id)
	var lines = ["%s - %s" % [Classes.label(id), c.get("about", "")]]
	for key in Classes.KEYS:
		var sk = Classes.skill(id, key)
		lines.append("%s  %s: %s" % [key, Classes.skill_label(id, key), sk.get("about", "")])
	class_about.text = "\n".join(lines)


func _start(class_id: String):
	if _waiting:
		return
	GameState.player_class = class_id
	Crafting.ensure_slots()
	match play_mode.selected:
		STEAM_HOST:	# make a Steam lobby; the game starts when it's ready (lobby_ready)
			_waiting = true
			SteamLink.host_lobby()
			return
		STEAM_JOIN:	# join the friend who invited me (or wait for an invite)
			_waiting = true
			if SteamLink.pending_lobby != 0:
				SteamLink.join_lobby(SteamLink.pending_lobby)
			else:
				net_status.text = "Waiting for an invite. Ask your friend to press F7 and invite you,\nor right-click them in your Steam friends list > Join Game."
			return
		ADDR_HOST:	# start the server, then play as normal (friends join you)
			if not Net.host():
				net_status.text = "Couldn't host. See the error log."
				return
		ADDR_JOIN:	# connect, then the host brings you to where they are
			if Net.join(ip_box.text.strip_edges()):
				_waiting = true
			return
	get_tree().change_scene_to_file("res://Home.tscn")


func _on_mode(i: int):
	ip_box.visible = i == ADDR_JOIN


## A Steam invite came in while on this screen.
func _on_invite():
	play_mode.select(STEAM_JOIN)
	_on_mode(STEAM_JOIN)
	if _waiting and play_mode.selected == STEAM_JOIN:	# already picked a class: go
		SteamLink.join_lobby(SteamLink.pending_lobby)
	else:
		net_status.text = "A friend invited you! Pick your class to join them."


func _title(box: VBoxContainer, t: String, size: int):
	var l = Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	box.add_child(l)


func _text(box: VBoxContainer) -> Label:
	var l = Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	box.add_child(l)
	return l
