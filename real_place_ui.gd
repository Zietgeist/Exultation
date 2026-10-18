extends CanvasLayer
## The address window for a Real Place (opened by real_place_gate.gd at Home).
## Downloads the map (real_map.gd), runs the off-limits check, then travels to RealZone.tscn.
## PRIVACY: the address is never saved, logged or sent anywhere except the address search.
## Solo only for now: online, friends' games would be sent the place.

const REAL_MAP = preload("res://real_map.gd")
const REAL_ZONE = "res://RealZone.tscn"
const GOLD = Color(1.0, 0.85, 0.3)

var back_pos := Vector3(0, 1, 8)	# where you come back at Home
var rm
var input: LineEdit
var go: Button
var status: Label
var busy := false


func _ready():
	layer = 60
	rm = REAL_MAP.new()
	add_child(rm)
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 0)
	panel.position = Vector2(-300, -120)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.08, 0.96)
	style.border_color = Color(0.3, 0.9, 1.0)
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title = Label.new()
	title.text = "Real Place"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var about = Label.new()
	about.text = "Fight in a real place. Type an address, or latitude, longitude.\nYour address is never saved or shared. Solo only for now."
	about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(about)
	var row = HBoxContainer.new()
	box.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "Address, or latitude, longitude"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_t): _go())
	row.add_child(input)
	go = Button.new()
	go.text = "Go"
	go.pressed.connect(_go)
	row.add_child(go)
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	row.add_child(cancel)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(560, 0)
	status.add_theme_color_override("font_color", GOLD)
	box.add_child(status)
	var credit = Label.new()
	credit.text = "Map data (c) OpenStreetMap contributors  |  Search by LocationIQ.com"
	credit.add_theme_font_size_override("font_size", 12)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(credit)
	rm.status.connect(func(t): status.text = t)
	GameState.ui_open = true
	input.grab_focus.call_deferred()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close():
	GameState.ui_open = false
	queue_free()


func _go():
	if busy or input.text.strip_edges() == "":
		return
	if Net.is_online():
		status.text = "Real places are solo for now. Leave the party first."
		return
	busy = true
	go.disabled = true
	var data = await rm.load_place(input.text)
	if not is_instance_valid(self):
		return
	busy = false
	go.disabled = false
	if data.is_empty():
		return	# the status line says why
	data.erase("name")	# the full address: not needed in the zone, so it never goes further
	var spawn = rm.free_spot(data)
	var key = "%s#%d" % [REAL_ZONE, randi()]	# a one-off copy, like a Trial Ground (not remembered)
	var info = {solo = true, data = data, spawn = spawn, back_scene = "res://Home.tscn", back_pos = back_pos}
	input.text = ""
	close()
	Net.go(REAL_ZONE, key, spawn, info)
