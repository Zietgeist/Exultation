extends Control
## Start screen. Left: your saved characters (Account) - Play one, or delete it - and how to play
## (solo / host / join). Right: make a NEW character: a name, a WORLD (skin), a RACE and a CLASS.
## Each character keeps its own gold, gear, pet and story. A different race or class = a new character.
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
var party_row: HBoxContainer	# hosting: which party's adventure to play
var party_pick: OptionButton
var party_name: LineEdit
var _parties = []
var net_status: Label
var _waiting = false
const MODES = ["Solo", "Host on Steam (friends)", "Join a Steam friend", "Host by address", "Join by address"]
const SOLO = 0
const STEAM_HOST = 1
const STEAM_JOIN = 2
const ADDR_HOST = 3
const ADDR_JOIN = 4
var _world_ids = []
var name_edit: LineEdit
var _char_list: VBoxContainer
var _confirm: ConfirmationDialog


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
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	center.add_child(outer)
	_title(outer, "EXULTATION", 44)
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	outer.add_child(cols)
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(460, 0)
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	var box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 10)
	cols.add_child(box)
	var right = box

	# Left: your characters
	_title(left, "Your characters", 26)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_char_list = VBoxContainer.new()
	_char_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_char_list)
	_confirm = ConfirmationDialog.new()
	add_child(_confirm)

	# Right: a new character
	_title(box, "New character", 26)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Name your character"
	name_edit.max_length = 24
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_edit)
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

	# Online co-op: host a game, or join a friend's (left side, under your characters)
	box = left
	_title(box, "How to play", 22)
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
	# Hosting: play a saved party (any member can host it) or start a new one
	party_row = HBoxContainer.new()
	party_row.alignment = BoxContainer.ALIGNMENT_CENTER
	party_row.add_theme_constant_override("separation", 12)
	box.add_child(party_row)
	var pl = Label.new()
	pl.text = "Party:"
	party_row.add_child(pl)
	party_pick = OptionButton.new()
	party_pick.add_item("New party")
	_parties = Party.list_saved()
	for p in _parties:
		party_pick.add_item(Party.summary(p))
	party_pick.tooltip_text = "Your party's progress is saved. Any member can host it next time and carry on."
	party_pick.item_selected.connect(func(i): party_name.visible = i == 0)
	party_row.add_child(party_pick)
	party_name = LineEdit.new()
	party_name.placeholder_text = "Name your party"
	party_name.custom_minimum_size = Vector2(220, 0)
	party_name.max_length = 32
	party_row.add_child(party_name)
	party_row.visible = false
	net_status = _text(box)
	if not SteamLink.available():
		net_status.text = "Steam: " + SteamLink.why_not()
	Net.status.connect(func(t): net_status.text = t)
	SteamLink.invite_waiting.connect(_on_invite)
	SteamLink.lobby_ready.connect(func(): Zones.start("res://Home.tscn"))
	if SteamLink.pending_lobby != 0:
		_on_invite.call_deferred()

	box = right
	_title(box, "Class  (click one to make this character and start)", 18)
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
	_fill_characters()
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
		elif arg.begins_with("--party="):	# test: pick (or make) a party by name
			var want = arg.get_slice("=", 1)
			var found = _parties.map(func(p): return p.name).find(want)
			party_pick.select(found + 1 if found != -1 else 0)
			party_name.text = want
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


## Your saved characters, newest played first.
func _fill_characters():
	for c in _char_list.get_children():
		c.queue_free()
	var chars = Account.list()
	if chars.is_empty():
		var l = _text(_char_list)
		l.text = "No characters yet. Make one on the right."
	for c in chars:
		var card = PanelContainer.new()
		var st = StyleBoxFlat.new()
		st.bg_color = Color(0.12, 0.11, 0.14)
		st.border_color = GOLD.darkened(0.4)
		st.border_width_left = 3
		st.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", st)
		_char_list.add_child(card)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var skin = SkinManager.skins.get(c.skin, {})
		var race_name = c.race
		for r in skin.get("races", []):
			if r.get("id", "") == c.race:
				race_name = r.get("name", c.race)
		var title = Label.new()
		title.text = "%s  ·  %s %s" % [c.name, race_name, Classes.label(Classes.normalize(c["class"]))]
		title.add_theme_color_override("font_color", GOLD)
		title.add_theme_font_size_override("font_size", 17)
		info.add_child(title)
		var sub = Label.new()
		sub.text = "%s  ·  %s" % [skin.get("name", c.skin), Account.summary(c)]
		sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		sub.add_theme_font_size_override("font_size", 13)
		info.add_child(sub)
		var play = Button.new()
		play.text = "Play"
		play.custom_minimum_size = Vector2(70, 0)
		play.pressed.connect(_play.bind(c.id))
		row.add_child(play)
		var del = Button.new()
		del.text = "X"
		del.tooltip_text = "Delete this character"
		del.pressed.connect(_ask_delete.bind(c))
		row.add_child(del)


func _ask_delete(c: Dictionary):
	_confirm.dialog_text = "Delete %s for good?\nTheir gold, gear, pet and story will be gone." % c.name
	for con in _confirm.confirmed.get_connections():
		_confirm.confirmed.disconnect(con.callable)
	_confirm.confirmed.connect(func(): Account.remove(c.id); _fill_characters())
	_confirm.popup_centered()


## Play a saved character.
func _play(char_id: String):
	if _waiting:
		return
	Account.select(char_id)
	_launch()


## Make a new character from the right side (name, world, race, this class) and start.
func _start(class_id: String):
	if _waiting:
		return
	var id = Account.create(name_edit.text, SkinManager.current_id, SkinManager.current_race, class_id)
	Account.select(id)
	_launch()


func _launch():
	Crafting.ensure_slots()
	match play_mode.selected:
		STEAM_HOST:	# make a Steam lobby; the game starts when it's ready (lobby_ready)
			_waiting = true
			_begin_party()
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
			_begin_party()
		ADDR_JOIN:	# connect, then the host brings you to where they are
			if Net.join(ip_box.text.strip_edges()):
				_waiting = true
			return
	Zones.start(Account.start_scene())	# back where this character left off


func _on_mode(i: int):
	ip_box.visible = i == ADDR_JOIN
	party_row.visible = i == ADDR_HOST or i == STEAM_HOST


## Hosting: start the chosen party (or a new one).
func _begin_party():
	var i = party_pick.selected
	Party.begin(_parties[i - 1] if i > 0 else Party.new_party(party_name.text))


## A Steam invite came in while on this screen.
func _on_invite():
	play_mode.select(STEAM_JOIN)
	_on_mode(STEAM_JOIN)
	if _waiting and play_mode.selected == STEAM_JOIN:	# already picked a class: go
		SteamLink.join_lobby(SteamLink.pending_lobby)
	else:
		net_status.text = "A friend invited you! Play a character (or make one) to join them."


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
