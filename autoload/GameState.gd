## GameState.gd - Autoload singleton (Stage 1)
##
## Central hub for cross-scene data: world seed, zone definitions and the
## flat color palette used everywhere in the game. Later stages will extend
## this with inventory, story flags, unlocked blueprints etc. For Stage 1 it
## stores the tunable world parameters and provides helpers to query which
## zone a world position belongs to.
extends Node

# ---------------------------------------------------------------------------
# Tunables (@export so they can be tweaked from the editor inspector too)
# ---------------------------------------------------------------------------
@export var world_seed: int = 20261015            ## Seed for terrain + scatter noise
@export var world_size: float = 400.0             ## Full side length of the map in meters
@export var chunk_size: float = 80.0              ## One chunk is chunk_size x chunk_size m
@export var terrain_amplitude: float = 16.0       ## Max terrain height variation
@export var water_level: float = -3.0             ## Y coordinate of the ocean surface

# ---------------------------------------------------------------------------
# Zone definitions. Each zone owns a rectangular region of the world plus its
# own flat palette (ground / accent colors). Zones are laid out on a 2x3 grid
# covering the map; the last cell row is the ocean ring handled separately by
# height (anything below water_level reads as "Ocean").
# ---------------------------------------------------------------------------
const ZONES: Array[Dictionary] = [
	{
		"id": "plains",
		"name": "Green Plains",
		"rect": Rect2(0.0, 0.34, 0.5, 0.66),   # normalized x,y,w,h on the map
		"ground_color": Color(0.45, 0.78, 0.35),
		"accent_color": Color(0.24, 0.55, 0.25),
		"tree_color": Color(0.20, 0.65, 0.30),
		"trunk_color": Color(0.45, 0.30, 0.18),
		"rock_color": Color(0.60, 0.62, 0.65),
		"ambient": Color(0.55, 0.80, 0.95),    # sky tint while inside the zone
		"disaster_bias": "storm",              # used by DisasterManager in Stage 9
	},
	{
		"id": "desert",
		"name": "Desert",
		"rect": Rect2(0.5, 0.34, 0.5, 0.66),
		"ground_color": Color(0.96, 0.83, 0.50),
		"accent_color": Color(0.87, 0.66, 0.32),
		"tree_color": Color(0.35, 0.70, 0.35),   # cactus green
		"trunk_color": Color(0.55, 0.42, 0.22),
		"rock_color": Color(0.80, 0.62, 0.38),
		"ambient": Color(1.0, 0.85, 0.55),
		"disaster_bias": "sandstorm",
	},
	{
		"id": "snow",
		"name": "Snow Mountains",
		"rect": Rect2(0.0, 0.0, 0.5, 0.34),
		"ground_color": Color(0.93, 0.96, 1.0),
		"accent_color": Color(0.72, 0.83, 0.95),
		"tree_color": Color(0.20, 0.45, 0.40),   # pine teal
		"trunk_color": Color(0.35, 0.28, 0.22),
		"rock_color": Color(0.62, 0.68, 0.78),
		"ambient": Color(0.75, 0.85, 1.0),
		"disaster_bias": "blizzard",
	},
	{
		"id": "volcano",
		"name": "Volcanic Lands",
		"rect": Rect2(0.5, 0.0, 0.5, 0.34),
		"ground_color": Color(0.32, 0.22, 0.25),
		"accent_color": Color(0.85, 0.30, 0.15),
		"tree_color": Color(0.50, 0.20, 0.20),   # dead trees
		"trunk_color": Color(0.22, 0.15, 0.16),
		"rock_color": Color(0.18, 0.14, 0.17),
		"ambient": Color(0.95, 0.45, 0.30),
		"disaster_bias": "meteor",
	},
	{
		"id": "ocean",
		"name": "Ocean & Islands",
		"rect": Rect2(-1, -1, 0, 0),             # implicit: everything under water
		"ground_color": Color(0.20, 0.55, 0.85),
		"accent_color": Color(0.35, 0.75, 0.95),
		"tree_color": Color(0.25, 0.70, 0.45),   # palm green
		"trunk_color": Color(0.55, 0.40, 0.25),
		"rock_color": Color(0.70, 0.72, 0.60),
		"ambient": Color(0.45, 0.75, 0.98),
		"disaster_bias": "tsunami",
	},
]

## Story progress flag - Stage 9 weakens disasters once the Engine is repaired.
var engine_repaired: bool = false

# ---------------------------------------------------------------------------
# Stage 2: player inventory (assigned by Player._ready), toast notifications
# and resource-gathering hooks that later stages (quests) will subscribe to.
# ---------------------------------------------------------------------------
var inventory: Inventory = null      # set by the Player when it spawns

signal toast_requested(text: String)              # HUD shows these as popups
signal resource_gathered(item_id: String, amount: int)  # QuestManager (Stage 8)


func toast(text: String) -> void:
	toast_requested.emit(text)


func notify_resource_gathered(item_id: String, amount: int) -> void:
	resource_gathered.emit(item_id, amount)


func _ready() -> void:
	# Seed all global RNG consumers deterministically (no OS randomize(): the
	# whole world must regenerate identically from GameState.world_seed).
	random_set()


## Deterministic RNG helper so world generation is reproducible from the seed.
func make_rng(extra_offset: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + extra_offset * 7919
	return rng


# ---------------------------------------------------------------------------
# Coordinate helpers: world space is centered at origin (-half..+half),
# zone rects are normalized 0..1 over the map.
# ---------------------------------------------------------------------------

## Convert a world XZ position into normalized map coordinates 0..1.
func world_to_norm(pos: Vector3) -> Vector2:
	var h := world_size * 0.5
	return Vector2((pos.x + h) / world_size, (pos.z + h) / world_size)


## Which zone dictionary contains this world position? Ocean is checked first:
## any point below the water line belongs to the Ocean & Islands zone even if
## it sits inside another zone's rectangle. Otherwise falls back to Ocean.
func get_zone_at(pos: Vector3) -> Dictionary:
	if pos.y < water_level + 0.6:
		return ZONES.back()
	var n := world_to_norm(pos)
	for z in ZONES:
		if z["id"] == "ocean":
			continue
		var r: Rect2 = z["rect"]
		if r.has_point(n):
			return z
	return ZONES.back()  # outside the map rect grid -> ocean ring


## Convenience lookups used by HUD / world gen.
func get_zone_by_id(id: String) -> Dictionary:
	for z in ZONES:
		if z["id"] == id:
			return z
	return ZONES[0]


func zone_name_at(pos: Vector3) -> String:
	return get_zone_at(pos)["name"]
