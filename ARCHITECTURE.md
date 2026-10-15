# Exultation architecture (short map for Claude and future helpers)

Read this before big changes. Keep it short; update it when a rule changes.

## The world and zones
- The game is ONE scene, `World.tscn` (player, camera, HUD). Zones (Home, Zone 1...) load into it,
  each in its own SubViewport with its own physics, so several zones can run at once.
- Rules (from `zones.gd`):
  - Never use `get_tree().current_scene` to mean "the zone". Use `Zones`.
  - Never use `get_tree().get_nodes_in_group()` for zone things. Use `Zones.all(self, "enemy")`,
    `Zones.first(self, "zone_spawner")`; UI uses `Zones.local_first(...)`, `Zones.local_path()`.
  - Things added to the world (effects, drops) go in a zone: `Zones.root_of(self).add_child(x)`.
  - All travel goes through `Net.go()` (solo, it just travels).

## Online (host and clients) - `net.gd`
- The HOST runs every zone that has a player in it: enemies, kills, layouts, bosses. The host decides.
- CLIENTS show only their own zone, with "mirror" copies of the host's enemies.
- Hits and roots go to the host (`_hit`, `_root`); damage and heals go to the player they target.
- Every player keeps their own loot, gold, gear, unlocks and skill ranks.
- Rules:
  - Anything that changes the shared world checks `Net.is_client()` and sends it to the host.
  - Every RPC that takes an enemy id or zone key checks it exists and matches before using it.
  - Prefer one event message ("enemy died", "scene event") over sending lots of state.
  - New systems should call small functions in `net.gd` (like `Net.scene_event`), not add RPCs
    all over the code.

## Classes and skills (data, not code)
- Each class is a file in `classes/*.json` (see `MODDING_CLASSES.md`). Mods: `mods/classes/`.
- Skills point at "effects". To add a new effect: write it in `skill_runner.gd` `_run()` AND add its
  name to `ClassManager.EFFECTS`. If you forget either one, the game shows a loud error.

## Names and looks
- Code uses IDs (`enemy_trash`, `zone_2_floor`). Skins (`skins/*.json`) give names and colors
  through `SkinManager`. Never hard-code a display name.

## Saves
- Every system asks `Account.path("its_file.cfg")` for where to save. Each character has its own
  folder: `user://characters/<id>/`. Account-wide things (controls, settings, play time) stay in `user://`.

## Errors
- Fail loudly: `ErrorLog.fail(...)` / `ErrorLog.warn(...)`. They show in the red banner and
  `logs/error_log.txt`. No silent fallbacks.

## Autoloads (global systems)
ErrorLog, Account, GameState, SessionManager, SkinManager, Crafting, Classes, Net, SteamLink,
Trials, Zones, Story, Rivals, Traits, Travel (fast_travel.gd), Party, Landmarks.

## Keeping files manageable
- The biggest scripts are `character_body_3d.gd` (~900 lines) and `net.gd` (~740). That's fine for now.
- When a script passes ~1000 lines, or a new feature would add a whole new job to it, move that job
  into its own script (like `auto_fight.gd` and `skill_runner.gd` already are) instead of growing it.
- Player "can I act right now?" checks (`GameState.ui_open`, typing, disguised, trial ward) are spread
  out. If a new mode gets added, consider one shared `can_act()` check instead of another flag.

## Repo notes
- `.uid` files MUST stay in git (Godot 4.4+ uses them to keep links between files working).
- `addons/godotsteam/` holds large Steam libraries (~94 MB). Fine for now; don't add more binaries
  without a reason.

## Physics layers
- Layer 1: walls, props, players. Layer 3: enemies (set in `enemy.gd` `_ready`). Enemies collide with 1 and 3.
- The player always hits layer 1; it hits layer 3 unless worn gear has `phase_mobs` (Windrunner Boots, the shrine boots), then it walks through enemies.
- Enemy pathing (`pathing.gd`): Trash walks straight. Thug/Master/Boss check every ~0.5 s if a wall is in the way; if so, A* on a 2 m grid (StaticBody3D = solid, remembered 20 s) gives waypoints. Too far apart (>96 m box) = walk straight.
- Hills (rubble piles in Zombie) are sloped convex mounds, not walls: anyone can climb over at 25% speed (`GameState.HILL_SPEED`, checked after move_and_slide via `GameState.on_hill`). Pathing ignores them.
