extends CanvasLayer
## The fast-travel list (opened by stepping onto a waystation). Pick where to go.
## The game keeps running while it's open (multiplayer-friendly). Esc closes.

const GOLD = Color(1.0, 0.85, 0.3)
const SOFT = Color(0.85, 0.85, 0.85)
const DIM = Color(0.6, 0.6, 0.6)
const RIDE = {"portal": "You step through the ring...", "rail": "The train rattles along the elevated line...", "tube": "Whoosh! The vacuum tube carries you off..."}

var panel: PanelContainer
var list: VBoxContainer
var fade: ColorRect


func _ready():
	layer = 47
	add_to_group("travel_ui")
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 520)
	panel.position = Vector2(-260, -260)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.96)
	style.border_color = Color(0.5, 0.9, 1.0)
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box = VBoxContainer.new()
	panel.add_child(box)
	var title = Label.new()
	title.name = "Title"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	var hint = Label.new()
	hint.text = "Where to? (Esc to stay.) Find more stops by walking near them."
	hint.add_theme_color_override("font_color", DIM)
	box.add_child(hint)
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(488, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	panel.visible = false
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


func _unhandled_input(event):
	if panel.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func open(here_path: String, here_id: String):
	for c in list.get_children():
		c.queue_free()
	(panel.get_child(0).get_child(0) as Label).text = "%s - fast travel" % Travel.station_name()
	var last_zone = ""
	for d in Travel.destinations():
		if d.path == here_path and d.id == here_id:
			continue
		var zname = GameState.ZONE_NAMES.get(d.path, d.path)
		if zname != last_zone:
			last_zone = zname
			var h = Label.new()
			h.text = zname
			h.add_theme_color_override("font_color", GOLD)
			list.add_child(h)
		var b = Button.new()
		b.text = "  " + d.label
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_go.bind(d))
		list.add_child(b)
	if list.get_child_count() == 0:
		var l = Label.new()
		l.text = "No other stops found yet."
		l.add_theme_color_override("font_color", DIM)
		list.add_child(l)
	var stay = Button.new()
	stay.text = "Stay here"
	stay.pressed.connect(close)
	list.add_child(stay)
	panel.visible = true
	GameState.ui_open = true


func close():
	panel.visible = false
	GameState.ui_open = false


func _go(d: Dictionary):
	close()
	GameState.notify(RIDE.get(Travel.style(), "Off you go..."))
	var t = create_tween()
	t.tween_property(fade, "color:a", 1.0, 0.35)
	t.tween_callback(func(): Travel.go_to(d))
	t.tween_interval(0.4)
	t.tween_property(fade, "color:a", 0.0, 0.5)
