extends "res://trials/trial_base.gd"
## Color: click the swatches in order. Rainbow order (red to violet), or at higher levels
## sometimes shades of one color from light to dark.

var order: Array = []		# the right order (colors)
var names: Array = []		# the name of each color in order, for the instructions
var next_index := 0
var shades := false
var picked_row: HBoxContainer
var buttons := []


func title() -> String:
	return "Color Sense"

func instructions() -> String:
	if shades:
		return "Click from LIGHTEST to DARKEST."
	# Name every color shown (harder trials add cyan / yellow-green), so nothing looks like a surprise.
	return "Click in rainbow order: %s." % ", ".join(names)

func time_limit() -> float:
	return lerp(22.0, 15.0, difficulty)


func build():
	custom_minimum_size = AREA
	shades = difficulty > 0.5 and rng.randf() < 0.5
	var n = 5 + roundi(difficulty * 3)
	if shades:
		var hue = rng.randf()
		var lo = lerp(0.25, 0.4, difficulty)
		for i in range(n):
			order.append(Color.from_hsv(hue, 0.65, lerp(0.95, lo, float(i) / (n - 1))))
	else:
		# Always the six named colors (red, orange, yellow, green, blue, violet), so the
		# instructions are true; harder trials add in-between shades (yellow-green, cyan).
		var hues = [0.0, 0.075, 0.15, 0.33, 0.62, 0.78]
		var hue_names = {0.0: "red", 0.075: "orange", 0.15: "yellow", 0.24: "yellow-green", 0.33: "green", 0.5: "cyan", 0.62: "blue", 0.78: "violet"}
		var extras = [0.5, 0.24]
		for k in range(roundi(difficulty * 2)):
			hues.append(extras[k])
		hues.sort()
		for h in hues:	# a small wobble so it's not a ruler
			names.append(hue_names[h])
			order.append(Color.from_hsv(clamp(h + rng.randf_range(-0.006, 0.006), 0.0, 0.8), lerp(0.9, 0.7, difficulty), 0.95))
	var v = VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 30)
	add_child(v)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var mixed = range(order.size())
	while mixed == range(order.size()):
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
