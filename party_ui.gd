extends CanvasLayer
## Online party panel: who's in the party and where they are, the "Follow / Stay" choice when
## someone in your zone goes through a gate, and P to rejoin the party.
## (Made by the HUD. Hidden when playing solo.)

const GOLD = Color(1.0, 0.85, 0.3)
const FOLLOW_TIME = 15.0

var list: Label
var prompt: PanelContainer
var prompt_text: Label
var _go: Callable
var _prompt_left := 0.0


func _ready():
	layer = 40
	list = Label.new()
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	list.offset_left = -360
	list.offset_top = 8
	list.offset_right = -10
	list.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	list.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	list.add_theme_color_override("font_outline_color", Color.BLACK)
	list.add_theme_constant_override("outline_size", 6)
	add_child(list)

	prompt = PanelContainer.new()
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt.offset_bottom = -110
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.06, 0.09, 0.92)
	st.border_color = GOLD
	st.set_border_width_all(2)
	st.set_content_margin_all(12)
	prompt.add_theme_stylebox_override("panel", st)
	var v = VBoxContainer.new()
	prompt.add_child(v)
	prompt_text = Label.new()
	prompt_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_text.add_theme_font_size_override("font_size", 22)
	prompt_text.add_theme_color_override("font_color", GOLD)
	v.add_child(prompt_text)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var yes = Button.new()
	yes.text = "Follow (Y)"
	yes.pressed.connect(_follow)
	row.add_child(yes)
	var no = Button.new()
	no.text = "Stay (N)"
	no.pressed.connect(_stay)
	row.add_child(no)
	prompt.visible = false
	add_child(prompt)
	Net.follow_offer.connect(_on_offer)


func _on_offer(text: String, go: Callable):
	_go = go
	prompt_text.text = text + ". Follow?"
	_prompt_left = FOLLOW_TIME
	prompt.visible = true


func _follow():
	prompt.visible = false
	if _go.is_valid():
		_go.call()


func _stay():
	prompt.visible = false


func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo) or GameState.ui_open:
		return
	if prompt.visible and event.keycode == KEY_Y:
		_follow()
		get_viewport().set_input_as_handled()
	elif prompt.visible and event.keycode == KEY_N:
		_stay()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_P and Net.is_online():
		Net.rejoin()
		get_viewport().set_input_as_handled()


func _process(delta):
	if prompt.visible:
		_prompt_left -= delta
		if _prompt_left <= 0.0:
			prompt.visible = false
	if not Net.is_online() or Net.roster.is_empty():
		list.text = ""
		return
	var lines = ["Party"]
	var apart = false
	for id in Net.roster:
		var r = Net.roster[id]
		var where = GameState.ZONE_NAMES.get(r.p, "")
		if where == "":
			where = SkinManager.name_of("trial_arena") if r.p == Trials.ARENA else r.p.get_file().get_basename()
		var me = id == Net.my_id()
		lines.append("%s%s - %s" % [Classes.label(r.c), " (you)" if me else "", where])
		if not me and r.k != Zones.local_key():
			apart = true
	if apart:
		lines.append("P: rejoin the party")
	list.text = "\n".join(lines)
