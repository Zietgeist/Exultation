extends Control
## HUD arrow in big zones with regions: points from you toward the heart of your region while its
## boss still stands, otherwise to the nearest region still to free (zone_features.compass_target).
## Hidden once you're there, while a window is open, and in zones without regions. Added by hud_control.gd.

const RADIUS_SHARE = 0.36	# how far from the middle of the screen the arrow sits
const ARRIVED = 30.0		# closer than this: no arrow

var _target := {}
var _dist := 0.0
var _dir := Vector2.ZERO
var _t := 0.0


func _ready():
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta):
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.1
	_target = {}
	var me = Zones.player
	var f = Zones.local_first("zone_features")
	if not GameState.ui_open and f and me and is_instance_valid(me) and me.is_inside_tree():
		var tgt = f.compass_target(me.global_position)
		if not tgt.is_empty():
			var p = f.to_global(tgt.pos)
			var d = Vector2(p.x - me.global_position.x, p.z - me.global_position.z)	# the camera looks north: screen up = -z
			if d.length() > ARRIVED:
				_target = tgt
				_dist = d.length()
				_dir = d.normalized()
	queue_redraw()


func _draw():
	if _target.is_empty():
		return
	var c = size / 2.0
	var r = minf(size.x, size.y) * RADIUS_SHARE
	var tip = c + _dir * r
	var side = Vector2(-_dir.y, _dir.x)
	var col = Color(_target.get("color", Color.WHITE)).lightened(0.25)
	var pts = PackedVector2Array([tip + _dir * 14.0, tip - _dir * 8.0 + side * 11.0, tip - _dir * 3.0, tip - _dir * 8.0 - side * 11.0])
	draw_colored_polygon(pts, Color(col, 0.85))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.7), 2.0)
	var font = get_theme_default_font()
	var text = "%s  ·  %d m" % [_target.text, roundi(_dist)]
	var at = tip - _dir * 34.0 + Vector2(-150, 6)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 300, 14, 4, Color(0, 0, 0, 0.85))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 300, 14, col)
