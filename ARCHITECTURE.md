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
- Hits, roots and stuns go to the host (`_hit`, `_root`, `_stun`); damage and heals go to the player they target.
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
- ZONES are saved too (`GameState` "Zone memory"): each spiral zone's memory (spawner, terrain, obstacles, fog,
  features) goes to `zones/<Zone>.dat` (zstd-compressed `store_var`), in the character folder, or in
  `user://parties/<id>_zones/` while a party is active. Saved on unload, every 5 min, and on quit; read lazily
  with `GameState.zone_memory_of(path)` (never read `zone_memory` directly). Clearing a zone resets its save.
  Bump `ZONE_SAVE_VERSION` if a saved part's shape changes (old saves then start fresh, loudly).

## Errors
- Fail loudly: `ErrorLog.fail(...)` / `ErrorLog.warn(...)`. They show in the red banner and
  `logs/error_log.txt`. No silent fallbacks.

## Autoloads (global systems)
ErrorLog, Account, GameState, SessionManager, SkinManager, Crafting, Classes, Net, SteamLink,
Trials, Zones, Story, Rivals, Traits, Travel (fast_travel.gd), Party, Landmarks, Regions, Helpers.

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
- The player always hits layer 1; it hits layer 3 unless worn gear has `phase_mobs` (nothing sets it since Oct 2026: walking through enemies moved to flying with wings).
- Enemy pathing (`pathing.gd`): Trash walks straight. Thug/Master/Boss check every ~0.5 s if a wall is in the way; if so, A* on a 2 m grid (StaticBody3D = solid, remembered 20 s) gives waypoints. Too far apart (>96 m box) = walk straight.
- Hills (rubble piles in Zombie) are sloped convex mounds, not walls: anyone can climb over at 25% speed (`GameState.HILL_SPEED`, checked after move_and_slide via `GameState.on_hill`). Pathing ignores them.

