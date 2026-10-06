extends Control
## Start screen: pick a WORLD (skin), a RACE (from that world) and a CLASS.
## The world changes names, colors, terrain looks and which races you can play.
## The race decides which gear slots you have (an Ent has no boots, but twenty rings).

const GOLD = Color(1.0, 0.85, 0.3)

var world_pick: OptionButton
var world_about: Label
var race_pick: OptionButton
var race_about: Label
var class_buttons = []
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

	_title(box, "Class", 22)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in range(3):
		var b = Button.new()
		b.custom_minimum_size = Vector2(200, 56)
		b.pressed.connect(_start.bind(i))
		row.add_child(b)
		class_buttons.append(b)
	_text(box).text = "DPS hits hard  ·  Tank takes hits  ·  Healer keeps going"

	_refresh()


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
	for i in range(3):
		class_buttons[i].text = "%s\n(%s)" % [SkinManager.class_label(i), ["DPS", "Tank", "Healer"][i]]


func _start(class_index: int):
	GameState.player_class = class_index
	Crafting.ensure_slots()
	get_tree().change_scene_to_file("res://Home.tscn")


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
