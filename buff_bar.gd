extends CanvasLayer
## Buff icons in the top-right corner: everything helping you right now, with a timer when
## the buff runs out on a clock (potion ward, Boost stacks, shield, auras...).
## Inn treats last until your next rest (banking gold at Home), so they show "rest" instead.
## Hover an icon for what it does. Added by hud_control.gd.

const ICONS = preload("res://icons.gd")
const SIZE = 40.0

var row: HBoxContainer
var _icons := {}		# buff id -> Control (kept between updates so tooltips don't flicker)
var _t := 0.0


func _ready():
	layer = 40
	row = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_top = 8
	row.offset_right = -10
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	add_child(row)


func _process(delta):
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var want = _active()
	for id in _icons.keys():
		if not want.has(id):
			_icons[id].queue_free()
			_icons.erase(id)
	for b in want.values():
		var ic = _icons.get(b.id)
		if ic == null:
			ic = _BuffIcon.new()
			ic.custom_minimum_size = Vector2(SIZE, SIZE + 14)
			row.add_child(ic)
			_icons[b.id] = ic
		ic.data = b
		ic.tooltip_text = b.name + "\n" + b.about
		ic.queue_redraw()


## Everything active: [id] -> {id, kind, color, name, about, time (-1 = no clock), text, stacks}
func _active() -> Dictionary:
	var out = {}
	var p = Zones.player
	if p == null or not is_instance_valid(p):
		return out
	var add = func(id: String, kind: String, color: Color, bname: String, about: String, time := -1.0, text := "", stacks := 0):
		out[id] = {id = id, kind = kind, color = color, name = bname, about = about, time = time, text = text, stacks = stacks}
	# Inn treats (until your next rest)
	var inn_kind = {"meal": "meal", "sleep": "sleep", "tonic": "potion"}
	var inn_col = {"meal": Color(1.0, 0.7, 0.3), "sleep": Color(0.6, 0.7, 1.0), "tonic": Color(0.5, 1.0, 0.6)}
	for id in GameState.buffs:
		if not GameState.has_buff(id):
			continue
		var o = GameState.INN_OFFERS.get(id, {})
		add.call("inn_" + id, inn_kind.get(id, "potion"), inn_col.get(id, Color.WHITE), o.get("name", id),
			GameState.buff_text(id) + "\nLasts until your next rest (bank your gold at Home).", -1.0, "rest")
	# Potion ward and haste
	if p.ward_time > 0.0:
		var bits = []
		for el in p.ward:
			if p.ward[el] > 0.0:
				bits.append("%s +%d%%" % [SkinManager.element_label(el), roundi(p.ward[el] * 100)])
		if p.haste > 0.0:
			bits.append("move +%d%%" % roundi(p.haste * 100))
		add.call("ward", "ward", Color(0.6, 0.9, 1.0), "Potion ward", "Resists: " + (", ".join(bits) if bits.size() > 0 else "-"), p.ward_time)
	# Skills
	var sk = p.skills
	if p.dps_boost_stacks > 0 and sk:
		var longest = 0.0
		for t in sk.boost_timers:
			longest = max(longest, t)
		add.call("boost", "boost", Color(1.0, 0.45, 0.25), "Damage boost", "x%.1f damage (%d stacks). Press again to refresh every stack." % [p.boost_mult, p.dps_boost_stacks], longest, "", p.dps_boost_stacks)
	if sk:
		if sk.shield_hp > 0.0:
			add.call("shield", "shield", Color(0.5, 0.8, 1.0), "Shield", "Soaks %d more damage." % sk.shield_hp, sk.shield_time)
		if not sk.thorns.is_empty():
			add.call("thorns", "thorns", Color(0.6, 0.9, 0.4), "Thorns aura", "Hurts enemies that hit you.", float(sk.thorns.time))
		if not sk.whirl.is_empty():
			add.call("whirl", "whirl", Color(0.9, 0.9, 1.0), "Whirlwind", "Spinning: hits everything close.", float(sk.whirl.time))
		if not sk.drain.is_empty():
			add.call("drain", "drain", Color(0.8, 0.3, 0.5), "Life drain", "On: drains nearby enemies to heal you.", -1.0, "on")
		if sk.totems.size() > 0:
			add.call("totem", "totem", Color(0.9, 0.75, 0.4), "Totems", "%d totem(s) fighting for you." % sk.totems.size(), -1.0, "", sk.totems.size())
		if not sk.mending.is_empty():
			add.call("vow", "vow", Color(0.5, 1.0, 0.6), "Mending Vow", "Heals %d, %d jump(s) left." % [sk.mending.heal, sk.mending.jumps], float(sk.mending.get("time", -1.0)))
	# The Survivor's job: Parley (V)
	if not Landmarks.recruit.is_empty():
		var j = Landmarks.recruit
		if Landmarks.disguised:
			add.call("parley", "parley", Color(0.5, 0.95, 0.5), "Disguised", "Enemies take you for one of their own. Auto-attack is off.\nPress V next to a Trash or Thug to talk (about half join).\nRecruiting for %s: %d / %d.\nAttacking, or being hit, drops the disguise." % [j.name, j.have, j.need], -1.0, "%d/%d" % [j.have, j.need])
		else:
			add.call("parley", "parley", Color(1.0, 0.55, 0.4), "Found out", "Fight back, then press V to put your disguise back on (once nothing is chasing you).\nRecruiting for %s: %d / %d." % [j.name, j.have, j.need], -1.0, "V")
	# Your pet after a tonic
	if p.pet and is_instance_valid(p.pet) and p.pet.well_fed > 0.0:
		add.call("petfed", "meal", Color(0.55, 0.9, 1.0), "%s is well fed" % p.pet.pet_name(), "From a tonic: 25% faster, gathers quicker, +20% health.", p.pet.well_fed)
	# Patient / Driven (pomodoro)
	if Traits.patient_stacks > 0:
		add.call("patient", "patient", Color(0.7, 0.95, 0.7), "Patient", "+%d%% damage and max health (1%% per rest you took on time, up to 10)." % Traits.patient_stacks, -1.0, "", Traits.patient_stacks)
	if Traits.is_driven():
		add.call("driven", "driven", Color(1.0, 0.55, 0.25), "Driven", "Past your flow time: total %+d%%. It drops 2%% each minute you keep going. Rest soon!" % roundi(Traits.rest_bonus() * 100.0))
	return out


