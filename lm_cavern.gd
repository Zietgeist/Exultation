extends "res://lm_base.gd"
## Cavern entrance (Cave / Subway Tunnels / Mine Shaft). Step into the opening to go underground:
## a dark, winding party dungeon (Cavern.tscn, cavern.gd) with geodes and better ore.
## Friends get the usual Follow / Stay choice. Each cavern is its own copy, shared by the party.

const CAVERN = "res://Cavern.tscn"


func title_height() -> float:
	return 10.0


func build():
	var f = facing()
	var right = Vector3(f.z, 0, -f.x)
	match SkinManager.props_style():
		"zombie":	# subway stairs: a railing box and a sign
			var c = mat("lm_subway", Color(0.4, 0.42, 0.4))
			box(Vector3(10, 1, 1), right * 0 + f * -5 + Vector3(0, 0.5, 0), c, true, atan2(-f.z, f.x) + PI / 2)
			box(Vector3(0.6, 4, 0.6), right * 5 + Vector3(0, 2, 0), c)
			box(Vector3(4, 1.5, 0.3), right * 5 + Vector3(0, 4.5, 0), mat("lm_sign", Color(0.2, 0.5, 0.25), true), false)
		"scifi":	# a mine headframe
			var c = mat("lm_mine", Color(0.5, 0.52, 0.58))
			for s in [-1, 1]:
				box(Vector3(0.8, 10, 0.8), right * 4 * s + Vector3(0, 5, 0), c)
			box(Vector3(9, 0.8, 0.8), Vector3(0, 10, 0), c, false, atan2(-right.z, right.x))
		_:	# a rocky hill with a dark mouth
			var rock = mat("lm_rock", Color(0.38, 0.35, 0.32))
			box(Vector3(18, 8, 12), -f * 5 + Vector3(0, 4, 0), rock, true, atan2(-f.z, f.x) + PI / 2)
			box(Vector3(6, 5, 1), f * 1.2 + Vector3(0, 2.5, 0), mat("lm_dark", Color(0.02, 0.02, 0.03)), false, atan2(-right.z, right.x))
	var gate = load("res://portal.gd").new()
	gate.target_scene = CAVERN
	gate.travel_key = "%s#%s_%s" % [CAVERN, zone_path.get_file().get_basename(), info.id]	# the same cave for the whole party
	gate.travel_info = {parent = zone_path, id = info.id, name = info.name, zone = info.zone,
		q = GameState.zone_quality(zone_path), back_scene = zone_path, back_pos = info.pos + f * 10.0 + Vector3(0, 1, 0)}
	gate.label_text = "Go down\n" + ("(cleared)" if state().has("cleared") else "")
	gate.color = Color(0.6, 0.5, 0.4)
	gate.arm_time = 1.0
	gate.position = f * 2.0
	add_child(gate)
