extends "res://lm_base.gd"
## Neutral town (Free Town / Safe Zone / Trade Hub): low walls with four gates, houses, and a square.
## No fighting inside: enemies won't follow you in (enemy.gd asks Landmarks.in_safe).
## In the square: a Trader (rare materials for banked gold), a Quest Board (jobs that pay gold) and
## an Inn (step in: bank your gold and rest, like at Home). Has a fast-travel stop.

const HALF = 40.0
var ui = null


func title_height() -> float:
	return 14.0


func build():
	var style = SkinManager.props_style()
	var wall_c = {"zombie": Color(0.45, 0.42, 0.38), "scifi": Color(0.5, 0.55, 0.62)}.get(style, Color(0.55, 0.5, 0.42))
	var roof_c = {"zombie": Color(0.35, 0.25, 0.2), "scifi": Color(0.3, 0.7, 0.85)}.get(style, Color(0.5, 0.25, 0.18))
	var wm = mat("lm_town_wall", wall_c)
	var rm = mat("lm_town_roof", roof_c)
	var h = HALF
	var gap = [{at = 0.5, width = 12.0}]
	wall(Vector3(-h, 0, -h), Vector3(h, 0, -h), 2.5, 1.2, wm, gap)
	wall(Vector3(-h, 0, h), Vector3(h, 0, h), 2.5, 1.2, wm, gap)
	wall(Vector3(-h, 0, -h), Vector3(-h, 0, h), 2.5, 1.2, wm, gap)
	wall(Vector3(h, 0, -h), Vector3(h, 0, h), 2.5, 1.2, wm, gap)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(info.name)
	for spot in [Vector3(-26, 0, -26), Vector3(26, 0, -26), Vector3(-26, 0, 26), Vector3(26, 0, 26),
			Vector3(-27, 0, 0), Vector3(27, 0, 0), Vector3(0, 0, -27)]:
		house(spot, Vector3(rng.randf_range(8, 11), rng.randf_range(4, 6), rng.randf_range(7, 9)), wm, rm)
	# The square
	ui = load("res://town_ui.gd").new()
	add_child(ui)
	var f = facing()
	var right = Vector3(f.z, 0, -f.x)
	npc(right * 9.0 - f * 4.0, Landmarks.word("trader"), "rare materials", "trader", ui, Color(0.8, 0.7, 0.3))
	var board = npc(-right * 9.0 - f * 4.0, Landmarks.word("board"), "jobs for gold", "board", ui, Color(0.55, 0.45, 0.35))
	board.get_child(0).visible = false	# a board, not a person: hide the body, show a sign instead
	box(Vector3(4, 3, 0.4), -right * 9.0 - f * 4.0 + Vector3(0, 1.8, 0), mat("lm_board", Color(0.45, 0.32, 0.2)), false)
	bank_spot(-f * 12.0, "Inn\n(step in: bank gold and rest)")
	label("Safe ground: no fighting inside the walls", Vector3(0, 3, 0) + f * (HALF - 3.0), 28, Color(0.7, 1.0, 0.8))


func host_start():
	pass


func _notification(what):
	if what == NOTIFICATION_READY:
		Landmarks.add_safe(Zones.key_of(self), global_position, HALF + 2.0)
