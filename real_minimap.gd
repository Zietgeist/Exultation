extends Control
## The mini-map in a Real Place (top-right): the streets around you, enemies, bosses (gold; an arrow at
## the edge when they're farther away), turned allies, the Return ring, and you in the middle. North is up.
## real_zone.gd does the drawing (draw_map); this just centers it on you and keeps it fresh.

var zone = null			# real_zone.gd
var meters := 160.0		# ground shown across
var _t := 0.0


func _ready():
	clip_contents = true	# nothing drawn outside the little square
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta):
	_t -= delta
	if _t <= 0.0:
		_t = 0.1
		queue_redraw()


func _draw():
	var view = Rect2(Vector2.ZERO, size)
	draw_rect(view, Color(0.05, 0.05, 0.07, 0.85))
	var me = Zones.player
	if zone == null or not is_instance_valid(zone) or me == null or not is_instance_valid(me):
		return
	var s = size.x / meters
	var offset = size / 2.0 - Vector2(me.global_position.x, me.global_position.z) * s
	zone.draw_map(self, offset, s, view)
	draw_rect(view, Color(0.3, 0.9, 1.0), false, 2.0)
