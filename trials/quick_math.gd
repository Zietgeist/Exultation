extends "res://trials/trial_base.gd"
## Numbers: answer three quick sums in a row. Starts with easy adding, grows into times tables and two steps.

const QUESTIONS = 3
var asked := 0
var answer := 0
var question_label: Label
var box: LineEdit
var progress: Label


func title() -> String:
	return "Quick Count"

func instructions() -> String:
	return "Type each answer and press Enter. Three right in a row passes."

func time_limit() -> float:
	return lerp(30.0, 20.0, difficulty)


func build():
	custom_minimum_size = AREA
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(v)
	question_label = make_label("", 44, GOLD)
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(question_label)
	box = LineEdit.new()
	box.custom_minimum_size = Vector2(220, 48)
	box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_theme_font_size_override("font_size", 30)
	box.text_submitted.connect(_on_submit)
	var c = CenterContainer.new()
	c.add_child(box)
	v.add_child(c)
	progress = make_label("", 18)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(progress)
	_next()
	box.grab_focus.call_deferred()


func _next():
	var q = _make_question()
	question_label.text = q[0] + " = ?"
	answer = q[1]
	box.text = ""
	progress.text = "%d of %d" % [asked + 1, QUESTIONS]


## [text, answer], harder as difficulty rises.
func _make_question() -> Array:
	var d = difficulty
	if d < 0.25:
		var a = rng.randi_range(1, 12)
		var b = rng.randi_range(1, 12)
		return ["%d + %d" % [a, b], a + b]
	if d < 0.5:
		var a = rng.randi_range(10, 60)
		var b = rng.randi_range(5, 39)
		if rng.randf() < 0.5:
			return ["%d + %d" % [a, b], a + b]
		return ["%d - %d" % [a + b, b], a]
	if d < 0.75:
		var a = rng.randi_range(2, 12)
		var b = rng.randi_range(2, 12)
		return ["%d x %d" % [a, b], a * b]
	var a = rng.randi_range(3, 12)
	var b = rng.randi_range(3, 12)
	var c = rng.randi_range(2, 30)
	return ["%d x %d + %d" % [a, b, c], a * b + c]


func _on_submit(text: String):
	if is_over():
		return
	if not text.strip_edges().is_valid_int() or int(text) != answer:
		question_label.text = "%s  (it was %d)" % [question_label.text.replace("?", ""), answer]
		finish(false)
		return
	asked += 1
	if asked >= QUESTIONS:
		finish(true)
	else:
		_next()


func auto_solve():
	while not is_over():
		_on_submit(str(answer))
