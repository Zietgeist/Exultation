extends CanvasLayer
## The window every shrine trial runs in: name, one line of instructions, a timer bar, the trial, the result.
## The game keeps running (multiplayer), but you're warded while it's open: nothing can hurt you,
## and your character stands still so typing doesn't walk you around. Esc gives up (counts as a fail).

const GOLD = Color(1.0, 0.85, 0.3)
const RESULT_TIME = 1.4

var trial = null
var ability := ""
var time_left := 0.0
var total_time := 1.0
var bar: ProgressBar
var result: Label
var _on_done: Callable
var _closing := false


func start(id: String, difficulty: float, on_done: Callable):
	layer = 60
	ability = id
	_on_done = on_done
	GameState.ui_open = true
	GameState.input_locked = true
	var me = get_tree().get_first_node_in_group("player")
	if me:
		me.warded = true

	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.09, 0.97)
	style.border_color = Trials.TYPES[id].color
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	trial = load(Trials.TYPES[id].script).new()
	trial.difficulty = difficulty
	trial.rng.randomize()
	trial.build()
	trial.done.connect(_on_trial_done)

	var head = Label.new()
	head.text = "%s  -  %s" % [Trials.ability_name(id), trial.title()]
	head.add_theme_font_size_override("font_size", 28)
	head.add_theme_color_override("font_color", Trials.TYPES[id].color)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var how = Label.new()
	how.text = trial.instructions()
	how.add_theme_font_size_override("font_size", 18)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(trial.AREA.x, 0)
	v.add_child(how)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = 1.0
	bar.value = 1.0
	var fill = StyleBoxFlat.new()
	fill.bg_color = Trials.TYPES[id].color
	bar.add_theme_stylebox_override("fill", fill)
	v.add_child(bar)
	v.add_child(trial)
	result = Label.new()
	result.add_theme_font_size_override("font_size", 26)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.text = "Esc: give up"
	result.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	v.add_child(result)

	total_time = trial.time_limit()
	time_left = total_time


func _process(delta):
	if trial == null or trial.is_over():
		return
	time_left -= delta
	bar.value = max(time_left, 0.0) / total_time
	if time_left <= 0.0:
		trial.finish(false)


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and trial and not trial.is_over():
		get_viewport().set_input_as_handled()
		trial.finish(false)


func _on_trial_done(passed: bool):
	if _closing:
		return
	_closing = true
	Trials.record(ability, passed)
	result.text = "Passed!" if passed else ("Out of time" if time_left <= 0.0 else "Not this time")
	result.add_theme_color_override("font_color", GOLD if passed else Color(1, 0.5, 0.45))
	await get_tree().create_timer(RESULT_TIME).timeout
	GameState.ui_open = false
	GameState.input_locked = false
	var me = get_tree().get_first_node_in_group("player")
	if me:
		me.warded = false
		me.invulnerable_time = max(me.invulnerable_time, 1.0)	# a moment to get your bearings
	queue_free()
	if _on_done.is_valid():
		_on_done.call(passed)
