## Terrain.gd - Shared, deterministic terrain sampling (Stage 1)
##
## IMPORTANT: both the chunk mesher AND the player controller call these
## functions, so the ground is perfectly consistent without relying on physics
## raycasts. Everything derives from GameState.world_seed, so the same seed
## always produces the same planet.
class_name Terrain
extends RefCounted

# Cached noise layers, built once per seed.
static var _height_noise: FastNoiseLite
static var _detail_noise: FastNoiseLite
static var _island_noise: FastNoiseLite
static var _ridge_noise: FastNoiseLite
static var _cached_seed: int = -999999


## (Re)build the noise stack for the current GameState seed.
static func ensure_built(seed_value: int) -> void:
	if _cached_seed == seed_value and _height_noise != null:
		return
	_cached_seed = seed_value

	_height_noise = FastNoiseLite.new()
	_height_noise.seed = seed_value
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.0045          # broad hills / basins
	_height_noise.fractal_octaves = 4

	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = seed_value + 101
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.frequency = 0.006
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = 3

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = seed_value + 202
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.frequency = 0.02            # small bumps

	_island_noise = FastNoiseLite.new()
	_island_noise.seed = seed_value + 303
	_island_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_island_noise.frequency = 0.003           # shapes ocean basins & islands


## Height in meters at world XZ. Pure function of position + seed.
static func get_height(x: float, z: float) -> float:
	ensure_built(GameState.world_seed)
	var amp := GameState.terrain_amplitude

	# Base rolling terrain (-1..1 roughly).
	var base := _height_noise.get_noise_2d(x, z)

	# Ridges: strong in the northern half (snow mountains zone) only.
	# Normalized "northness": z runs from -half(north) to +half(south).
	var half := GameState.world_size * 0.5
	var north := clampf((0.0 - z) / half, 0.0, 1.0)             # 1 at far north
	var ridge := absf(_ridge_noise.get_noise_2d(x, z))          # 0..1 ridged
	var volcano_n := clampf((0.0 - z) / half - 0.3, 0.0, 1.0)   # NE gets a bump too
	var ridge_term := ridge * ridge * (6.0 * north + 3.0 * volcano_n)

	var h := (base * amp) + ridge_term

	# Island mask: push the outer ring and some patches below sea level so the
	# Ocean zone has real water and scattered islands.
	var isl := _island_noise.get_noise_2d(x, z)
	h += isl * amp * 0.7

	# Flatten the desert a touch (gentle dunes instead of hills) by pulling
	# heights toward a plateau when inside the desert rect.
	var n := GameState.world_to_norm(Vector3(x, 0, z))
	var des: Rect2 = GameState.get_zone_by_id("desert")["rect"]
	if des.has_point(n):
		var flat := lerpf(h, _detail_noise.get_noise_2d(x, z) * 2.2 + 1.5, 0.55)
		h = flat

	# Small high-frequency detail everywhere.
	h += _detail_noise.get_noise_2d(x * 1.7, z * 1.7) * 1.2

	# Volcanic lands get one prominent cone near their center.
	var volc_center := norm_to_world_pos(0.75, 0.17)
	var d_cone := Vector2(x - volc_center.x, z - volc_center.z).length()
	if d_cone < 55.0:
		h += (1.0 - d_cone / 55.0) * 26.0

	return h


static func norm_to_world_pos(nx: float, nz: float) -> Vector3:
	var half := GameState.world_size * 0.5
	return Vector3(nx * world_span() - half, 0, nz * world_span() - half)


static func world_span() -> float:
	return GameState.world_size


## Surface normal via central differences - used for slope checks & tree tilt.
static func get_normal(x: float, z: float, eps: float = 1.0) -> Vector3:
	var hl := get_height(x - eps, z)
	var hr := get_height(x + eps, z)
	var hd := get_height(x, z - eps)
	var hu := get_height(x, z + eps)
	return Vector3(hl - hr, 2.0 * eps, hd - hu).normalized()


static func is_underwater(x: float, z: float) -> bool:
	return get_height(x, z) < GameState.water_level
