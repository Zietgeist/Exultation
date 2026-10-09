extends CanvasLayer
## The Chronicle (press J): your story, written as you play. Newest first.
## At each rest (going Home after 5+ minutes out) it offers to add one line of your own.
## The game keeps running while it's open (multiplayer-friendly).

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.6, 0.6, 0.6)
const INK = Color(0.95, 0.88, 0.7)
const MIN_FLOW_FOR_LINE = 5 * 60	# only ask after a real stretch out

var panel: PanelContainer
var list: VBoxContainer
var name_edit: LineEdit
var pet_edit: LineEdit
var title_label: Label
var prompt: PanelContainer
var prompt_edit: LineEdit
var _last_flow := 0.0


func _ready():
	layer = 46
	_build_book()
	_build_prompt()
	Story.chronicle_changed.connect(func(): if panel.visible: _rebuild())
	SessionManager.break_started.connect(_on_break)


func _process(_delta):
	if SessionManager.flow_seconds > 0.0:
		_last_flow = SessionManager.flow_seconds


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_J and (panel.visible or not GameState.ui_open):
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and (panel.visible or prompt.visible):
		if prompt.visible:
			_close_prompt()
		else:
			toggle()
		get_viewport().set_input_as_handled()


func toggle():
	panel.visible = not panel.visible
	GameState.ui_open = panel.visible
	if panel.visible:
		name_edit.text = Story.player_name
		var pet = Zones.player.pet if Zones.player else null
		pet_edit.text = pet.pet_name_given if pet else ""
		_rebuild()


# ---------------- The book ----------------

func _build_book():
	panel = _panel(Vector2(1000, 600), INK)
	add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head = HBoxContainer.new()
	box.add_child(head)
	var title = Label.new()
	title_label = title
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_edit.max_length = 24
	name_edit.tooltip_text = "The name your story (and gear you make) is written under."
	name_edit.text_submitted.connect(func(t): _save_name())
	head.add_child(name_edit)
	var save = Button.new()
	save.text = "Rename"
	save.pressed.connect(_save_name)
	head.add_child(save)
	pet_edit = LineEdit.new()
	pet_edit.placeholder_text = "Name your " + SkinManager.name_of("pet")
	pet_edit.custom_minimum_size = Vector2(170, 0)
	pet_edit.max_length = 20
	pet_edit.tooltip_text = "Your gathering pet's name."
	pet_edit.text_submitted.connect(func(t): _save_pet_name())
	head.add_child(pet_edit)
	var save_pet = Button.new()
	save_pet.text = "Name pet"
	save_pet.pressed.connect(_save_pet_name)
	head.add_child(save_pet)
	var write = Button.new()
	write.text = "Write a line"
	write.tooltip_text = "Add your own line to the Chronicle: what happened, what you want to remember."
	write.pressed.connect(open_prompt)
	head.add_child(write)
	var hint = Label.new()
	hint.text = "Written as you play. Your own lines are in gold.   J or Esc closes."
	hint.add_theme_color_override("font_color", DIM)
	box.add_child(hint)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(968, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	panel.visible = false


func _save_pet_name():
	var pet = Zones.player.pet if Zones.player else null
	if pet:
		pet.set_pet_name(pet_edit.text)
	pet_edit.release_focus()
	_rebuild()


func _save_name():
	Story.set_player_name(name_edit.text)
	name_edit.release_focus()
	_rebuild()


func _rebuild():
	title_label.text = "%s's Chronicle  -  Day %d" % [Story.player_name, Story.day()]
	for c in list.get_children():
		c.queue_free()
	if Story.chronicle.is_empty():
		_line("Nothing written yet. Go make some history.", DIM)
		return
	var last_day = -1
	for i in range(Story.chronicle.size() - 1, -1, -1):
		var e = Story.chronicle[i]
		if e.day != last_day:
			last_day = e.day
			_line("Day %d  (%s)" % [e.day, e.date], GOLD, 18)
		_line(("  \"%s\"" if e.own else "  %s") % e.text, GOLD.lightened(0.3) if e.own else SOFT)


func _line(text: String, color: Color, size := 16):
	var l = Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(940, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	list.add_child(l)


# ---------------- One line at each rest ----------------

func _build_prompt():
	prompt = _panel(Vector2(640, 150), GOLD)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-320, -330)
	add_child(prompt)
	var box = VBoxContainer.new()
	prompt.add_child(box)
	var l = Label.new()
	l.text = "You rest by the fire. One line for your Chronicle? (optional)"
	l.add_theme_color_override("font_color", GOLD)
	box.add_child(l)
	prompt_edit = LineEdit.new()
	prompt_edit.placeholder_text = "What happened out there? What do you want to remember?"
	prompt_edit.max_length = 140
	prompt_edit.text_submitted.connect(func(t): _write())
	box.add_child(prompt_edit)
	var row = HBoxContainer.new()
	box.add_child(row)
	var w = Button.new()
	w.text = "Write it"
	w.pressed.connect(_write)
	row.add_child(w)
	var s = Button.new()
	s.text = "Not now"
	s.pressed.connect(_close_prompt)
	row.add_child(s)
	prompt.visible = false


## Coming Home no longer pops the "write a line" box (it got in the way). Write one any time
## from the Chronicle (J): "Write a line".
func _on_break(_blocks):
	_last_flow = 0.0


func open_prompt():
	if panel.visible:
		toggle()
	prompt_edit.text = ""
	prompt.visible = true
	GameState.ui_open = true
	prompt_edit.grab_focus.call_deferred()


func _write():
	Story.add_own_line(prompt_edit.text)
	_close_prompt()


func _close_prompt():
	prompt.visible = false
	prompt_edit.release_focus()
	GameState.ui_open = panel.visible


func _panel(size: Vector2, border: Color) -> PanelContainer:
	var p = PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = size
	p.position = -size / 2.0
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.05, 0.96)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", style)
	return p