## Real-world maps (PROTOTYPE)
- `real_map.gd`: address/lat,lon -> LocationIQ (key in `geo_key.txt`, git-ignored) -> Overpass (OpenStreetMap) -> gray-box buildings/roads/parks.
- Off-limits check before building: military areas, camps, memorial sites, battlefields, atrocity names within 1 km, plus `real_map_blocklist.json`. Never log or share the typed address.
- In the game: the "Real Place" ring at Home (`real_place_gate.gd`) opens `real_place_ui.gd` (address box) -> `Net.go("res://RealZone.tscn", "...#id", spawn, info)`. `real_zone.gd` builds the map, 8 packs, a Return ring; a one-off copy like a Trial Ground (not saved).
- SOLO ONLY for now (online, friends' games would receive the place). The address is dropped before travel; only meters-around-(0,0) geometry goes into the zone.
- Preview without enemies: "Real place (test)" on the character screen -> `RealMapTest.tscn`.
- Must show "(c) OpenStreetMap contributors" wherever a real map is shown.

## Helpers you rescue (`helpers.gd`, autoload "Helpers")
- Captives: Zone 2 cook, Zone 3 Smith's assistant, Zone 4 Alchemist's assistant. Held at a camp by a Master + 10 Trash; G frees them once no enemy is within 14 m. Saved per character (helpers.cfg).
- At Home they stand between the Return Portal and the fast-travel stop. Their work starts on `SessionManager.break_started` (walking into Home).
- Cook: the meal is served when you leave Home; strength = `cook_power(minutes)` (exponential, 100% at 4 min) applied to all three meal buffs. Once rescued, the Inn stops selling them.
- Buffs are strengths 0..1 of `GameState.BUFF_MAX` (`buff_power`, `buff_bonus`, `buff_text`). Never treat `buffs[id]` as a bool.
- Assistants: take all stored raw for their shop, refine it in 3 min with +1 per 3 (into `Crafting.stash`).

## Farmland (open_field map, Zone 1 and "Overgrown Fields")
- `terrain_generator.gd` `_layout_farmland`: river with bridges (`_layout_river`), fenced fields (wall type "fence" + crop "deco" rows + a pack site style "field" that the spawner fills with a herd, `SITE_PACKS.field`), barns (piece kind "barn", look from `props.gd barn()`). All saved/rebuilt like other pieces.

## Guide (character window C -> Guide tab)
- `guide.json`: the hand-written topics (group, title, text with [b] BBCode). Tokens: `{el:shadow}`, `{name:enemy_trash}`, `{class:tank}`, `{bag_min}`/`{bag_max}`, so names follow the skin.
- `guide.gd`: loads it and writes the "live" parts from game data (classes, races, materials, recipes, Inn, trials, traits, worlds, zone damage types). Those stay correct by themselves.
- Add or change a system -> update its topic in `guide.json` (hand-written numbers there do NOT update themselves).

## Big zones: regions, encounters, hordes (`regions.gd` autoload "Regions", `zone_features.gd`)
- Zone 6 and up (`Regions.is_big`): encounters every ~260 m (cache, story stone, champion, ambush) and the
  horde director (`zone_director.gd`, host only). Zone 7 and up (`Regions.has_regions`): a grid of regions
  (~900 m each: Zone 7 = 2x2 ... Zone 10 = 8x8), each with a name (skin "regions" words), a map template,
  an element and a heart (`region_heart.gd`) where a region boss waits.
- All of it is SEEDED from the zone path (like landmarks), so it's the same for everyone and isn't sent online.
  Hearts and encounters are only built near players (`zone_features.gd` streams them) - keep it that way for Zone 10.
- `terrain_generator.gd` builds region zones square by square (`_build_regions`, `_area`, `_bounds()`); hearts are keep-out.
- State this session: `zone_features.save_state()` (region bosses down, champions/ambushes done) is a zone-memory part
  ("features") and goes to joined players with the layout. Events: `Net.feature_event` -> `zone_features.net_event`.
  Caches and stones are personal (`Regions.done`).
- SAVED between sessions (big zones): freed regions + zone bosses beaten (`Regions.progress/record`, party or
  `regions.cfg`); the spawner empties freed regions and starts with their credit (`_apply_saved_regions`).
  Clearing the zone resets it. Regions entered are saved too (map names).
- Feature foes carry meta "landmark" = "feature" (the spawner never saves or sleeps them). Their kills count toward the
  2nd boss; a region boss adds 10% of `min_clear` (like closing a rift).

## Crafting (`crafting.gd`, `gear_fx.gd`)
- Item = recipe TYPE (BASES: 10 weapon types, armor, rings, potions) x main material QUALITY (x1.25 per step on the
  item's own power AND every attribute) + creative-slot materials (attributes; special materials add effects).
- Shrine ladder alternates: odd levels = better recipes (`recipe_level`), even levels = special material tiers
  (`material_tier`: Treasured, Heirloom, Legendary, Mythic; stash ids like `t2_ingot`). Precision's Masterwork recipe
  covers every weapon type: ids `adv:precision:<level>:<weapon>` (3-part ids still mean the family's own base).
- Special effects live in item attrs as `fx_<name>` and are applied by `gear_fx.gd` (one per player, `player.fx`).
  Add an effect: material family in `Crafting.FX`, numbers + `describe` + hook in `gear_fx.gd`.

## Wings and Daddy (`wings_flight.gd`, `daddy.gd`)
- Every race gets a "wings" slot (`SkinManager.race_slots` adds it). Wings items have `stats.flight` (seconds).
- Flight lives in `player.flight`: hold Shift; it replaces gravity, lifts you to FLY_HEIGHT, turns off the enemy
  collision layer, makes you immune, blocks attacks/skills, and clamps you inside the zone.
- `player.stun(seconds, text)` (puppets: `Net.stun_player`). Daddy (Zone 2, `daddy.gd`) uses it; his death goes out
  with `Net.group_event(node, "daddy_camp", ...)` and each player gets wings via `Crafting.grant_wings()`.
- Per-skin wing looks: not yet (`wings_flight._make_wings` is one shape).

