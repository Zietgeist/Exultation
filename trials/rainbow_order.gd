extends "res://trials/trial_base.gd"
## Color: click the swatches in order. Rainbow order (red to violet), or at higher levels
## sometimes shades of one color from light to dark.

var order: Array = []		# the right order (colors)
var next_index := 0
var shades := false
var picked_row: HBoxContainer
var buttons := []


func title() -> String:
	return "Color Sense"

func instructions() -> String:
	return "Click from LIGHTEST to DARKEST." if shades else "Click in rainbow order: red, orange, yellow, green, blue, violet."

func time_limit() -> float:
	return lerp(22.0, 15.0, difficulty)


func build():
	custom_minimum_size = AREA
	var n = 5 + roundi(difficulty * 3)
	shades = difficulty > 0.5 and rng.randf() < 0.5
	if shades:
		var hue = rng.randf()
		var lo = lerp(0.25, 0.4, difficulty)
		for i in range(n):
			order.append(Color.from_hsv(hue, 0.65, lerp(0.95, lo, float(i) / (n - 1))))
	else:
		for i in range(n):	# red (0.0) to violet (~0.78), small wobble so it's not a ruler
			var h = lerp(0.0, 0.78, float(i) / (n - 1)) + rng.randf_range(-0.01, 0.01)
			order.append(Color.from_hsv(clamp(h, 0.0, 0.8), lerp(0.85, 0.6, difficulty), 0.95))
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 30)
	add_child(v)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var mixed = range(n)
	while mixed == range(n):
		mixed.shuffle()
	for i in mixed:
		var b = Button.new()
		b.custom_minimum_size = Vector2(70, 70)
		var st = StyleBoxFlat.new()
		st.bg_color = order[i]
		st.set_corner_radius_all(8)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, st)
		b.pressed.connect(_on_pick.bind(i, b))
		row.add_child(b)
		buttons.append({i = i, b = b})
	picked_row = HBoxContainer.new()
	picked_row.alignment = BoxContainer.ALIGNMENT_CENTER
	picked_row.add_theme_constant_override("separation", 6)
	picked_row.custom_minimum_size = Vector2(0, 44)
	v.add_child(picked_row)


func _on_pick(i: int, b: Button):
	if is_over():
		return
	if i != next_index:
		b.modulate = Color(1, 1, 1, 0.3)
		finish(false)
		return
	next_index += 1
	b.disabled = true
	b.modulate = Color(1, 1, 1, 0.15)
	var chip = ColorRect.new()
	chip.color = order[i]
	chip.custom_minimum_size = Vector2(40, 40)
	picked_row.add_child(chip)
	if next_index >= order.size():
		finish(true)


func auto_solve():
	for k in range(order.size()):
		for e in buttons:
			if e.i == k:
				_on_pick(e.i, e.b)
