extends "res://trials/trial_base.gd"
## Logic: turn every light off. Clicking a light flips it AND the ones next to it (up, down, left, right).

var grid := 3	# lights per side
var lights := []	# bools, row by row
var buttons := []
var solution := []	# the presses that made the puzzle (pressing them again solves it)


func title() -> String:
	return "Lamplighter"

func instructions() -> String:
	return "Turn ALL the lights off. A click flips that light and its neighbors."

func time_limit() -> float:
	return lerp(35.0, 28.0, difficulty)


func build():
	custom_minimum_size = AREA
	grid = 3 if difficulty < 0.6 else 4
	lights.resize(grid * grid)
	lights.fill(false)
	var presses = 2 + roundi(difficulty * 4)
	var cells = range(grid * grid)
	cells.shuffle()
	solution = cells.slice(0, presses)
	for c in solution:
		_flip(c)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box = GridContainer.new()
	box.columns = grid
	box.add_theme_constant_override("h_separation", 8)
	box.add_theme_constant_override("v_separation", 8)
	center.add_child(box)
	var cell_size = 300.0 / grid
	for i in range(grid * grid):
		var b = Button.new()
		b.custom_minimum_size = Vector2(cell_size, cell_size)
		b.pressed.connect(_on_press.bind(i))
		box.add_child(b)
		buttons.append(b)
	_paint()


func _flip(c: int):
	var r = c / grid
	var col = c % grid
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var rr = r + d.y
		var cc = col + d.x
		if rr >= 0 and rr < grid and cc >= 0 and cc < grid:
			lights[rr * grid + cc] = not lights[rr * grid + cc]


func _on_press(c: int):
	if is_over():
		return
	_flip(c)
	_paint()
	if not lights.has(true):
		finish(true)


func _paint():
	for i in range(buttons.size()):
		var st = StyleBoxFlat.new()
		st.bg_color = Color(1.0, 0.85, 0.35) if lights[i] else Color(0.16, 0.15, 0.2)
		st.set_corner_radius_all(10)
		for state in ["normal", "hover", "pressed", "focus"]:
			buttons[i].add_theme_stylebox_override(state, st)


func auto_solve():
	for c in solution:
		_on_press(c)
