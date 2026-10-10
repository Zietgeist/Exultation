extends CanvasLayer
## The pet window (press K). How your pet is doing and how it's growing.
## Hover any bar's name for what it means. Feed it and name it from here.
## The game keeps running while it's open (multiplayer), only your attack keys pause.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.65, 0.65, 0.65)

var panel: PanelContainer
var box: VBoxContainer
var name_edit: LineEdit
var _refresh := 0.0
var _bars := {}		# name -> [ProgressBar, value Label] (updated in place, so tooltips stay put)
var _lines := {}		# id -> Label


func _ready():
	layer = 45
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 560)
	panel.position = Vector2(-280, -280)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.96)
	style.border_color = Color(0.55, 0.9, 1.0)
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var outer = VBoxContainer.new()
	panel.add_child(outer)
	box = VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(box)
	# Name and feed (built once, so typing isn't interrupted by the refresh)
	var row = HBoxContainer.new()
	outer.add_child(row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Give it a name"
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.text_submitted.connect(func(_t): _rename())
	row.add_child(name_edit)
	var nb = Button.new()
	nb.text = "Name it"
	nb.pressed.connect(_rename)
	row.add_child(nb)
	var fb = Button.new()
	fb.text = "Feed a herb (T)"
	fb.tooltip_text = "Shares one herb from your satchel. You need to be close to your pet."
	fb.pressed.connect(_feed)
	row.add_child(fb)
	var tb = Button.new()
	tb.text = "Give a tonic"
	tb.tooltip_text = "A refined herb (made at the Chemist). Much better than a raw one:\nfully fed and calm, a big Bond boost, less skittish, healed,\nand WELL FED for a while: 25% faster, gathers quicker, +20% health.\nBetter tonics last longer. You need to be close to your pet."
	tb.pressed.connect(_feed.bind(true))
	row.add_child(tb)
	var close = Button.new()
	close.text = "Close (K)"
	close.pressed.connect(toggle)
	row.add_child(close)
	visible = false


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_K and (visible or not GameState.ui_open):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and visible:
		toggle()
		get_viewport().set_input_as_handled()


func toggle():
	visible = not visible
	GameState.ui_open = visible
	if visible:
		var pet = _pet()
		name_edit.text = pet.pet_name_given if pet else ""
		_rebuild()


func _pet():
	var p = Zones.player
	return p.pet if p and "pet" in p and is_instance_valid(p.pet) else null


func _process(delta):
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		_update()


func _rename():
	var pet = _pet()
	if pet:
		pet.set_pet_name(name_edit.text)
		_rebuild()


func _feed(tonic := false):
	var pet = _pet()
	if pet == null:
		return
	if not pet.alive():
		GameState.notify("%s is knocked out. It'll be back soon." % pet.pet_name())
	elif pet._flat(pet.global_position - Zones.player.global_position).length() > pet.FEED_RANGE:
		GameState.notify("Get closer to %s to feed it." % pet.pet_name())
	elif tonic:
		pet.feed_tonic()
	else:
		pet.feed()
	_rebuild()


func _rebuild():
	for c in box.get_children():
		c.queue_free()
	_bars.clear()
	_lines.clear()
	var pet = _pet()
	if pet == null:
		_text("You don't have a pet with you.", SOFT)
		return
	_lines.title = _title(pet.full_name())
	_lines.mood = _text("", Color(0.7, 0.95, 1.0))
	_title("Right now", 18)
	_bar("Health", 0.0 if not pet.alive() else 100.0 * pet.health / pet.MAX_HEALTH, Color(0.3, 0.9, 0.4),
		"Heals by itself once it's been calm for a few seconds.")
	_bar("Food", pet.food(), Color(1.0, 0.6, 0.2),
		"Goes down while you're out (empty after about one flow block). Feed it a herb (T near it).\nA hungry pet slowly drifts away (Bond goes down).")
	_bar("Stress", pet.stress, Color(0.9, 0.4, 0.4),
		"Goes up when it's hit or enemies are near. Comes down with calm time, much faster when you're close.\nToo much at once and it's overwhelmed: it hides behind you until it settles.")
	_title("Growing", 18)
	_bar("Bond", pet.bond, Color(0.9, 0.5, 0.9),
		"Grows when you feed it, rest at Home together, and protect it.\nHigh Bond: faster, gathers from farther and quicker. At 80+ it gathers two things at once.")
	_bar("Sturdy", pet.sturdy, Color(0.6, 0.6, 0.9),
		"Grows when it gets through scares with you close by.\nSturdy: more health, but slower. (Low = nimble.)")
	_bar("Skittish", pet.skittish, Color(0.8, 0.8, 0.4),
		"Being overwhelmed again and again (worse when you're far away) makes it panic sooner.\nCalm time near you and resting at Home heal it.")
	_title("What it can do", 18)
	_lines.can = _text("", SOFT)
	_text("It stays away from nodes where an enemy could notice it.", DIM)
	_title("Together", 18)
	_lines.record = _text("", DIM)
	_update()


## Fresh numbers, twice a second.
func _update():
	var pet = _pet()
	if pet == null or _bars.is_empty():
		return
	_lines.title.text = pet.full_name()
	_lines.mood.text = "Mood: %s" % pet.mood() + ("   WELL FED %d:%02d" % [int(pet.well_fed) / 60, int(pet.well_fed) % 60] if pet.well_fed > 0.0 else "") + ("   (knocked out: back in %ds)" % ceili(pet.knocked_out) if not pet.alive() else "")
	_set_bar("Health", 0.0 if not pet.alive() else 100.0 * pet.health / pet.MAX_HEALTH)
	_set_bar("Food", pet.food())
	_set_bar("Stress", pet.stress)
	_set_bar("Bond", pet.bond)
	_set_bar("Sturdy", pet.sturdy)
	_set_bar("Skittish", pet.skittish)
	_lines.can.text = "Speed %.1f  ·  gathers within %d of you  ·  %.1fs per gather%s" % [pet.speed(), pet.gather_radius(), pet.gather_time(),
		"  ·  two at once" if pet.double_gather() else ""]
	_lines.record.text = "Gathered %d  ·  fed %d times  ·  protected %d times  ·  knocked out %d times" % [
		pet.record.gathered, pet.record.fed, pet.record.guarded, pet.record.knockouts]


func _set_bar(bar_name: String, value: float):
	_bars[bar_name][0].value = value
	_bars[bar_name][1].text = "%d" % value


# ---------------- helpers ----------------

func _title(t: String, size := 24):
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GOLD)
	box.add_child(l)
	return l


func _text(t: String, color: Color):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func _bar(label: String, value: float, color: Color, tip: String):
	var row = HBoxContainer.new()
	box.add_child(row)
	var l = Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(80, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP	# so the tooltip shows
	row.add_child(l)
	var b = ProgressBar.new()
	b.max_value = 100
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(300, 16)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = tip
	var fill = StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	row.add_child(b)
	var v = Label.new()
	v.text = "%d" % value
	v.add_theme_color_override("font_color", DIM)
	row.add_child(v)
	_bars[label] = [b, v]
