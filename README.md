# Broken Engine — Stage 1 (runnable build)

Open-world vehicle-building sandbox, flat "Dumb Ways"-inspired style.
**Target: Godot 4.x (4.3+ recommended), GDScript only, zero external assets.**

## How to run
1. Install Godot 4.3+ (standard edition).
2. Open Godot → **Import** → select this folder's `project.godot`.
3. Press **F5** (Run Main Scene). Everything is generated at runtime from the seed.

## Controls
| Key | Action |
|---|---|
| W A S D | Move |
| Shift | Sprint |
| Space | Jump |
| Mouse | Look (captured; Esc releases in editor play) |
| C | Toggle first/third person camera |
| T | Fast-forward time (hold) |

## What's in this stage
- **Procedural world**: FastNoiseLite heightmap (`world/Terrain.gd`), deterministic
  from `GameState.world_seed`. Chunked streaming with load/unload radius
  (`world/WorldManager.gd`, `world/Chunk.gd`) — one ArrayMesh + trimesh collision
  per chunk, trees/rocks as colored MultiMeshes (one draw call each).
- **5 zones** with own palettes and disaster bias data (`autoload/GameState.gd`):
  Green Plains (spawn), Desert (flattened dunes), Snow Mountains (ridged peaks +
  snow caps), Volcanic Lands (a real cone mountain), Ocean (islands + animated
  translucent water plane).
- **Player controller**: CharacterBody3D, analytic terrain following (no raycasts),
  arcade gravity, sprint/jump, shallow-water drag, procedural bean avatar with dot
  eyes and swinging limbs (`player/Player.gd`).
- **Day/night cycle**: color-keyframed ProceduralSky gradient + sun arc/tint/energy,
  zone ambient tint blended in (`autoload/DayNightManager.gd`).
- **Flat style helper**: cached unshaded/flat/emissive materials (`world/FlatStyle.gd`).
- **HUD**: zone name, clock, compass, control hints (`ui/HUD.gd`).

## Architecture notes for later stages
- Autoloads registered in `project.godot`: `GameState`, `DayNightManager`.
  Stages 6–10 will add `QuestManager`, `DisasterManager`, `SaveSystem`,
  `DialogueManager` there.
- All tunables are `@export` on autoloads/scripts: world size, chunk size, seed,
  terrain amplitude, water level, day length, gravity scale, speeds.
- Terrain height is a *pure function* (`Terrain.get_height`) — vehicles (Stage 4/5),
  mine entrances (Stage 6) and disasters (Stage 9) must sample it the same way.

## Known limitations (by design for Stage 1)
- No resources/inventory/tools yet (Stage 2), no building (Stage 3), no vehicles (4–5).
- Water waves are a whole-plane bob; shader vertex waves arrive with ships (Stage 5).
- Trees/rocks are decorative (not minable) and have no collision bodies yet.
- No NPCs/mines/dungeons/disasters/saves (Stages 6–10).
- Player can walk off the map edge at ±200 m; invisible walls come with quest markers.
- Physics props disabled far away by design (chunks unload); terrain walking is
  unaffected because ground is sampled analytically.