## One icon: dark square, the drawn icon, stacks in the corner, the timer underneath.
class _BuffIcon extends Control:
	var data := {}

	func _draw():
		if data.is_empty():
			return
		var sq = Rect2(0, 0, SIZE, SIZE)
		draw_rect(sq, Color(0.08, 0.08, 0.1, 0.85))
		draw_rect(sq.grow(-1), data.color.darkened(0.2), false, 2.0)
		ICONS.draw(self, data.kind, sq.grow(-6), data.color)
		var font = get_theme_default_font()
		if data.stacks > 1:
			var s = str(data.stacks)
			draw_string_outline(font, Vector2(SIZE - 12, SIZE - 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
			draw_string(font, Vector2(SIZE - 12, SIZE - 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		var t = data.text
		if data.time >= 0.0:
			t = ("%ds" % ceili(data.time)) if data.time < 60.0 else ("%d:%02d" % [int(data.time) / 60, int(data.time) % 60])
			var frac = clamp(data.time / 30.0, 0.0, 1.0)	# a thin bar that drains as it runs out
			draw_rect(Rect2(2, SIZE - 4, (SIZE - 4) * frac, 2), data.color)
		if t != "":
			draw_string_outline(font, Vector2(0, SIZE + 12), t, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 12, 4, Color.BLACK)
			draw_string(font, Vector2(0, SIZE + 12), t, HORIZONTAL_ALIGNMENT_CENTER, SIZE, 12, Color(0.95, 0.95, 0.95))
