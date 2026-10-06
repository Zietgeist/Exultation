extends "res://trials/trial_base.gd"
## Precision: guide the cursor from the green circle to the gold one without leaving the path.

var points: PackedVector2Array = []
var half_width := 24.0
var started := false
var trail: PackedVector2Array = []


func title() -> String:
	return "Steady Hand"

func instructions() -> String:
	return "Move the cursor onto the green circle, then follow the path to the gold circle. Don't touch the edges."

func time_limit() -> float:
	return lerp(22.0, 13.0, difficulty)


func build():
	custom_minimum_size = AREA
	mouse_filter = Control.MOUSE_FILTER_PASS
	half_width = lerp(26.0, 9.0, difficulty)
	var n = 5 + roundi(difficulty * 4)
	var margin = 50.0
	for i in range(n):
		var x = lerp(margin, AREA.x - margin, float(i) / (n - 1))
		var y = AREA.y / 2.0 if i == 0 or i == n - 1 else rng.randf_range(margin, AREA.y - margin)
		points.append(Vector2(x, y))


func _process(_delta):
	if is_over() or points.is_empty():
		return
	var m = get_local_mouse_position()
	if not started:
		if m.distance_to(points[0]) <= half_width:
			started = true
			trail.append(m)
		queue_redraw()
		return
	if trail.is_empty() or trail[trail.size() - 1].distance_to(m) > 3.0:
		trail.append(m)
	if _distance_to_path(m) > half_width:
		queue_redraw()
		finish(false)
		return
	if m.distance_to(points[points.size() - 1]) <= half_width:
		finish(true)
	queue_redraw()


func _distance_to_path(p: Vector2) -> float:
	var best = INF
	for i in range(points.size() - 1):
		var c = Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
		best = min(best, p.distance_to(c))
	return best


func _draw():
	if points.is_empty():
		return
	draw_polyline(points, Color(0.25, 0.23, 0.3), half_width * 2.0, true)
	for p in points:
		draw_circle(p, half_width, Color(0.25, 0.23, 0.3))
	draw_polyline(points, Color(0.45, 0.42, 0.5), 1.5, true)
	draw_circle(points[0], half_width, Color(0.3, 0.85, 0.4))
	draw_circle(points[points.size() - 1], half_width, GOLD)
	if trail.size() > 1:
		draw_polyline(trail, Color(1, 1, 1, 0.8), 2.0, true)


func auto_solve():
	finish(true)
