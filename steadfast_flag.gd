extends CanvasLayer
## Pop-up flag: you've cleared 99% of a zone (Steadfast). A banner across the top of the screen for a
## few seconds, and a flag planted where you stand (Traits.on_zone_cleared makes both).

const GOLD = Color(1.0, 0.85, 0.3)
var zone_name := ""


func _ready():
	layer = 60
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size = Vector2(620, 110)
	panel.position = Vector2(-310, 115)	# below the center notices
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.04, 0.92)
	style.border_color = GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	row.add_child(_flag_icon())
	var text = VBoxContainer.new()
	row.add_child(text)
	var t = Label.new()
	t.text = "STEADFAST!"
	t.add_theme_font_size_override("font_size", 34)
	t.add_theme_color_override("font_color", GOLD)
	text.add_child(t)
	var s = Label.new()
	s.text = "99%% of %s cleared. You held your ground." % zone_name
	s.add_theme_font_size_override("font_size", 18)
	text.add_child(s)
	panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.4)
	tw.tween_interval(5.0)
	tw.tween_property(panel, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)


## A little flag drawn with two rectangles.
func _flag_icon() -> Control:
	var c = Control.new()
	c.custom_minimum_size = Vector2(70, 86)
	var pole = ColorRect.new()
	pole.color = Color(0.8, 0.8, 0.8)
	pole.position = Vector2(10, 4)
	pole.size = Vector2(5, 80)
	c.add_child(pole)
	var cloth = ColorRect.new()
	cloth.color = GOLD
	cloth.position = Vector2(15, 6)
	cloth.size = Vector2(50, 32)
	c.add_child(cloth)
	return c


## A real flag where you stand (stays for this visit).
static func plant(at_node: Node3D):
	var root = Zones.root_of(at_node)
	if root == null:
		return
	var flag = Node3D.new()
	var pole = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.1
	cyl.height = 5.0
	pole.mesh = cyl
	pole.position.y = 2.5
	pole.material_override = SkinManager.material("flag_pole", Color(0.8, 0.8, 0.8))
	flag.add_child(pole)
	var cloth = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(1.8, 1.1, 0.05)
	cloth.mesh = b
	cloth.position = Vector3(0.95, 4.3, 0)
	var m = StandardMaterial3D.new()
	m.albedo_color = GOLD
	m.emission_enabled = true
	m.emission = GOLD
	m.emission_energy_multiplier = 0.6
	cloth.material_override = m
	flag.add_child(cloth)
	root.add_child(flag)
	flag.global_position = at_node.global_position + Vector3(1.5, -1.0, 0)
