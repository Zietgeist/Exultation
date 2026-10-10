extends CanvasLayer
## The Survivor at a taken stronghold: asks you to recruit guards (talk to it with G or a click).
## The job itself lives in Landmarks (recruit, parley, finish_recruit).

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)

var lm = null		# the stronghold (lm_stronghold.gd)
var panel: PanelContainer
var box: VBoxContainer


func _ready():
	layer = 46
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.position = Vector2(-260, -150)
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.06, 0.08, 0.96)
	st.border_color = Color(0.75, 0.65, 0.5)
	st.set_border_width_all(2)
	st.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", st)
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	panel.visible = false


func _unhandled_input(event):
	if panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


## npc.gd calls this when you talk to the Survivor.
func open(_shop: String, _who):
	_rebuild()
	panel.visible = true
	GameState.ui_open = true


func close():
	panel.visible = false
	GameState.ui_open = false


func _rebuild():
	for c in box.get_children():
		c.queue_free()
	var path = lm.zone_path
	var id = lm.info.id
	var guards = int(lm.state().get("guards", 0))
	var job = Landmarks.recruit
	_text("Survivor  -  %s" % lm.info.name, GOLD, 22)
	if job.is_empty():
		_text(("We took the place back, but there's nobody left to hold it. Some of them out there are sick of fighting. Talk them into guarding these walls?" if guards == 0
			else "%d guards keep watch now. A few more wouldn't hurt." % guards), SOFT, 16)
		_text("Wear this disguise: they'll take you for one of their own (no fighting, auto-attack off). Press V (Parley) next to a Trash or Thug. About half will agree and come here. The rest see through it and attack. Fight them off, then press V to put the disguise back on.", Color(0.7, 0.85, 1.0), 14)
		_button("Take the job: recruit %d" % Landmarks.RECRUIT_NEED, func():
			Landmarks.start_recruit(path, id, lm.info.name)
			close())
	elif job.path != path or job.id != id:
		_text("You're already recruiting for %s (%d / %d)." % [job.name, job.have, job.need], SOFT, 16)
	elif job.have < job.need:
		_text("Recruited so far: %d / %d. Keep talking to them (V)." % [job.have, job.need], SOFT, 16)
	else:
		_text("You brought %d of them! I'll put them on the walls." % job.have, SOFT, 16)
		_button("Bring them in", func():
			Landmarks.finish_recruit()
			_rebuild())
	_button("Close", close)


func _text(t: String, c: Color, size: int):
	var l = Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	l.add_theme_color_override("font_color", c)
	l.add_theme_font_size_override("font_size", size)
	box.add_child(l)


func _button(t: String, f: Callable):
	var b = Button.new()
	b.text = t
	b.pressed.connect(f)
	box.add_child(b)
