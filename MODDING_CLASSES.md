# Making a class (modding)

Every class is one `.json` file. No code needed for most ideas.

**Where to put it**
- Built-in classes: `classes/`
- Mods: `mods/classes/` in the game folder, or `user://mods/classes/` (the player's save folder)
- A mod with the same `"id"` as a built-in class replaces it.

**What goes in the file**
```json
{
	"id": "bard",
	"order": 6,
	"name": "Bard",
	"role": "Support",
	"about": "Shown on the start screen.",
	"stats": {"health": 1.0, "speed": 1.0},
	"energy": {"regen": 0.3, "per_damage_taken": 0.0, "per_meter_moved": 0.0},
	"skills": {
		"E": {"id": "song", "name": "Song", "cost": 3, "cooldown": 0, "effect": "totem",
			"params": {"duration": 10, "damage_per_second": 20, "radius": 6, "max": 1},
			"per_rank": {"duration": 2},
			"about": "Tooltip text."},
		"Q": {...},
		"F": {...}
	}
}
```

- `stats`: multipliers on base health (100) and speed (10).
- `energy`: regen per second, energy per point of damage taken, energy per meter run.
- `per_rank`: added to `params` for each rank above 1. Skills rank up by use (10, 30, 70, 150 uses).
- `cooldown`: seconds (optional).

**Effects you can use** (and their params)
| effect | params |
|---|---|
| heal_self | amount |
| damage_boost | multiplier (the cap with every stack; stacks add up evenly), duration, max_stacks |
| shield | absorb, duration |
| blast | damage, screen_share |
| thorns_aura | duration, damage_per_second, reflect, screen_share |
| drain_aura (toggle) | energy_per_second, share_per_enemy (max-life share per enemy in range), max_share_per_second, min_per_second, heal_share, screen_share |
| mending | heal, jumps, duration; optional solo_boost_multiplier, solo_boost_duration, solo_boost_max_stacks (solo at full health it stacks damage like Boost) |
| dash | distance, safe_time |
| whirlwind | duration, damage_per_second, radius, speed_bonus |
| totem | duration, radius, max, and EITHER strike_power, sweep_power, sweep_when (fights with your weapon: Strike the toughest foe, or Sweep when sweep_when+ are close) OR damage_per_second (zaps the 3 closest) |
| root_field | duration, screen_share, damage |
| script | your own: `"script": "res://mods/my_skill.gd"` with `func run(player, params) -> bool` |

**World names**: a skin can rename classes and skills:
`"classes": {"bard": "Minstrel"}`, `"skills": {"song": "War Song"}`.

Mistakes (unknown effect, missing skill, bad JSON) show up in the red error banner and `logs/error_log.txt`.
