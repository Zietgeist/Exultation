extends RefCounted
## Special effects from special materials (crafting.gd: Treasured, Heirloom, Legendary, Mythic).
## Each material family carries one effect. Everything you wear adds up (weapon and armor alike);
## the strength is in "points" (a Treasured material ~1, Mythic ~4, a bit more at high quality).
##   Sunder     (Ingot)       +10% damage per point to tough foes (Thugs, Masters, Bosses)      up to +100%
##   Bloom      (Tulip)       heal 2% of your max health per point on each kill                 up to 15%
##   Prism      (Gem)         each hit arcs to another foe for 12% per point (2 foes at 3+)     up to 60%
##   Gale       (Treesilver)  +6% move speed per point for 3 s after each kill                  up to +40%
##   Thornskin  (Orchid)      8% per point of the damage you take hits the attacker back        up to 50%
## Plus weapon traits: Mace strikes can stun.
## One of these lives on each player (character_body_3d.gd `fx`); apply_gear() fills it in.

const SUNDER = 0.10
const SUNDER_MAX = 1.0
const BLOOM = 0.02
const BLOOM_MAX = 0.15
const PRISM = 0.12
const PRISM_MAX = 0.6
const PRISM_REACH = 6.0
const GALE = 0.06
const GALE_MAX = 0.4
const GALE_TIME = 3.0
const THORNS = 0.08
const THORNS_MAX = 0.5
const STUN_TIME = 1.0
const MINE_FOR = 3.0	# a kill counts as yours if you hit it in the last few seconds

var points := {}		# effect -> points from everything worn
var stun_chance := 0.0	# weapon trait (Mace)
var _gale_left := 0.0


## Lines for an item's description.
static func describe(fx: Dictionary) -> Array:
	var out = []
	for k in fx:
		var v = float(fx[k])
		match k:
			"sunder": out.append("Sunder: +%d%% damage to tough foes" % roundi(minf(v * SUNDER, SUNDER_MAX) * 100))
			"bloom": out.append("Bloom: heal %d%% of your health on each kill" % roundi(minf(v * BLOOM, BLOOM_MAX) * 100))
			"prism": out.append("Prism: hits arc to %d more foe%s for %d%%" % [2 if v >= 3.0 else 1, "s" if v >= 3.0 else "", roundi(minf(v * PRISM, PRISM_MAX) * 100)])
			"gale": out.append("Gale: +%d%% move speed for %ds after each kill" % [roundi(minf(v * GALE, GALE_MAX) * 100), GALE_TIME])
			"thornskin": out.append("Thornskin: %d%% of the damage you take hits back" % roundi(minf(v * THORNS, THORNS_MAX) * 100))
			_: ErrorLog.warn("gear_fx: unknown special effect '%s'" % k)
	return out


func set_gear(fx: Dictionary, stun := 0.0):
	points = fx
	stun_chance = stun


func tick(delta: float):
	_gale_left = maxf(0.0, _gale_left - delta)


## Extra damage multiplier against this foe.
func damage_mult(enemy) -> float:
	if points.has("sunder") and "tier" in enemy and enemy.tier >= 1:
		return 1.0 + minf(points.sunder * SUNDER, SUNDER_MAX)
	return 1.0


## After one of your hits landed (strike = left click).
func after_hit(player, enemy, damage: float, strike: bool):
	if not is_instance_valid(enemy):
		return
	enemy.set_meta("hit_by_me", Time.get_ticks_msec())	# the kill counts as mine for a few seconds
	if strike and stun_chance > 0.0 and randf() < stun_chance and enemy.has_method("stun"):
		enemy.stun(STUN_TIME)
		player._float_text("Stunned!", Color(1.0, 0.9, 0.5))
	if points.has("prism"):
		var share = minf(points.prism * PRISM, PRISM_MAX)
		var arcs = 2 if points.prism >= 3.0 else 1
		var near = []
		for e in Zones.all(player, "enemy"):
			if e != enemy and is_instance_valid(e) and e.global_position.distance_to(enemy.global_position) < PRISM_REACH:
				near.append(e)
		near.sort_custom(func(a, b): return a.global_position.distance_to(enemy.global_position) < b.global_position.distance_to(enemy.global_position))
		for e in near.slice(0, arcs):
			player._show_beam(e.global_position, Color(0.75, 0.6, 1.0))
			e.set_meta("hit_by_me", Time.get_ticks_msec())
			e.take_damage(damage * share)


## A foe died. If you hit it lately, your on-kill effects go off.
func on_kill(player, enemy):
	if not enemy.has_meta("hit_by_me") or Time.get_ticks_msec() - int(enemy.get_meta("hit_by_me")) > MINE_FOR * 1000.0:
		return
	if points.has("bloom"):
		player.health = minf(player.MAX_HEALTH, player.health + player.MAX_HEALTH * minf(points.bloom * BLOOM, BLOOM_MAX))
	if points.has("gale"):
		_gale_left = GALE_TIME


func speed_mult() -> float:
	if _gale_left > 0.0 and points.has("gale"):
		return 1.0 + minf(points.gale * GALE, GALE_MAX)
	return 1.0


## You took `amount` from `source`: part of it hits back.
func reflect(source, amount: float):
	if not points.has("thornskin") or source == null or not is_instance_valid(source) or not source.has_method("take_damage") or not "tier" in source:
		return
	source.take_damage(amount * minf(points.thornskin * THORNS, THORNS_MAX))
